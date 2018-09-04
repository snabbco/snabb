-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Concurrent ML channels.

module(..., package.seeall)

local op = require('lib.fibers.op')

local Cond = {}

function new()
   return setmetatable({ waitq={} }, {__index=Cond})
end

-- Make an operation that will complete when and if the condition is
-- signalled.
function Cond:wait_operation()
   local function try() return not self.waitq end
   local function gc()
      local i = 1
      while i <= #self.waitq do
         if self.waitq[i].suspension:waiting() then
            i = i + 1
         else
            table.remove(self.waitq, i)
         end
      end
   end
   local function block(suspension, wrap_fn)
      gc()
      table.insert(self.waitq, {suspension=suspension, wrap=wrap_fn})
   end
   return op.new_base_op(nil, try, block)
end

function Cond:wait() return self:wait_operation():perform() end

function Cond:signal()
   if self.waitq ~= nil then
      for _,remote in ipairs(self.waitq) do
         if remote.suspension:waiting() then
            remote.suspension:complete(remote.wrap)
         end
      end
      self.waitq = nil
   end
end

function selftest()
   print('selftest: lib.fibers.cond')
   local lib = require('core.lib')
   local fiber = require('lib.fibers.fiber')
   local cond, log = new(), {}
   local function record(x) table.insert(log, x) end

   fiber.spawn(function() record('a'); cond:wait(); record('b') end)
   fiber.spawn(function() record('c'); cond:signal(); record('d') end)
   assert(lib.equal(log, {}))
   fiber.current_scheduler:run()
   assert(lib.equal(log, {'a', 'c', 'd'}))
   fiber.current_scheduler:run()
   assert(lib.equal(log, {'a', 'c', 'd', 'b'}))

   print('selftest: ok')
end
