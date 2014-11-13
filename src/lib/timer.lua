module(...,package.seeall)

local engine = require("core.app")

local ticks = false     -- Ticks in milliseconds.
debug = false           -- verbose printouts?

-- Return engine time in milliseconds.
function now ()
   local resolution = 1000
   return math.floor(engine.now() * resolution)
end

-- Timer table object (map tick to timerlist).
TimerTable = {}

function TimerTable:new ()
   return setmetatable({}, {__index = TimerTable})
end

function TimerTable:activate (timer)
   if not ticks then ticks = now() end
   local tick = ticks + timer.ticks
   if self[tick] then table.insert(self[tick], timer)
   else self[tick] = {timer} end
end

-- Run all timers in table that have expired.
function TimerTable:run ()
   run_to_time(self, now())
end

-- Run timers up to the given new time.
function run_to_time (timers, new_ticks)
   local function call_timers (l)
      for i=1,#l do
         local timer = l[i]
         if debug then
            print(string.format("running timer %s at tick %s", timer.name, new_ticks))
         end
         timer.fn(timer)
         if timer.repeating then timers:activate(timer) end
      end
   end
   for tick = ticks, new_ticks do
      ticks = tick
      if timers[ticks] then
         call_timers(timers[ticks])
         timers[ticks] = nil
      end
   end
end

-- Create timer to be inserted into a TimerTable.
function TimerTable:timer (name, fn, ticks, mode)
   return { name = name,
            fn = fn,
            ticks = ticks,
            repeating = (mode == 'repeating') }
end

function selftest ()
   print("selftest: timer")
   engine.main({duration=0.1})
   ticks = now()
   local start = ticks
   local ntimers, runtime = 10000, 100000
   local count, expected_count = 0, 0
   local fn = function (t) count = count + 1 end
   -- Start timers, each counting at a different frequency
   local timers = TimerTable.new()
   for freq = 1, ntimers do
      local t = timers:timer("timer"..freq, fn, freq, 'repeating')
      timers:activate(t)
      expected_count = expected_count + math.floor(runtime / freq)
   end
   -- Run timers for 'runtime' in random sized time steps
   local now_ticks = 0
   while now_ticks < runtime do
      now_ticks = math.min(runtime, now_ticks + math.random(5))
      local old_count = count
      run_to_time(timers, now_ticks + start)
      assert(count > old_count, "count increasing")
   end
   assert(count == expected_count, "final count correct")
   print("ok")
end
