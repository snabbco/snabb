module(...,package.seeall)

-- Ingress packet drop monitor timer.

local ffi = require("ffi")

-- Every 100 milliseconds.
local default_interval = 1e8

local now = core.app.now

local IngressDropMonitor = {}

function new(args)
   local ret = {
      threshold = args.threshold or 100000,
      wait = args.wait or 20,
      action = args.action or 'flush',
      last_flush = 0,
      last_value = ffi.new('uint64_t[1]'),
      current_value = ffi.new('uint64_t[1]')
   }
   return setmetatable(ret, {__index=IngressDropMonitor})
end

function IngressDropMonitor:sample ()
   local app_array = engine.app_array
   local sum = self.current_value
   sum[0] = 0
   for i = 1, #app_array do
      local app = app_array[i]
      if app.ingress_packet_drops and not app.dead then
         sum[0] = sum[0] + app:ingress_packet_drops()
      end
   end
end

local tips_url = "https://github.com/Igalia/snabb/blob/lwaftr/src/program/lwaftr/doc/README.performance.md"

function IngressDropMonitor:jit_flush_if_needed ()
   if self.current_value[0] - self.last_value[0] < self.threshold then return end
   if now() - self.last_flush < self.wait then return end
   self.last_flush = now()
   self.last_value[0] = self.current_value[0]
   --- TODO: Change last_flush, last_value and current_value fields to be counters.
   local msg = now()..": warning: Dropped more than "..self.threshold.." packets"
   if self.action == 'flush' then
      msg = msg.."; flushing JIT to try to recover"
   end
   msg = msg..". See "..tips_url.." for performance tuning tips."
   print(msg)
   if self.action == 'flush' then jit.flush() end
end

function IngressDropMonitor:timer(interval)
   return timer.new("ingress drop monitor",
                    function ()
                       self:sample()
                       self:jit_flush_if_needed()
                    end,
                    interval or default_interval,
                    "repeating")
end
