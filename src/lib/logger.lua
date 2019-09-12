-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local lib          = require("core.lib")
local token_bucket = require("lib.token_bucket")
local tsc          = require("lib.tsc")

local logger = {}
local params = {
   rate = { default = 10 },
   discard_report_rate = { default = 0.2 },
   fh = { default = io.stdout },
   flush = { default = true },
   module = { required = false },
   date = { default = true },
   date_fmt = { default = "%b %d %Y %H:%M:%S " },
   throttle = { default = true },
   throttle_config = { default = {} },
}
local throttle_params = {
   excess = { default = 5 },     -- Multiple of rate at which to start throttling
   increment = { default = 4 },  -- Fraction of rate to increase for un-throttling
   min_rate = { default = 0.1 }, -- Minimum throttled rate
}

function new (arg)
   local o = setmetatable(lib.parse(arg, params), { __index = logger })
   o.tb = token_bucket.new({ rate = o.rate })
   o.discard_tb = token_bucket.new({ rate = o.discard_report_rate })
   o.discards = 0
   o.tsc = tsc.new()
   o.stamp = o.tsc:stamp()
   o.preamble = (o.module and o.module..': ') or ''
   if o.throttle then
      o.throttle = lib.parse(o.throttle_config, throttle_params)
   end
   return o
end

function logger:log (msg)
   if self.tb:take(1) then
      local date = (self.date and os.date(self.date_fmt)) or ''
      local preamble = date..self.preamble
      self.fh:write(("%s%s\n"):format(preamble, msg))
      if self.flush then self.fh:flush() end

      if self.discards > 0 and self.discard_tb:take(1) then
         self.fh:write(
            ("%s%d messages discarded\n"):format(preamble, self.discards)
         )
         
         if self.throttle then
            local ticks = self.tsc:stamp() - self.stamp
            local discard_rate =
               self.discards * tonumber(self.tsc:tps())/tonumber(ticks)
            local threshold = self.rate * self.throttle.excess
            local current_rate = self.tb:get()
            
            if discard_rate > threshold then
               local min_rate = self.throttle.min_rate
               if current_rate > min_rate then
                  local new_rate = math.max(min_rate, current_rate/2)
                  self.fh:write(
                     ("%sMessage discard rate %.2f Hz exceeds "
                         .."threshold (%.2f Hz), throttling "
                         .."logging rate to %.2f Hz%s\n")
                        :format(preamble, discard_rate, threshold, new_rate,
                                (new_rate == min_rate and ' (minimum)') or '')
                  )
                  self.tb:set(new_rate)
               end
            else
               if current_rate < self.rate then
                  local new_rate = math.min(self.rate,
                                            current_rate + self.rate/self.throttle.increment)
                  self.fh:write(
                     ("%sUnthrottling logging rate to %.2f Hz%s\n")
                        :format(preamble, new_rate,
                                (new_rate == self.rate and ' (maximum)') or '')
                  )
                  self.tb:set(new_rate)
               end
            end
            
         end
         
         self.discards = 0
         self.stamp = self.tsc:stamp()
      end
   else
      self.discards = self.discards + 1
   end
end

-- Return true if a message can be logged without being discarded,
-- false otherwise.  The latter increases the discard counter,
-- assuming the caller wants to actually log a message.
function logger:can_log ()
   if self.tb:can_take(1) then
      return true
   end
   self.discards = self.discards + 1
   return false
end

