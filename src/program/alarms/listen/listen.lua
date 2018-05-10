-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local S = require("syscall")
local common = require("program.config.common")
local data = require("lib.yang.data")
local fiber = require("lib.fibers.fiber")
local file = require("lib.stream.file")
local mem = require("lib.stream.mem")
local path_lib = require("lib.yang.path")
local rpc = require("lib.yang.rpc")

local function open_socket(file)
   S.signal('pipe', 'ign')
   local socket = assert(S.socket("unix", "stream"))
   S.unlink(file)
   local sa = S.t.sockaddr_un(file)
   assert(socket:bind(sa))
   assert(socket:listen())
   return socket
end

local function attach_listener(leader, caller)
   local msg, parse_reply = rpc.prepare_call(
      caller, 'attach-notification-listener', {})
   common.send_message(leader, msg)
   return parse_reply(mem.open_input_string(common.recv_message(leader)))
end

function run(args)
   args = common.parse_command_line(args, { command='listen' })
   local caller = rpc.prepare_caller('snabb-config-leader-v1')
   local leader = common.open_socket_or_die(args.instance_id)
   attach_listener(leader, caller)
   
   local handler = require('lib.fibers.file').new_poll_io_handler()
   file.set_blocking_handler(handler)
   fiber.current_scheduler:add_task_source(handler)
   -- Leader was blocking in call to attach_listener.
   leader:nonblock()

   -- Check if there is a socket path specified, if so use that as method
   -- to communicate, otherwise use stdin and stdout.
   local client_tx
   if args.socket then
      local sockfd = open_socket(args.socket)
      local addr = S.t.sockaddr_un()
      -- Wait for a connection
      print("Listening for clients on socket: "..args.socket)
      client_tx = file.fdopen(assert(sockfd:accept(addr)))
   else
      client_tx = file.fdopen(S.stdout)
   end
      
   local function exit_when_finished(f)
      return function()
         local success, res = pcall(f)
         if not success then io.stderr:write('error: '..tostring(res)..'\n') end
         os.exit(success and 0 or 1)
      end
   end
   local function print_notification (output, msg)
      output:write_chars(msg)
      output:flush()
   end
   local function handle_outgoing ()
      while true do
         local msg = common.recv_message(leader)
         print_notification(client_tx, msg)
      end
   end

   fiber.spawn(exit_when_finished(handle_outgoing))

   while true do
      local sched = fiber.current_scheduler
      sched:run()
      -- FIXME: If we want to wait until tasks are runnable, the
      -- scheduler should handle that.
      if #sched.next == 0 then
         handler:schedule_tasks(sched, sched:now(), -1)
      end
   end
end
