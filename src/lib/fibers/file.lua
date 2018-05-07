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
   self:wait_for_readable_op(fd):perform()
end
function PollIOHandler:wait_for_writable(fd)
   self:wait_for_writable_op(fd):perform()
end

local function add_waiter(fd, waiters, task)
   local tasks = waiters[fd]
   if tasks == nil then tasks = {}; waiters[fd] = tasks end
   table.insert(tasks, task)
end

function PollIOHandler:wait_for_readable_op(fd)
   local function try() return false end
   local function block(suspension, wrap_fn)
      local task = suspension:complete_task(wrap_fn)
      local fd = fd:getfd()
      add_waiter(fd, self.waiting_for_readable, task)
      self.epoll:add(fd, epoll.RD)
   end
   return op.new_base_op(nil, try, block)
end

function PollIOHandler:wait_for_writable_op(fd)
   local function try() return false end
   local function block(suspension, wrap_fn)
      local task = suspension:complete_task(wrap_fn)
      local fd = fd:getfd()
      add_waiter(fd, self.waiting_for_writable, task)
      self.epoll:add(fd, epoll.WR)
   end
   return op.new_base_op(nil, try, block)
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

function PollIOHandler:cancel_tasks_for_fd(fd)
   local function cancel_tasks(waiting)
      local tasks = waiting[fd]
      if tasks ~= nil then
         for i=1,#tasks do tasks[i]:cancel() end
         waiting[fd] = nil
      end
   end
   cancel_tasks(self.waiting_for_readable)
   cancel_tasks(self.waiting_for_writable)
end

function PollIOHandler:cancel_all_tasks()
   for fd,_ in pairs(self.waiting_for_readable) do
      self:cancel_tasks_for_fd(fd)
   end
   for fd,_ in pairs(self.waiting_for_writable) do
      self:cancel_tasks_for_fd(fd)
   end
end

local installed = 0
function install_poll_io_handler()
   installed = installed + 1
   if installed == 1 then
      local handler = new_poll_io_handler()
      file.set_blocking_handler(handler)
      fiber.current_scheduler:add_task_source(handler)
   end
end

function uninstall_poll_io_handler()
   installed = installed - 1
   if installed == 0 then
      file.set_blocking_handler(nil)
      -- FIXME: Remove task source.
      for i,source in ipairs(fiber.current_scheduler.sources) do
         if getmetatable(source) == PollIOHandler_mt then
            table.remove(fiber.current_scheduler.sources, i)
            source.epoll:close()
            break
         end
      end
   end
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
