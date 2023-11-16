-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Timeout events.

module(..., package.seeall)

local op = require('lib.fibers.op')
local fiber = require('lib.fibers.fiber')
local epoll = require('lib.fibers.epoll')
local file = require('lib.stream.file')
local bit = require('bit')

local PollIOHandler = {}
local PollIOHandler_mt = { __index=PollIOHandler }
function new_poll_io_handler()
   return setmetatable(
      { epoll=epoll.new(),
        waiting_for_readable={},   -- sock descriptor => array of task
        waiting_for_writable={} }, -- sock descriptor => array of task
      PollIOHandler_mt)
end

-- These three methods are "blocking handler" methods and are called by
-- lib.stream.file.
function PollIOHandler:init_nonblocking(fd)
   fd:nonblock()
end
function PollIOHandler:wait_for_readable(fd)
   self:fd_readable_op(fd):perform()
end
function PollIOHandler:wait_for_writable(fd)
   self:fd_writable_op(fd):perform()
end

local function add_waiter(fd, waiters, task)
   local tasks = waiters[fd]
   if tasks == nil then tasks = {}; waiters[fd] = tasks end
   table.insert(tasks, task)
end

local function make_block_fn(fd, waiting, epoll, events)
   return function(suspension, wrap_fn)
      local task = suspension:complete_task(wrap_fn)
      local fd = fd:getfd()
      add_waiter(fd, waiting, task)
      epoll:add(fd, events)
   end
end

function PollIOHandler:fd_readable_op(fd)
   local function try() return false end
   local block = make_block_fn(
      fd, self.waiting_for_readable, self.epoll, epoll.RD)
   return op.new_base_op(nil, try, block)
end

function PollIOHandler:fd_writable_op(fd)
   local function try() return false end
   local block = make_block_fn(
      fd, self.waiting_for_writable, self.epoll, epoll.WR)
   return op.new_base_op(nil, try, block)
end

function PollIOHandler:stream_readable_op(stream)
   local fd = assert(stream.io.fd)
   local function try() return not stream.rx:is_empty() end
   local block = make_block_fn(
      fd, self.waiting_for_readable, self.epoll, epoll.RD)
   return op.new_base_op(nil, try, block)
end

-- A stream_writable_op is the same as fd_writable_op, as a stream's
-- buffer is never left full -- any stream method that fills the buffer
-- flushes it directly.  Knowing something about the buffer state
-- doesn't tell us anything useful.
function PollIOHandler:stream_writable_op(stream)
   local fd = assert(stream.io.fd)
   return self:fd_writable_op(fd)
end

local function schedule_tasks(sched, tasks)
   -- It's possible for tasks to be nil, as an IO error will notify for
   -- both readable and writable, and maybe we only have tasks waiting
   -- for one side.
   if tasks == nil then return end
   for i=1,#tasks do
      sched:schedule(tasks[i])
      tasks[i] = nil
   end
end

-- These method is called by the fibers scheduler.
function PollIOHandler:schedule_tasks(sched, now, timeout)
   if timeout == nil then timeout = 0 end
   if timeout >= 0 then timeout = timeout * 1e3 end
   for _, event in self.epoll:poll(timeout) do
      if bit.band(event.events, epoll.RD + epoll.ERR) ~= 0 then
         local tasks = self.waiting_for_readable[event.data.fd]
         schedule_tasks(sched, tasks)
      end
      if bit.band(event.events, epoll.WR + epoll.ERR) ~= 0 then
         local tasks = self.waiting_for_writable[event.data.fd]
         schedule_tasks(sched, tasks)
      end
   end
end

PollIOHandler.wait_for_events = PollIOHandler.schedule_tasks

function PollIOHandler:cancel_tasks_for_fd(fd, reason)
   local function cancel_tasks(waiting)
      local tasks = waiting[fd]
      if tasks ~= nil then
         for i=1,#tasks do tasks[i]:cancel(reason) end
         waiting[fd] = nil
      end
   end
   cancel_tasks(self.waiting_for_readable)
   cancel_tasks(self.waiting_for_writable)
end

function PollIOHandler:cancel_all_tasks(sched, reason)
   for fd,_ in pairs(self.waiting_for_readable) do
      self:cancel_tasks_for_fd(fd, reason)
   end
   for fd,_ in pairs(self.waiting_for_writable) do
      self:cancel_tasks_for_fd(fd, reason)
   end
end

local installed = 0
local installed_poll_handler
function install_poll_io_handler()
   installed = installed + 1
   if installed == 1 then
      installed_poll_handler = new_poll_io_handler()
      file.set_blocking_handler(installed_poll_handler)
      fiber.current_scheduler:add_task_source(installed_poll_handler)
   end
   return installed_poll_handler
end

function uninstall_poll_io_handler()
   installed = installed - 1
   if installed == 0 then
      file.set_blocking_handler(nil)
      -- FIXME: Remove task source.
      for i,source in ipairs(fiber.current_scheduler.sources) do
         if source == installed_poll_handler then
            table.remove(fiber.current_scheduler.sources, i)
            break
         end
      end
      installed_poll_handler.epoll:close()
      installed_poll_handler = nil
   end
end

function fd_readable_op(fd)
   return assert(installed_poll_handler):fd_readable_op(fd)
end
function fd_writable_op(fd)
   return assert(installed_poll_handler):fd_writable_op(fd)
end
function stream_readable_op(stream)
   return assert(installed_poll_handler):stream_readable_op(stream)
end
function stream_writable_op(stream)
   return assert(installed_poll_handler):stream_writable_op(stream)
end

function selftest()
   print('selftest: lib.fibers.file')
   local lib = require('core.lib')
   local log = {}
   local function record(x) table.insert(log, x) end

   local handler = new_poll_io_handler()
   file.set_blocking_handler(handler)
   fiber.current_scheduler:add_task_source(handler)

   fiber.current_scheduler:run()
   assert(lib.equal(log, {}))

   local rd, wr = file.pipe()
   local message = "hello, world\n"
   fiber.spawn(function()
                  record('rd-a')
                  local str = rd:read_some_chars()
                  record('rd-b')
                  record(str)
               end)
   fiber.spawn(function()
                  record('wr-a')
                  wr:write(message)
                  record('wr-b')
                  wr:flush()
                  record('wr-c')
               end)

   fiber.current_scheduler:run()
   assert(lib.equal(log, {'rd-a', 'wr-a', 'wr-b', 'wr-c'}))
   fiber.current_scheduler:run()
   assert(lib.equal(log, {'rd-a', 'wr-a', 'wr-b', 'wr-c', 'rd-b', message}))

   print('selftest: ok')
end
