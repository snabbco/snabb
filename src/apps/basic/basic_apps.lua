module(...,package.seeall)

local app = require("core.app")
local freelist = require("core.freelist")
local packet = require("core.packet")
local link = require("core.link")
local transmit, receive = link.transmit, link.receive


local ffi = require("ffi")
local C = ffi.C

--- # `Source` app: generate synthetic packets

Source = {}

function Source:new(size)
   size = tonumber(size) or 60
   local data = ffi.new("char[?]", size)
   local p = packet.from_pointer(data, size)
   return setmetatable({size=size, packet=p}, {__index=Source})
end

function Source:pull ()
   local pkt = self.packet
   for _, outport in ipairs(self.output) do
      while not outport:full() do
         outport:transmit(pkt:clone())
      end
   end
end

function Source:stop ()
   self.packet:free()
end

--- # `Join` app: Merge multiple inputs onto one output

Join = {}

function Join:new()
   return setmetatable({}, {__index=Join})
end

function Join:push ()
   local outport = self.output.out
   for _, inport in ipairs(self.input) do
      while not inport:empty() and not outport:full() do
         outport:transmit(inport:receive())
      end
   end
end

--- ### `Split` app: Split multiple inputs across multiple outputs

-- For each input port, push packets onto outputs. When one output
-- becomes full then continue with the next.
Split = {}

function Split:new ()
   return setmetatable({}, {__index=Split})
end

function Split:push ()
   for _, inport in ipairs(self.input) do
      for _, outport in ipairs(self.output) do
         while not inport:empty() and not outport:full() do
            outport:transmit(inport:receive())
         end
      end
   end
end

--- ### `Sink` app: Receive and discard packets

Sink = {}

function Sink:new ()
   return setmetatable({}, {__index=Sink})
end

function Sink:push ()
   for _, inport in ipairs(self.input) do
      while not inport:empty() do
         inport:receive():free()
      end
   end
end

--- ### `Tee` app: Send inputs to all outputs

Tee = {}

function Tee:new ()
   return setmetatable({}, {__index=Tee})
end

function Tee:push ()
   for _, inport in ipairs(self.input) do
      while not inport:empty() do
         local pkt = inport:receive()
         local used = false
         for _, outport in ipairs(self.outport) do
            if not outport:full() then
               outport:transmit(used and pkt:clone() or pkt)
               used = true
            end
         end
      end
   end
end

--- ### `Repeater` app: Send all received packets in a loop

Repeater = {}

function Repeater:new ()
   return setmetatable({index = 1, packets = {}},
                       {__index=Repeater})
end

function Repeater:push ()
   local inport, outport = self.input.input, self.output.output
   local packets = self.packets
   while not inport:empty() do
      table.insert(packets, inport:receive())
   end
   local npackets = #packets
   if npackets > 0 then
      local index = self.index
      while not outport:full() do
         assert(packets[index])
         outport:transmit(packets[index]:clone())
         index = (index % npackets) + 1
      end
      self.index = index
   end
end

function Repeater:stop ()
   for _, pkt in ipairs(self.packets) do
      pkt:free()
   end
end

