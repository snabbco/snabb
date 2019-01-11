module(..., package.seeall)
local ffi = require("ffi")
local lib = require("core.lib")
local packet = require("core.packet")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local datagram = require("lib.protocol.datagram")

transport = {}

local params = {
   src = { required = true },
   dst = { required = true },
   links = { default = {} },
}
local proto_params = {
   proto = { required = true },
}

local ether_header_size = ethernet:sizeof()
local ipv6_header_size = ipv6:sizeof()
local ipv6_header_ptr_t = ipv6._header.ptr_t
local combined_header_size = ether_header_size + ipv6_header_size

function transport:new (arg)
   local conf = lib.parse(arg, params)
   local o = {}
   o._discard_link = link.new("ipv6_proto_discard")
   o._proto_links_out = ffi.new("struct link *[256]", o._discard_link)

   o._proto_infos = {}
   o._proto_infos_by_name = {}
   for name, arg in pairs(conf.links) do
      local proto = lib.parse(arg, proto_params).proto
      assert(proto > 0 and proto < 255, "Illegal protocol: "..proto)

      -- Construct a combined Ethernet/IPv6 header which will be
      -- prepended to downstream packets.
      local dgram = datagram:new()
      dgram:push(ipv6:new({ src = conf.src,
                            dst = conf.dst,
                            next_header = proto }))
      dgram:push(ethernet:new({ type = 0x86dd }))
      dgram:new(dgram:packet(), ethernet) -- Reset parse stack

      -- Provide access to the IPv6 header to set the payload_length
      -- field in the push() loop.
      local header = dgram:parse_n(2)

      local proto_info = { proto = proto,
                           header = header,
                           combined_header = {
                              data = ffi.cast("uint8_t *", dgram:packet().data),
                              length = dgram:packet().length } }
      table.insert(o._proto_infos, proto_info)
      o._proto_infos_by_name[name] = proto_info
   end

   return setmetatable(o, { __index = transport })
end

function transport:link (mode, dir, name, l)
   if mode == 'unlink' or name == "south" then return end
   if dir == 'output' then
      local proto_info = assert(self._proto_infos_by_name[name],
                                "Unconfigured link: "..name)
      self._proto_links_out[proto_info.proto] = l
   else
      return self.prepend, self._proto_infos_by_name[name]
   end
end

function transport:prepend (lin, proto_info)
   local sout = self.output.south

   for _ = 1, link.nreadable(lin) do
      local p = link.receive(lin)
      proto_info.header:payload_length(p.length)
      local header = proto_info.combined_header
      p = packet.prepend(p, header.data, header.length)
      link.transmit(sout, p)
   end
end

function transport:push (sin)
   local links_out = self._proto_links_out

   for _ = 1, link.nreadable(sin) do
      local p = link.receive(sin)
      -- Precondition: incoming packets must have at least an Ethernet
      -- and an IPv6 header
      assert(p.length >= combined_header_size)
      local ipv6 = ffi.cast(ipv6_header_ptr_t, p.data + ether_header_size)
      local proto = ipv6.next_header
      p = packet.shiftleft(p, combined_header_size)
      link.transmit(links_out[proto], p)
   end

   local discard = self._discard_link
   for _ = 1, link.nreadable(discard) do
      packet.free(link.receive(discard))
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
      local ether = require("lib.protocol.ethernet"):new({ type = 0x86dd })
      local ipv6 = ipv6:new({ next_header = proto })
      dgram:push(ipv6)
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
   config.app(app_graph, "mux", transport, { src = ipv6:pton("::1"),
                                             dst = ipv6:pton("::2"),
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
