module(...,package.seeall)

local app = require("core.app")
local buffer = require("core.buffer")
local packet = require("core.packet")
local link = require("core.link")

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

Source = setmetatable({}, {__index = Basic})

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

Join = setmetatable({}, {__index = Basic})

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
Split = setmetatable({}, {__index = Basic})

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

Sink = setmetatable({}, {__index = Basic})

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

--- ### `Tee` app: Send inputs to all outputs

Tee = setmetatable({}, {__index = Basic})

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

Repeater = setmetatable({}, {__index = Basic})

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

--- ### `Buzz` app: Print a debug message when called

Buzz = setmetatable({}, {__index = Basic})

function Buzz:new ()
   return setmetatable({}, {__index=Buzz})
end

function Buzz:pull () print "bzzz pull" end
function Buzz:push () print "bzzz push" end


