module(..., package.seeall)
local ffi = require("ffi")
local lib = require("core.lib")
local ethernet = require("lib.protocol.ethernet")

af_mux = {}

function af_mux:alloc_l2 ()
   local l2 = ffi.new("struct link *[256]", self.discard)
   table.insert(self.l2_anchors, l2)
   return l2
end

local function split (type)
   local hi = bit.rshift(type, 8)
   local lo = bit.band(type, 0x00FF)
   return hi, lo
end

function af_mux:add (type, link)
   local hi, lo = split(type)
   local l2 = self.l1[hi]
   if l2 == self.default then
      l2 = self:alloc_l2()
      self.l1[hi] = l2
   end
   l2[lo] = link
end

function af_mux:new ()
   local o = setmetatable({}, { __index = af_mux })
   o.discard = link.new("af_mux_discard")
   o.l2_anchors = {}
   o.default = o:alloc_l2()
   o.l1 = ffi.new("struct link **[256]", o.default)
   o.ether = ethernet:new({})
   return o
end

function af_mux:link (mode, dir, name, l)
   if mode == 'unlink' or name == "south" then return end
   if dir == 'output' then
      if name == "ipv4" then
         self:add(0x0800, l) -- IPv4
         self:add(0x0806, l) -- ARP
      elseif name == "ipv6" then
         self:add(0x86dd, l)
      else
         error("Invalid address family "..name)
      end
   else
      return self.push_to_south
   end
end

function af_mux:push_to_south (lin)
   local sout = self.output.south
   for _ = 1, link.nreadable(lin) do
      link.transmit(sout, link.receive(lin))
   end
end

function af_mux:push (sin)
   for _ = 1, link.nreadable(sin) do
      local p = link.receive(sin)
      local ether = ffi.cast(self.ether._header.ptr_t, p.data)
      local hi, lo = split(lib.ntohs(ether.ether_type))
      link.transmit(self.l1[hi][lo], p)
   end

   local discard = self.discard
   for _ = 1, link.nreadable(discard) do
      packet.free(link.receive(discard))
   end
end

function selftest ()
   local app_graph = config.new()
   local sink = require("apps.basic.basic_apps").Sink
   local join = require("apps.basic.basic_apps").Join

   local Source = {}
   function Source:new (ether_type)
      local dgram = require("lib.protocol.datagram"):new()
      local type = ether_type or math.random(0x0800)
      local ether = require("lib.protocol.ethernet"):new({ type = type })
      dgram:push(ether)
      return setmetatable({ dgram = dgram }, { __index = Source })
   end
   function Source:pull ()
      for _ = 1, engine.pull_npackets do
         link.transmit(self.output.output, packet.clone(self.dgram:packet()))
      end
   end

   config.app(app_graph, "mux", af_mux)
   config.app(app_graph, "in_4", Source, 0x0800)
   config.app(app_graph, "in_arp", Source, 0x0806)
   config.app(app_graph, "in_6", Source, 0x86dd)
   config.app(app_graph, "in_random", Source)
   config.app(app_graph, "sink_4", sink)
   config.app(app_graph, "sink_6", sink)
   config.app(app_graph, "join", join)
   config.app(app_graph, "null_4", sink)
   config.app(app_graph, "null_6", sink)

   config.link(app_graph, "in_4.output -> join.in_4")
   config.link(app_graph, "in_arp.output -> join.in_arp")
   config.link(app_graph, "in_6.output -> join.in_6")
   config.link(app_graph, "in_random.output -> join.in_random")
   config.link(app_graph, "join.output -> mux.south")
   config.link(app_graph, "mux.ipv4 -> sink_4.input")
   config.link(app_graph, "mux.ipv6 -> sink_6.input")
   config.link(app_graph, "null_4.output -> mux.ipv4")
   config.link(app_graph, "null_6.output -> mux.ipv6")

   engine.configure(app_graph)
   engine.main({ duration = 1 })

   local counter = require("core.counter")
   local function packets (app, link, dir)
      local at = engine.app_table[app]
      return tonumber(counter.read(at[dir][link].stats.rxpackets))
   end

   assert(packets("in_4", "output", "output") +
             packets("in_arp", "output", "output")
             == packets("mux", "ipv4", "output"))
   assert(packets("in_6", "output", "output")
             == packets("mux", "ipv6", "output"))
end
