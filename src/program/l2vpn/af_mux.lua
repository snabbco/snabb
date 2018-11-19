module(..., package.seeall)
local ffi = require("ffi")
local lib = require("core.lib")
local ethernet = require("lib.protocol.ethernet")

af_mux = {}

function af_mux:alloc_l2 ()
   local l2 = ffi.new("struct link *[256]", self.discard_link)
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
   o.discard_link = link.new("af_mux_discard")
   o.l2_anchors = {}
   o.default = o:alloc_l2()
   o.l1 = ffi.new("struct link **[256]", o.default)
   o.ether = ethernet:new({})
   return o
end

function af_mux:link ()
   for name, l in pairs(self.output) do
      if type(name) == "string" and name ~= "south" then
         if name == "ipv4" then
            self:add(0x0800, l) -- IPv4
            self:add(0x0806, l) -- ARP
         elseif name == "ipv6" then
            self:add(0x86dd, l)
         else
            error("Invalid address family "..name)
         end
      end
   end
end

function af_mux:push ()
   local isouth = self.input.south
   for _ = 1, link.nreadable(isouth) do
      local p = link.receive(isouth)
      local ether = ffi.cast(self.ether._header.ptr_t, p.data)
      local hi, lo = split(lib.ntohs(ether.ether_type))
      link.transmit(self.l1[hi][lo], p)
  end

   for _ = 1, link.nreadable(self.discard_link) do
      packet.free(link.receive(self.discard_link))
   end
   
   local iv4, iv6 = self.input.ipv4, self.input.ipv6
   local osouth = self.output.south
   if iv4 then
      for _ = 1, link.nreadable(iv4) do
         link.transmit(osouth, link.receive(iv4))
      end
   end
   if iv6 then
      for _ = 1, link.nreadable(iv6) do
         link.transmit(osouth, link.receive(iv6))
      end
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
