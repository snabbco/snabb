module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")
local counter = require("core.counter")
local packet = require("core.packet")
local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")
local ipsum = require("lib.checksum").ipsum
local datagram = require("lib.protocol.datagram")

transport = {
   shm = {
      ["bad-checksum"] = { counter }
   }
}

local params = {
   src = { required = true },
   dst = { required = true },
   links = { default = {} },
}
local proto_params = {
   proto = { required = true },
}

local ether_header_size = ethernet:sizeof()
local ipv4_header_size = ipv4:sizeof()
local ipv4_header_ptr_t = ipv4._header.ptr_t
local combined_header_size = ether_header_size + ipv4_header_size
-- Offsets in units of uint16_t
local csum_offset = ffi.offsetof(ipv4._header.t, 'checksum')/2
local length_offset = ffi.offsetof(ipv4._header.t, 'total_length')/2

function transport:new (arg)
   local conf = lib.parse(arg, params)
   local o = {}
   o._discard_link = link.new("ipv4_proto_discard")
   o._proto_links_out = ffi.new("struct link *[256]", o._discard_link)

   o._proto_infos = {}
   o._proto_infos_by_name = {}
   for name, arg in pairs(conf.links) do
      local proto = lib.parse(arg, proto_params).proto
      assert(proto > 0 and proto < 255, "Illegal protocol: "..proto)

      -- Construct a combined Ethernet/IPv4 header which will be
      -- prepended to downstream packets.
      local dgram = datagram:new()
      dgram:push(ipv4:new({ src = conf.src,
                            dst = conf.dst,
                            ttl = 64,
                            flags = 0x2, -- Don't fragment
                            protocol = proto }))
      dgram:push(ethernet:new({ type = 0x0800 }))
      dgram:new(dgram:packet(), ethernet) -- Reset parse stack

      local proto_info = { link_name = name,
                           proto = proto,
                           combined_header = {
                              ptr = ffi.cast("uint8_t *", dgram:packet().data),
                              ipv4_ptr = ffi.cast("uint16_t *",
                                                  dgram:packet().data
                                                     + ether_header_size),
                              length = dgram:packet().length } }
      table.insert(o._proto_infos, proto_info)
      o._proto_infos_by_name[name] = proto_info
   end
   o._nprotos = #o._proto_infos

   return setmetatable(o, { __index = transport })
end

function transport:link ()
   for name, l in pairs(self.output) do
      if type(name) == "string" and name ~= "south" then
         local proto_info = assert(self._proto_infos_by_name[name],
                                   "Unconfigured link: "..name)
         self._proto_links_out[proto_info.proto] = l
      end
   end
end

local function prepend(self, i, sout)
   local proto_info = self._proto_infos[i]
   local pin = assert(self.input[proto_info.link_name])
   for _ = 1, link.nreadable(pin) do
      local p = link.receive(pin)
      local total_length = p.length + ipv4_header_size
      local header = proto_info.combined_header
      C.checksum_update_incremental_16(header.ipv4_ptr + csum_offset,
                                       header.ipv4_ptr + length_offset,
                                       total_length)
      p = packet.prepend(p, header.ptr, header.length)
      link.transmit(sout, p)
   end
end

function transport:push ()
   local sin = self.input.south
   local sout = self.output.south
   local discard = self._discard_link
   local links_out = self._proto_links_out

   for _ = 1, link.nreadable(sin) do
      local p = link.receive(sin)
      -- Precondition: incoming packets must have at least an Ethernet
      -- and an IPv4 header
      assert(p.length >= combined_header_size)
      local ipv4 = ffi.cast(ipv4_header_ptr_t, p.data + ether_header_size)
      if ipsum(ffi.cast("uint8_t *", ipv4), ipv4_header_size, 0) == 0 then
         local proto = ipv4.protocol
         p = packet.shiftleft(p, combined_header_size)
         link.transmit(links_out[proto], p)
      else
         counter.add(self.shm["bad-checksum"])
         packet.free(p)
      end
   end

   for _ = 1, link.nreadable(discard) do
      packet.free(link.receive(discard))
   end

   if self._nprotos >= 3 then
      for i = 1, self._nprotos do
         prepend(self, i, sout)
      end
   else
      if self._nprotos >= 1 then
         prepend(self, 1, sout)
      end
      if self._nprotos >= 2 then
         prepend(self, 2, sout)
      end
   end
end

function selftest ()
   local app_graph = config.new()
   local Source = require("apps.basic.basic_apps").Source
   local Sink = require("apps.basic.basic_apps").Sink
   local Join = require("apps.basic.basic_apps").Join

   local SourceProto = {}
   function SourceProto:new (proto)
      local dgram = require("lib.protocol.datagram"):new()
      local ether = require("lib.protocol.ethernet"):new({ type = 0x0800 })
      local ipv4 = ipv4:new({ protocol = proto })
      dgram:push(ipv4)
      dgram:push(ether)
      return setmetatable({ dgram = dgram }, { __index = SourceProto })
   end
   function SourceProto:pull ()
      for _ = 1, engine.pull_npackets do
         link.transmit(self.output.output, packet.clone(self.dgram:packet()))
      end
   end

   local mux_links = {}
   local p_lo, p_hi = 10, 15
   for i = p_lo, p_hi do
      local name = "proto_"..i
      config.app(app_graph, name, SourceProto, i)
      config.link(app_graph, name..".output -> join."..name)
      if i%2 == 0 then
         mux_links[name] = { proto = i }
         config.app(app_graph, name.."_sink", Sink)
         config.link(app_graph, "mux."..name.." -> "..name.."_sink.input")
         config.app(app_graph, name.."_source", Source)
         config.link(app_graph, name.."_source.output -> mux."..name)
      end
   end
   config.app(app_graph, "join", Join)
   config.app(app_graph, "mux", transport, { src = ipv4:pton("127.0.0.1"),
                                             dst = ipv4:pton("127.0.0.2"),
                                             links = mux_links })
   config.link(app_graph, "join.output -> mux.south")
   config.app(app_graph, "sink", Sink)
   config.link(app_graph, "mux.south -> sink.input")

   engine.configure(app_graph)
   engine.main({ duration = 1 })

   local counter = require("core.counter")
   local function packets (app, link, dir)
      local at = engine.app_table[app]
      return tonumber(counter.read(at[dir][link].stats.rxpackets))
   end

   for i = p_lo, p_hi do
      local name = "proto_"..i
      if i%2 == 0 then
         assert(packets(name, "output", "output") ==
                   packets("mux", name, "output"))
      end
   end
end
