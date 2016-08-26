module(...,package.seeall)

local app = require("core.app")
local packet = require("core.packet")
local link = require("core.link")
local transmit, receive = link.transmit, link.receive
local clone = packet.clone

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

function RateLimitedRepeater:set_rate (byte_rate)
   self.rate = math.max(byte_rate, 0)
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

   local npackets = #self.packets
   if npackets > 0 and self.rate > 0 then
      for _ = 1, engine.pull_npackets do
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
