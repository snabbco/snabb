module(...,package.seeall)

local app = require("core.app")
local freelist = require("core.freelist")
local packet = require("core.packet")
local link = require("core.link")
local transmit, receive = link.transmit, link.receive
local clone = packet.clone


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
   for _, o in ipairs(self.output) do
      for i = 1, link.nwritable(o) do
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
      for n = 1,math.min(link.nreadable(inport), link.nwritable(self.output.out)) do
         transmit(self.output.out, receive(inport))
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
         for _ = 1, math.min(link.nreadable(i), link.nwritable(o)) do
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
   noutputs = #self.output
   if noutputs > 0 then
      local maxoutput = link.max
      for _, o in ipairs(self.output) do
         maxoutput = math.min(maxoutput, link.nwritable(o))
      end
      for _, i in ipairs(self.input) do
         for _ = 1, math.min(link.nreadable(i), maxoutput) do
            local p = receive(i)
            maxoutput = maxoutput - 1
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
      for i = 1, link.nwritable(o) do
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

--- ### `Statistics` app: Periodically print statistics

Statistics = {}

function Statistics:new ()
   return setmetatable({packets=0, bytes=0},
                       {__index=Statistics})
end

function Statistics:push ()
   local i, o = self.input.input, self.output.output
   local packets = self.packets
   local bytes = self.bytes
   for _ = 1, math.min(link.nreadable(i), link.nwritable(o)) do
      local p = receive(i)
      bytes = bytes + p.length
      packets = packets + 1
      transmit(o, p)
   end
   local cur_now = tonumber(app.now())
   self.period_start = self.period_start or cur_now
   local elapsed = cur_now - self.period_start
   if elapsed > 1 then
      print(string.format('%s: %.3f MPPS, %.3f Gbps.',
			  self.appname,
			  packets / elapsed / 1e6,
			  bytes * 8 / 1e9 / elapsed))
      self.period_start = cur_now
      self.bytes = 0
      self.packets = 0
   else
      self.bytes = bytes
      self.packets = packets
   end
end

--- ### `RateLimitedRepeater` app: A repeater that can limit flow rate

RateLimitedRepeater = {}

function RateLimitedRepeater:new (arg)
   local conf = arg and config.parse_app_arg(arg) or {}
   --- By default, limit to 10 Mbps, just to have a default.
   conf.rate = conf.rate or (10e6 / 8)
   -- By default, allow for 255 standard packets in the queue.
   conf.bucket_capacity = conf.bucket_capacity or (255 * 1500)
   conf.initial_capacity = conf.initial_capacity or conf.bucket_capacity
   local o = {
      index = 1,
      packets = {},
      rate = conf.rate,
      bucket_capacity = conf.bucket_capacity,
      bucket_content = conf.initial_capacity
    }
   return setmetatable(o, {__index=RateLimitedRepeater})
end

function RateLimitedRepeater:push ()
   local i, o = self.input.input, self.output.output
   for _ = 1, link.nreadable(i) do
      local p = receive(i)
      table.insert(self.packets, p)
   end

   do
      local cur_now = tonumber(app.now())
      local last_time = self.last_time or cur_now
      self.bucket_content = math.min(
            self.bucket_content + self.rate * (cur_now - last_time),
            self.bucket_capacity
         )
      self.last_time = cur_now
   end

   local npackets = #self.packets
   if npackets > 0 then
      for _ = 1, link.nwritable(o) do
         local p = self.packets[self.index]
         if p.length > self.bucket_content then break end
         self.bucket_content = self.bucket_content - p.length
         transmit(o, clone(p))
         self.index = (self.index % npackets) + 1
      end
   end
end

function RateLimitedRepeater:stop ()
   for i = 1, #self.packets do
      packet.free(self.packets[i])
   end
end
