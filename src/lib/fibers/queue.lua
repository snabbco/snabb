-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Concurrent ML buffered channel, implemented in the classic style with
-- a fiber buffering between two channels.

module(..., package.seeall)

local op = require('lib.fibers.op')
local channel = require('lib.fibers.channel')
local fiber = require('lib.fibers.fiber')

local Queue = {}

function new(bound)
   if bound then assert(bound >= 1) end
   local ch_in, ch_out = channel.new(), channel.new()
   function service_queue()
      local q = {}
      while true do
         if #q == 0 then
            -- Empty.
            table.insert(q, ch_in:get())
         elseif bound and #q >= bound then
            -- Full.
            ch_out:put(q[1])
            table.remove(q, 1)
         else
            local get_op = ch_in:get_operation()
            local put_op = ch_out:put_operation(q[1])
            local got_val = op.choice(get_op, put_op):perform()
            if got_val == nil then
               -- Put operation succeeded.
               table.remove(q, 1)
            else
               -- Get operation succeeded.
               table.insert(q, got_val)
            end
         end
      end
   end
   fiber.spawn(service_queue)
   local ret = {}
   function ret:put_operation(x)
      assert(x~=nil)
      return ch_in:put_operation(x)
   end
   function ret:get_operation()
      return ch_out:get_operation()
   end
   function ret:put(x) self:put_operation(x):perform() end
   function ret:get() return self:get_operation():perform() end
   return ret
end

function selftest()
   print('selftest: lib.fibers.queue')
   local lib = require('core.lib')
   local ch, log = new(), {}
   local function record(x) table.insert(log, x) end

   fiber.spawn(function()
         q = new()
         record('a');
         q:put('b');
         record('c');
         q:put('d');
         record('e');
         record(q:get())
         q:put('f');
         record('g');
         record(q:get())
         record('h');
         record(q:get())
   end)

   local function run(...)
      log = {}
      fiber.current_scheduler:run()
      assert(lib.equal(log, { ... }))
   end

   -- 1. Main fiber runs, creating queue fiber.  It blocks trying to
   -- hand off 'b' as the queue fiber hasn't run yet.
   run('a')
   -- 2. Queue fiber runs, taking 'b', and thereby resuming the main
   -- fiber (marking it runnable on the next turn).  Queue fiber blocks
   -- trying to get or put.
   run()
   -- 3. Main fiber runs, is able to put 'd' directly as the queue was
   -- waiting on it, then blocks waiting for a 'get'.  Putting 'd'
   -- resumed the queue fiber.
   run('c', 'e')
   -- 4. Queue fiber takes 'd' and is also able to put 'a', resuming the
   -- main fiber.
   run()
   -- 5. Main fiber receives 'b', is able to put 'f' directly, blocks
   -- getting from queue.
   run('b', 'g')
   -- 6. Queue fiber resumed with 'f', puts 'd', then blocks.
   run()
   -- 7. Main fiber resumed with 'd' and also succeeds getting 'f'.
   run('d', 'h', 'f')
   -- 8. Queue resumes and blocks.
   run()
   -- Nothing from here on out.
   for i=1,20 do run() end

   print('selftest: ok')
end
