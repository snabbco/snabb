module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local lib = require("core.lib")

debug = false     -- verbose printouts?

ticks = false     -- current time, in ticks
ns_per_tick = 1e6 -- tick resolution (millisecond)
timers = {}       -- table of {tick->timerlist}

function init ()
   ticks = math.floor(tonumber(C.get_time_ns() / ns_per_tick))
end

-- Run all timers that have expired.
function run ()
   if ticks then run_to_time(C.get_time_ns()) end
end

-- Run all timers up to the given new time.
function run_to_time (ns)
   local new_ticks = math.floor(tonumber(ns) / ns_per_tick)
   for tick = ticks, new_ticks do
      ticks = tick
      if timers[ticks] then
         for _,t in pairs(timers[ticks]) do
            if debug then
               print("running timer " .. t.name .. " at tick " .. ticks)
            end
            t.fn(t)
            if t.repeating then activate(t) end
         end
         timers[ticks] = nil
      end
   end
end

function activate (t)
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
