-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local app = require("core.app")
local packet = require("core.packet")
local link = require("core.link")
local ffi = require("ffi")
local transmit, receive = link.transmit, link.receive

--- # `Source` app: generate synthetic packets

Source = {}

function Source:new(size)
   size = tonumber(size) or 60
   local data = ffi.new("char[?]", size)
   local p = packet.from_pointer(data, size)
   return setmetatable({size=size, packet=p}, {__index=Source})
end

function Source:pull ()
   for _, o in ipairs(self.output) do
      for i = 1, engine.pull_npackets do
         transmit(o, packet.clone(self.packet))
      end
   end
end

function Source:stop ()
   packet.free(self.packet)
end

--- # `Join` app: Merge multiple inputs onto one output

Join = {}

function Join:new()
   return setmetatable({}, {__index=Join})
end

function Join:push ()
   for _, inport in ipairs(self.input) do
      while not link.empty(inport) do
         transmit(self.output.output, receive(inport))
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
   for _, i in ipairs(self.input) do
      for _, o in ipairs(self.output) do
         for _ = 1, link.nreadable(i) do
            transmit(o, receive(i))
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
   for _, i in ipairs(self.input) do
      for _ = 1, link.nreadable(i) do
        local p = receive(i)
        packet.free(p)
      end
   end
end

--- ### `Tee` app: Send inputs to all outputs

Tee = {}

function Tee:new ()
   return setmetatable({}, {__index=Tee})
end

function Tee:push ()
   local noutputs = #self.output
   if noutputs > 0 then
      for _, i in ipairs(self.input) do
         for _ = 1, link.nreadable(i) do
            local p = receive(i)
            do local output = self.output
               for k = 1, #output do
                  transmit(output[k], k == #output and p or packet.clone(p))
               end
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
   local i, o = self.input.input, self.output.output
   for _ = 1, link.nreadable(i) do
      local p = receive(i)
      table.insert(self.packets, p)
   end
   local npackets = #self.packets
   if npackets > 0 then
      for i = 1, engine.pull_npackets do
         assert(self.packets[self.index])
         transmit(o, packet.clone(self.packets[self.index]))
         self.index = (self.index % npackets) + 1
      end
   end
end

function Repeater:stop ()
   for i = 1, #self.packets do
      packet.free(self.packets[i])
   end
end

--- # `Truncate` app: truncate or zero pad packet to length n

Truncate = {}

function Truncate:new (n)
   return setmetatable({n = n}, {__index=Truncate})
end

function Truncate:push ()
   for _ = 1, link.nreadable(self.input.input) do
      local p = receive(self.input.input)
      ffi.fill(p.data, math.max(0, self.n - p.length))
      p.length = self.n
      transmit(self.output.output,p)
   end
end

--- # `Sample` app: let through every nth packet

Sample = {}

function Sample:new (n)
   return setmetatable({n = n, seen = 1}, {__index=Sample})
end

function Sample:push ()
   for _ = 1, link.nreadable(self.input.input) do
      local p = receive(self.input.input)
      if self.n == self.seen then
         transmit(self.output.output, p)
         self.seen = 1
      else
         self.seen = self.seen + 1
         packet.free(p)
      end
   end
end
