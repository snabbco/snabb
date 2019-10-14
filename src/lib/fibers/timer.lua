-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Hierarchical timer wheel inspired by Juho Snellman's "Ratas".  For a
-- detailed discussion, see:
--
--   https://www.snellman.net/blog/archive/2016-07-27-ratas-hierarchical-timer-wheel/

module(...,package.seeall)

local lib = require("core.lib")
local bit = require("bit")
local band = bit.band

local TimerWheel = {}

local WHEEL_SLOTS = 256
local SLOT_INDEX_MASK = 255

local function push_node(node, head)
   node.prev, node.next, head.prev.next, head.prev = head.prev, head, node, node
end

local function pop_node(head)
   local node = head.next
   head.next, node.next.prev = node.next, head
   return node
end

local function allocate_timer_entry()
   return { time=false, prev=false, next=false, obj=false }
end

local timer_entry_freelist = {}

local function new_timer_entry()
   local pos = #timer_entry_freelist
   if pos ~= 0 then
      local ent = timer_entry_freelist[pos]
      timer_entry_freelist[pos] = nil
      return ent
   end
   return allocate_timer_entry()
end

local function make_timer_entry(t, obj)
   local ent = new_timer_entry()
   ent.time, ent.obj = t, obj
   return ent
end

local function recycle_timer_entry(ent)
   ent.time, ent.next, ent.prev, ent.obj = false, false, false, false
   timer_entry_freelist[#timer_entry_freelist+1] = ent
end

local function new_slots()
   local ret = {}
   for slot=0,WHEEL_SLOTS-1 do
      local head = make_timer_entry(false, false)
      head.prev, head.next = head, head
      ret[slot] = head
   end
   return ret
end

function new_timer_wheel(now, period)
   now, period = now or engine.now(), period or 1e-3
   return setmetatable(
      { now=now, period=period, rate=1/period, cur=0,
        slots=new_slots(), outer=false },
      {__index=TimerWheel})
end

local function add_wheel(inner)
   local base = inner.now + inner.period * (WHEEL_SLOTS - inner.cur)
   inner.outer = new_timer_wheel(base, inner.period * WHEEL_SLOTS)
end

function TimerWheel:add_delta(dt, obj)
   return self:add_absolute(self.now + dt, obj)
end

function TimerWheel:add_absolute(t, obj)
   local offset = math.max(math.floor((t - self.now) * self.rate), 0)
   if offset < WHEEL_SLOTS then
      local idx = band(self.cur + offset, SLOT_INDEX_MASK)
      local ent = make_timer_entry(t, obj)
      push_node(ent, self.slots[idx])
      return ent
   else
      if not self.outer then add_wheel(self) end
      return self.outer:add_absolute(t, obj)
   end
end

local function slot_min_time(head)
   local min = 1/0
   local ent = head.next
   while ent ~= head do
      min = math.min(ent.time, min)
      ent = ent.next
   end
   return min
end

function TimerWheel:next_entry_time()
   for offset=0,WHEEL_SLOTS-1 do
      local idx = band(self.cur + offset, SLOT_INDEX_MASK)
      local head = self.slots[idx]
      if head ~= head.next then
         local t = slot_min_time(head)
         if self.outer then
            -- Unless we just migrated entries from outer to inner wheel
            -- on the last tick, outer wheel overlaps with inner.
            local outer_idx = band(self.outer.cur + offset, SLOT_INDEX_MASK)
            t = math.min(t, slot_min_time(self.outer.slots[outer_idx]))
         end
         return t
      end
   end
   if self.outer then return self.outer:next_entry_time() end
   return 1/0
end

local function tick_outer(inner, outer)
   if not outer then return end
   local head = outer.slots[outer.cur]
   while head.next ~= head do
      local ent = pop_node(head)
      local idx = math.floor((ent.time - outer.now) * inner.rate)
      -- Because of floating-point imprecision it's possible to get an
      -- index that falls just outside [0,WHEEL_SLOTS-1].
      idx = math.max(math.min(idx, WHEEL_SLOTS-1), 0)
      push_node(ent, inner.slots[idx])
   end
   outer.cur = band(outer.cur + 1, SLOT_INDEX_MASK)
   -- Adjust inner clock; outer period is more precise than N additions
   -- of the inner period.
   inner.now, outer.now = outer.now, outer.now + outer.period
   if outer.cur == 0 then tick_outer(outer, outer.outer) end
end

local function tick(wheel, sched)
   local head = wheel.slots[wheel.cur]
   while head.next ~= head do
      local ent = pop_node(head)
      local obj = ent.obj
      recycle_timer_entry(ent)
      sched:schedule(obj)
   end
   wheel.cur = band(wheel.cur + 1, SLOT_INDEX_MASK)
   wheel.now = wheel.now + wheel.period
   if wheel.cur == 0 then tick_outer(wheel, wheel.outer) end
end

function TimerWheel:advance(t, sched)
   while t >= self.now + self.period do tick(self, sched) end
end

function selftest ()
   print("selftest: lib.fibers.timer")
   local wheel = new_timer_wheel(10, 1e-3)

   -- At millisecond precision, advancing the wheel by an hour shouldn't
   -- take perceptible time.
   local hour = 60*60
   wheel:advance(hour)

   local event_count = 1e5
   local t = wheel.now
   for i=1,event_count do
      local dt = math.random()
      t = t + dt
      wheel:add_absolute(t, t)
   end
   
   local last = 0
   local count = 0
   local check = {}
   function check:schedule(t)
      local now = wheel.now
      -- The timer wheel only guarantees ordering between ticks, not
      -- ordering within a tick.  It doesn't even guarantee insertion
      -- order within a tick.  However for this test we know that
      -- insertion order is preserved.
      assert(last <= t)
      last, count = t, count + 1
      -- Check that timers fire within a tenth a tick of when they
      -- should.  Floating-point imprecisions can cause either slightly
      -- early or slightly late ticks.
      assert(wheel.now - wheel.period*0.1 < t)
      assert(t < wheel.now + wheel.period*1.1)
   end

   wheel:advance(t+1, check)
   assert(count == event_count)

   print("selftest: ok")
end
