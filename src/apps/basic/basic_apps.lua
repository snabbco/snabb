module(...,package.seeall)

local lib = require("core.lib")
local app = require("core.app")
local buffer = require("core.buffer")
local packet = require("core.packet")
local link = require("core.link")

local ffi = require("ffi")
local C = ffi.C

Basic = {}

function Basic:relink ()
   self.inputi, self.outputi = {}, {}
   for _,l in pairs(self.output) do
      table.insert(self.outputi, l)
   end
   for _,l in pairs(self.input) do
      table.insert(self.inputi, l)
   end
end

--- # `Source` app: generate synthetic packets

Source = setmetatable({zone = "Source"}, {__index = Basic})

function Source:new()
   return setmetatable({}, {__index=Source})
end

function Source:pull ()
   for _, o in ipairs(self.outputi) do
      for i = 1, link.nwritable(o) do
         local p = packet.allocate()
         packet.add_iovec(p, buffer.allocate(), 60)
         link.transmit(o, p)
      end
   end
end

--- # `Join` app: Merge multiple inputs onto one output

Join = setmetatable({zone = "Join"}, {__index = Basic})

function Join:new()
   return setmetatable({}, {__index=Join})
end

function Join:push () 
   for _, inport in ipairs(self.inputi) do
      for n = 1,math.min(link.nreadable(inport), link.nwritable(self.output.out)) do
         link.transmit(self.output.out, link.receive(inport))
      end
   end
end

--- ### `Split` app: Split multiple inputs across multiple outputs

-- For each input port, push packets onto outputs. When one output
-- becomes full then continue with the next.
Split = setmetatable({zone = "Split"}, {__index = Basic})

function Split:new ()
   return setmetatable({}, {__index=Split})
end

function Split:push ()
   for _, i in ipairs(self.inputi) do
      for _, o in ipairs(self.outputi) do
         for _ = 1, math.min(link.nreadable(i), link.nwritable(o)) do
            link.transmit(o, link.receive(i))
         end
      end
   end
end

--- ### `Sink` app: Receive and discard packets

Sink = setmetatable({zone = "Sink"}, {__index = Basic})

function Sink:new ()
   return setmetatable({}, {__index=Sink})
end

function Sink:push ()
   for _, i in ipairs(self.inputi) do
      for _ = 1, link.nreadable(i) do
        local p = link.receive(i)
        packet.deref(p)
      end
   end
end

--- ### `FastSink` app: Receive and discard packets

-- It is hacked Sink with very low packet processing overhead
-- Only for test purpose, never use it in real world application
-- Assumed to be used in pair with FastRepeater
-- FastSink doesn't calculate rx statistics

FastSink = setmetatable({zone = "FastSink"}, {__index = Basic})

function FastSink:new ()
   return setmetatable({}, {__index=Sink})
end

function FastSink:push ()
   local i = self.input.input
   -- make link empty
   i.read = 0
   i.write = 0
end

--- ### `Tee` app: Send inputs to all outputs

Tee = setmetatable({zone = "Tee"}, {__index = Basic})

function Tee:new ()
   return setmetatable({}, {__index=Tee})
end

function Tee:push ()
   noutputs = #self.outputi
   if noutputs > 0 then
      local maxoutput = link.max
      for _, o in ipairs(self.outputi) do
         maxoutput = math.min(maxoutput, link.nwritable(o))
      end
      for _, i in ipairs(self.inputi) do
         for _ = 1, math.min(link.nreadable(i), maxoutput) do
            local p = link.receive(i)
            packet.ref(p, noutputs - 1)
            maxoutput = maxoutput - 1
            for _, o in ipairs(self.outputi) do
               link.transmit(o, p)
            end
         end
      end
   end
end

--- ### `Repeater` app: Send all received packets in a loop

Repeater = setmetatable({zone = "Repeater"}, {__index = Basic})

function Repeater:new ()
   return setmetatable({index = 1, packets = {}},
                       {__index=Repeater})
end

function Repeater:push ()
   local i, o = self.input.input, self.output.output
   for _ = 1, link.nreadable(i) do
      local p = link.receive(i)
      packet.tenure(p)
      table.insert(self.packets, p)
   end
   local npackets = #self.packets
   if npackets > 0 then
      for i = 1, link.nwritable(o) do
         assert(self.packets[self.index])
         link.transmit(o, self.packets[self.index])
         self.index = (self.index % npackets) + 1
      end
   end
end

--- ### `FastRepeater` app: Send all received packets in a loop

-- It is hacked Repeater with very low packet processing overhead
-- Only for test purpose, never use it in real world application
-- Assumed to be used in pair with FastSink

FastRepeater = setmetatable({zone = "FastRepeater"}, {__index = Basic})

function FastRepeater:new ()
   return setmetatable({init = true},
                       {__index=FastRepeater})
end

do
   local ring_size = C.LINK_RING_SIZE
   local max_packets = C.LINK_MAX_PACKETS

   function FastRepeater:push ()
      local o = self.output.output
      -- on first call read all packets
      if self.init then
         local i = self.input.input
         local npackets = link.nreadable(i)
         for index = 1, npackets do
            local p = link.receive(i)
            packet.tenure(p)
            o.packets[index - 1] = p
         end
         --  and fullfil output link buffer
         for index = npackets, max_packets do
            o.packets[index] = o.packets[index % npackets]
         end
         o.stats.txpackets = ring_size
         self.init = false
         return
      end
      -- reset output link, make it full again
      o.write = (o.write + link.nwritable(o)) % ring_size
      -- assert(link.full(o)) -- hint how to debug
      o.stats.txpackets = o.stats.txpackets + ring_size
      -- intentionally don't calculate txbytes
   end
end

--- ### `Buzz` app: Print a debug message when called

Buzz = setmetatable({zone = "Buzz"}, {__index = Basic})

function Buzz:new ()
   return setmetatable({}, {__index=Buzz})
end

function Buzz:pull () print "bzzz pull" end
function Buzz:push () print "bzzz push" end


--- ### Classifier app:
--- records history of packets
Classifier = setmetatable({}, {__index = Basic})
function Classifier:new()
   return setmetatable(
      {_patterns={}, _rev={}, _counters={}, _seq={}}, 
      {__index=Classifier})
end

function Classifier:setPatterns(pats)
   self._patterns = pats
   self._seq = {}
   self._rev = {}
   self._counters = {}
   for k,v in pairs(pats) do
      self._rev[v] = k
      self._counters[k] = 0
   end
end

function Classifier:count(ln, d)
   local packet_name = self._rev[d]
   if packet_name == nil then
     packet_name = #self._patterns+1
     self._patterns[packet_name] = d
     self._rev[d] = packet_name
   end
   self._seq[#self._seq+1] = ln..':'..packet_name
   self._counters[packet_name] = (self._counters[packet_name] or 0) + 1
end

function Classifier:repConters()
   return table.concat(self._counters, ',')
end

function Classifier:repSequence()
   return table.concat(self._seq, ',')
end

function Classifier:push ()
   for ln, l in pairs(self.input) do
      for _ = 1, link.nreadable(l) do
        local p = link.receive(l)
        self:count(ln, packet.tostring(p))
        packet.deref(p)
      end
   end
end

