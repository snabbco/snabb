module(...,package.seeall)

local app = require("core.app")
local packet = require("core.packet")
local link = require("core.link")
local transmit, receive = link.transmit, link.receive
local clone = packet.clone

--- ### `RateLimitedRepeater` app: A repeater that can limit flow rate


RateLimitedRepeater = {
   config = {
      -- rate: by default, limit to 10 Mbps, just to have a default.
      rate = {default=10e6},
      -- bucket_capacity: by default, allow for 255 standard packets in the
      -- queue.
      bucket_capacity = {default=255*1500*8},
      initial_capacity = {}
   }
}

function RateLimitedRepeater:new (conf)
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

function RateLimitedRepeater:set_rate (bit_rate)
   self.rate = math.max(bit_rate, 0)
end

function RateLimitedRepeater:pull ()
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

   -- 7 bytes preamble, 1 start-of-frame, 4 CRC, 12 interpacket gap.
   local overhead = 7 + 1 + 4 + 12

   local npackets = #self.packets
   if npackets > 0 and self.rate > 0 then
      for _ = 1, engine.pull_npackets do
         local p = self.packets[self.index]
         local bits = (p.length + overhead) * 8
         if bits > self.bucket_content then break end
         self.bucket_content = self.bucket_content - bits
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
