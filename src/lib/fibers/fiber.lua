-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Fibers.

module(..., package.seeall)

local sched = require('lib.fibers.sched')

local current_fiber = false
current_scheduler = sched.new()

local Fiber = {}
Fiber.__index = Fiber

function spawn(fn)
   current_scheduler:schedule(
      setmetatable({coroutine=coroutine.create(fn),
                    alive=true, sockets={}}, Fiber))
end

function Fiber:resume(...)
   assert(self.alive, "dead fiber")
   local saved_current_fiber = current_fiber
   current_fiber = self
   local ok, err = coroutine.resume(self.coroutine, ...)
   current_fiber = saved_current_fiber
   if not ok then
      print('Error while running fiber: '..tostring(err))
      self.alive = false
   end
end
Fiber.run = Fiber.resume

function Fiber:suspend(block_fn, ...)
   assert(current_fiber == self)
   -- The block_fn should arrange to reschedule the fiber when it
   -- becomes runnable.
   block_fn(current_scheduler, current_fiber, ...)
   return coroutine.yield()
end

function Fiber:get_socket(sd)
   return assert(self.sockets[sd])
end

function Fiber:add_socket(sock)
   local sd = #self.sockets
   -- FIXME: add refcount on socket
   self.sockets[sd] = sock
   return sd
end

function Fiber:close_socket(sd)
   local s = self:get_socket(sd)
   self.sockets[sd] = nil
   -- FIXME: remove refcount on socket
end

function Fiber:wait_for_readable(sd)
   local s = self:get_socket(sd)
   current_scheduler:resume_when_readable(s, self)
   return coroutine.yield()
end

function Fiber:wait_for_writable(sd)
   local s = self:get_socket(sd)
   current_scheduler:schedule_when_writable(s, self)
   return coroutine.yield()
end

function Fiber:sleep(dt)
   current_scheduler:schedule_after_sleep(dt, self)
   return coroutine.yield()
end

function Fiber:sleep_until(t)
   current_scheduler:schedule_at_time(t, self)
   return coroutine.yield()
end

function now(d) return current_scheduler:now() end
function suspend(block_fn, ...) return current_fiber:suspend(block_fn, ...) end
function sleep(dt) return current_fiber:sleep(dt) end
function sleep_until(t) return current_fiber:sleep_until(t) end

function selftest()
   print('selftest: lib.fibers.fiber')
   local done = {}
   local count = 1e3
   for i=1,count do
      local function fn()
         local start, dt = now(), math.random()
         sleep(dt)
         assert(now() >= start + dt)
         table.insert(done, i)
      end
      spawn(fn)
   end
   for t=now(),now()+1.5,0.01 do
      current_scheduler:run(t)
   end
   assert(#done == count)
   print('selftest: ok')
end
