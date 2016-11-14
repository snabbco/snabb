module(...,package.seeall)

-- Ingress packet drop monitor timer.

local S = require("syscall")
local counter = require("core.counter")
local ffi = require("ffi")
local shm = require("core.shm")

-- Every 100 milliseconds.
local default_interval = 1e8

local default_tips_url =
   "https://github.com/snabbco/snabb/blob/master/src/doc/performance-tuning.md"

local now = core.app.now

local IngressDropMonitor = {}

function new(args)
   local ret = {
      threshold = args.threshold or 100000,
      wait = args.wait or 20,
      action = args.action or 'flush',
      tips_url = args.tips_url or default_tips_url,
      last_flush = 0,
      last_value = ffi.new('uint64_t[1]'),
      current_value = ffi.new('uint64_t[1]')
   }
   if args.counter then
      if not args.counter:match(".counter$") then
         args.counter = args.counter..".counter"
      end
      if not shm.exists(args.counter) then
         ret.counter = counter.create(args.counter, 0)
      else
         ret.counter = counter.open(args.counter)
      end
   end
   return setmetatable(ret, {__index=IngressDropMonitor})
end

function IngressDropMonitor:sample ()
   local app_array = engine.breathe_push_order
   local sum = self.current_value
   sum[0] = 0
   for i = 1, #app_array do
      local app = app_array[i]
      if app.ingress_packet_drops and not app.dead then
         sum[0] = sum[0] + app:ingress_packet_drops()
      end
   end
   if self.counter then
      counter.set(self.counter, sum[0])
   end
end

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
   msg = msg..". See "..self.tips_url.." for performance tuning tips."
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
