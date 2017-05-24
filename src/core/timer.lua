-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local lib = require("core.lib")

-- Enable only when debugging this module. Can be very verbose.
local debug = false

ticks = false     -- current time, in ticks
ns_per_tick = 1e6 -- tick resolution (millisecond)
timers = {}       -- table of {tick->timerlist}

-- This function can be removed in the future.
-- For now it exists to help people understand why their code now
-- breaks if it calls timer.init().
function init ()
   error("timer.init() function is gone (timer module auto-initializes)")
end

-- Run all timers that have expired.
function run ()
   if ticks then run_to_time(tonumber(C.get_time_ns())) end
end

-- Run all timers up to the given new time.
local function call_timers (l)
   for i=1,#l do
      local timer = l[i]
      if debug then
         print(string.format("running timer %s at tick %s", timer.name, ticks))
      end
      timer.fn(timer)
      if timer.repeating then activate(timer) end
   end
end
function run_to_time (ns)
   local new_ticks = math.floor(tonumber(ns) / ns_per_tick)
   for tick = ticks, new_ticks do
      ticks = tick
      if timers[ticks] then
         call_timers(timers[ticks])
         timers[ticks] = nil
      end
   end
end

function activate (t)
   -- Initialize time
   if not ticks then
      ticks = math.floor(tonumber(C.get_time_ns() / ns_per_tick))
   end
   local tick = ticks + t.ticks
   if timers[tick] then
      table.insert(timers[tick], t)
   else
      timers[tick] = {t}
   end
end

function new (name, fn, nanos, mode)
   return { name = name,
            fn = fn,
            ticks = math.ceil(nanos / ns_per_tick),
            repeating = (mode == 'repeating') }
end

function selftest ()
   print("selftest: timer")

   ticks = 0
   local ntimers, runtime = 10000, 100000
   local count, expected_count = 0, 0
   local fn = function (t) count = count + 1 end
   local start = C.get_monotonic_time()
   -- Start timers, each counting at a different frequency
   for freq = 1, ntimers do
      local t = new("timer"..freq, fn, ns_per_tick * freq, 'repeating')
      activate(t)
      expected_count = expected_count + math.floor(runtime / freq)
   end
   -- Run timers for 'runtime' in random sized time steps
   local now_ticks = 0
   while now_ticks < runtime do
      now_ticks = math.min(runtime, now_ticks + math.random(5))
      local old_count = count
      run_to_time(now_ticks * ns_per_tick)
      assert(count > old_count, "count increasing")
   end
   assert(count == expected_count, "final count correct")
   local finish = C.get_monotonic_time()
   local elapsed_time = finish - start
   print(("ok (%s callbacks in %.4f seconds)"):format(
      lib.comma_value(count), elapsed_time))
end

