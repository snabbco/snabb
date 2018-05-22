-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Concurrent ML channels.

module(..., package.seeall)

local op = require('lib.fibers.op')

local Fifo = {}
Fifo.__index = Fifo
local function new_fifo() return setmetatable({}, Fifo) end
function Fifo:push(x) table.insert(self, x) end
function Fifo:empty() return #self == 0 end
function Fifo:peek() assert(not self:empty()); return self[1] end
function Fifo:pop() assert(not self:empty()); return table.remove(self, 1) end

local Channel = {}

function new()
   return setmetatable(
      { getq=new_fifo(), putq=new_fifo() },
      {__index=Channel})
end

-- Make an operation that if and when it completes will rendezvous with
-- a receiver fiber to send VAL over the channel.
function Channel:put_operation(val)
   local getq, putq = self.getq, self.putq
   local function try()
      while not getq:empty() do
         local remote = getq:pop()
         if remote.suspension:waiting() then
            remote.suspension:complete(remote.wrap, val)
            return true
         end
         -- Otherwise the remote suspension is already completed, in
         -- which case we did the right thing to pop off the dead
         -- suspension from the getq.
      end
      return false
   end
   local function block(suspension, wrap_fn)
      -- First, a bit of GC.
      while not putq:empty() and not putq:peek().suspension:waiting() do
         putq:pop()
      end
      -- We have suspended the current fiber; arrange for the fiber
      -- to be resumed by a get operation by adding it to the channel's
      -- putq.
      putq:push({suspension=suspension, wrap=wrap_fn, val=val})
   end
   return op.new_base_op(nil, try, block)
end

-- Make an operation that if and when it completes will rendezvous with
-- a sender fiber to receive one value from the channel.
function Channel:get_operation()
   local getq, putq = self.getq, self.putq
   local function try()
      while not putq:empty() do
         local remote = putq:pop()
         if remote.suspension:waiting() then
            remote.suspension:complete(remote.wrap)
            return true, remote.val
         end
         -- Otherwise the remote suspension is already completed, in
         -- which case we did the right thing to pop off the dead
         -- suspension from the putq.
      end
      return false
   end
   local function block(suspension, wrap_fn)
      -- First, a bit of GC.
      while not getq:empty() and not getq:peek().suspension:waiting() do
         getq:pop()
      end
      -- We have suspended the current fiber; arrange for the fiber to
      -- be resumed by a put operation by adding it to the channel's
      -- getq.
      getq:push({suspension=suspension, wrap=wrap_fn})
   end
   return op.new_base_op(nil, try, block)
end

-- Send MESSAGE on the channel.  If there is already another fiber
-- waiting to receive a message on this channel, give it our message and
-- continue.  Otherwise, block until a receiver becomes available.
function Channel:put(message)
   self:put_operation(message):perform()
end

-- Receive a message from the channel and return it.  If there is
-- already another fiber waiting to send a message on this channel, take
-- its message directly.  Otherwise, block until a sender becomes
-- available.
function Channel:get()
   return self:get_operation():perform()
end

function selftest()
   print('selftest: lib.fibers.channel')
   local lib = require('core.lib')
   local fiber = require('lib.fibers.fiber')
   local ch, log = new(), {}
   local function record(x) table.insert(log, x) end

   fiber.spawn(function() record('a'); record(ch:get()) end)
   fiber.spawn(function() record('b'); ch:put('c'); record('d') end)
   assert(lib.equal(log, {}))
   fiber.current_scheduler:run()
   -- One turn: first fiber ran, suspended, then second fiber ran,
   -- completed first, and continued self to end.
   assert(lib.equal(log, {'a', 'b', 'd'}))
   fiber.current_scheduler:run()
   -- Next turn schedules first fiber and finishes.
   assert(lib.equal(log, {'a', 'b', 'd', 'c'}))

   log = {}
   fiber.spawn(function() record('b'); ch:put('c'); record('d') end)
   fiber.spawn(function() record('a'); record(ch:get()) end)
   assert(lib.equal(log, {}))
   fiber.current_scheduler:run()
   -- Reversed order.
   assert(lib.equal(log, {'b', 'a', 'c'}))
   fiber.current_scheduler:run()
   assert(lib.equal(log, {'b', 'a', 'c', 'd'}))

   print('selftest: ok')
end
