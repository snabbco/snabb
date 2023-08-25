-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Fibers.

module(..., package.seeall)

local C = require('ffi').C -- for usleep
local timer = require('lib.fibers.timer')

local Scheduler = {}
function new()
   ret = setmetatable(
      { next={}, cur={}, sources={}, wheel=timer.new_timer_wheel() },
      {__index=Scheduler})
   local timer_task_source = { wheel=ret.wheel }
   function timer_task_source:schedule_tasks(sched, now)
      self.wheel:advance(now, sched)
   end
   function timer_task_source:cancel_all_tasks(sched)
      -- Implement me!
   end
   ret:add_task_source(timer_task_source)
   return ret
end

function Scheduler:add_task_source(source)
   table.insert(self.sources, source)
   if source.wait_for_events then self.event_waiter = source end
end

function Scheduler:schedule(task)
   table.insert(self.next, task)
end

function Scheduler:now()
   return self.wheel.now
end

function Scheduler:schedule_at_time(t, task)
   self.wheel:add_absolute(t, task)
end

function Scheduler:schedule_after_sleep(dt, task)
   self.wheel:add_delta(dt, task)
end

function Scheduler:schedule_tasks_from_sources(now)
   for i=1,#self.sources do
      self.sources[i]:schedule_tasks(self, now)
   end
end

function Scheduler:run(now)
   if now == nil then now = self:now() end
   self:schedule_tasks_from_sources(now)
   self.cur, self.next = self.next, self.cur
   for i=1,#self.cur do
      local task = self.cur[i]
      self.cur[i] = nil
      task:run()
   end
end

function Scheduler:next_wake_time()
   if #self.next > 0 then return self:now() end
   return self.wheel:next_entry_time()
end

function Scheduler:wait_for_events()
   local now, next_time = C.get_monotonic_time(), self:next_wake_time()
   -- Limit the sleep to 10 seconds to ensure that our timeout can be
   -- represented as a u32 in microseconds, and also for strace
   -- debugging.
   local timeout = math.min(10, next_time - now)
   if self.event_waiter then
      self.event_waiter:wait_for_events(self, now, timeout)
   else
      C.usleep(timeout * 1e6)
   end
end

function Scheduler:stop()
   self.done = true
end

function Scheduler:main()
   self.done = false
   repeat
      self:wait_for_events()
      self:run(C.get_monotonic_time())
   until self.done
end

function Scheduler:shutdown()
   for i=1,100 do
      for i=1,#self.sources do self.sources[i]:cancel_all_tasks(self, 'shutdown') end
      if #self.next == 0 then return true end
      self:run()
   end
   return false
end

function selftest ()
   print("selftest: lib.fibers.scheduler")
   local sched = new()

   local last, count = 0, 0
   local function task_run(task)
      local now = sched:now()
      local t = task.scheduled
      last, count = t, count + 1
      -- Check that tasks run within a tenth a tick of when they should.
      -- Floating-point imprecisions can cause either slightly early or
      -- slightly late ticks.
      assert(sched:now() - sched.wheel.period*1.1 < t)
      assert(t < sched:now() + sched.wheel.period*0.1)
   end

   local event_count = 1e5
   local t = sched:now()
   for i=1,event_count do
      local dt = math.random()
      t = t + dt
      sched:schedule_at_time(t, {run=task_run, scheduled=t})
   end
   
   for now=sched:now(),t+1,sched.wheel.period do
      sched:run(now)
   end

   assert(count == event_count)

   print("selftest: ok")
end
