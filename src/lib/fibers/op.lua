-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Concurrent ML operations.

module(..., package.seeall)

local fiber = require('lib.fibers.fiber')

-- A suspension represents an instantiation of an operation that a fiber
-- has to wait on because it can't complete directly.  Some other event
-- will cause the operation to complete and cause the fiber to resume.
-- Since a suspension has a run method, it is also a task and so can be
-- scheduled directly.
local Suspension = {}
Suspension.__index = Suspension
local CompleteTask = {}
CompleteTask.__index = CompleteTask
function Suspension:waiting() return self.state == 'waiting' end
function Suspension:complete(wrap, val)
   assert(self:waiting())
   self.state = 'synchronized'
   self.wrap = wrap
   self.val = val
   self.sched:schedule(self)
end
function Suspension:complete_and_run(wrap, val)
   assert(self:waiting())
   self.state = 'synchronized'
   return self.fiber:resume(wrap, val)
end
function Suspension:complete_task(wrap, val)
   return setmetatable({suspension=self, wrap=wrap, val=val}, CompleteTask)
end
function Suspension:run() -- Task method.
   assert(not self:waiting())
   return self.fiber:resume(self.wrap, self.val)
end
local function new_suspension(sched, fiber)
   return setmetatable(
      { state='waiting', sched=sched, fiber=fiber },
      Suspension)
end

-- A complete task is a task that when run, completes a suspension, if
-- the suspension hasn't been completed already.  There can be multiple
-- complete tasks for a given suspension, if the suspension can complete
-- in multiple ways (e.g. via a choice op).
function CompleteTask:run()
   if self.suspension:waiting() then
      -- Use complete-and-run so that the fiber runs in this turn.
      self.suspension:complete_and_run(self.wrap, self.val)
   end
end

-- A complete task can also be cancelled, which makes it complete with a
-- call to "error".
function CompleteTask:cancel(reason)
   if self.suspension:waiting() then
      self.suspension:complete(error, reason or 'cancelled')
   end
end

-- An operation represents the potential for synchronization with some
-- external party.  An operation has to be instantiated by its "perform"
-- method, as if it were a thunk.  Note that Concurrent ML uses the term
-- "event" for "operation", and "synchronize" with "perform".

-- Base operations are the standard kind of operation.  A base operation
-- has three fields, which are all functions: "wrap_fn", which is called
-- on the result of a successfully performed operation; "try_fn", which
-- attempts to directly complete this operation in a non-blocking way;
-- and "block_fn", which is called after a fiber has suspended, and
-- which arranges to resume the fiber when the operation completes.
local BaseOp = {}
BaseOp.__index = BaseOp
function new_base_op(wrap_fn, try_fn, block_fn)
   if wrap_fn == nil then wrap_fn = function(val) return val end end
   return setmetatable(
      { wrap_fn=wrap_fn, try_fn=try_fn, block_fn=block_fn },
      BaseOp)
end

-- Choice operations represent a non-deterministic choice between a
-- number of sub-operations.  Performing a choice operation will perform
-- at most one of its sub-operations.
local ChoiceOp = {}
ChoiceOp.__index = ChoiceOp
local function new_choice_op(base_ops)
   return setmetatable(
      { base_ops=base_ops },
      ChoiceOp)
end

-- Given a set of operations, return a new operation that if it
-- succeeds, will succeed with one and only one of the sub-operations.
function choice(...)
   local ops = {}
   -- Build a flattened list of choices that are all base ops.
   for _, op in ipairs({...}) do
      if op.base_ops then
         for _, op in ipairs(op.base_ops) do table.insert(ops, op) end
      else
         table.insert(ops, op)
      end
   end
   if #ops == 1 then return ops[1] end
   return new_choice_op(ops)
end

-- :wrap method
--
-- Return a new operation that, if and when it succeeds, will apply F to
-- the values yielded by performing the wrapped operation, and yield the
-- result as the values of the wrapped operation.

function BaseOp:wrap(f)
   local wrap_fn, try_fn, block_fn = self.wrap_fn, self.try_fn, self.block_fn
   return new_base_op(function(val) return f(wrap_fn(val)) end, try_fn, block_fn)
end

function ChoiceOp:wrap(f)
   local ops = {}
   for _, op in ipairs(self.base_ops) do table.insert(ops, op:wrap(f)) end
   return new_choice_op(ops)
end

-- :perform method
--
-- Attempt to perform an operation, and return the resulting value (if
-- any).  If the operation can complete immediately, then return
-- directly.  Otherwise suspend the current fiber and continue only when
-- the operation completes.

local function block_base_op(sched, fiber, op)
   op.block_fn(new_suspension(sched, fiber), op.wrap_fn)
end
function BaseOp:perform()
   local success, val = self.try_fn()
   if success then return self.wrap_fn(val) end
   local wrap, val = fiber.suspend(block_base_op, self)
   return wrap(val)
end

local function block_choice_op(sched, fiber, ops)
   local suspension = new_suspension(sched, fiber)
   for _,op in ipairs(ops) do op.block_fn(suspension, op.wrap_fn) end
end
function ChoiceOp:perform()
   local ops = self.base_ops
   local base = math.random(#ops)
   for i=1,#ops do
      local op = ops[((i + base) % #ops) + 1]
      local success, val = op.try_fn()
      if success then return op.wrap_fn(val) end
   end
   local wrap, val = fiber.suspend(block_choice_op, ops)
   return wrap(val)
end
