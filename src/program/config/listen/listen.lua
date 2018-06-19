-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local S = require("syscall")
local ffi = require("ffi")
local fiber = require("lib.fibers.fiber")
local queue = require("lib.fibers.queue")
local mem = require("lib.stream.mem")
local file = require("lib.stream.file")
local rpc = require("lib.yang.rpc")
local data = require("lib.yang.data")
local path_lib = require("lib.yang.path")
local json_lib = require("lib.ptree.json")
local common = require("program.config.common")

local function open_socket(file)
   S.signal('pipe', 'ign')
   local socket = assert(S.socket("unix", "stream"))
   S.unlink(file)
   local sa = S.t.sockaddr_un(file)
   assert(socket:bind(sa))
   assert(socket:listen())
   return socket
end

local function validate_config(schema_name, revision_date, path, value_str)
   local parser = common.config_parser(schema_name, path)
   local value = parser(mem.open_input_string(value_str))
   return common.serialize_config(value, schema_name, path)
end

local request_handlers = {}
function request_handlers.get(schema_name, revision_date, path)
   return {method='get-config',
           args={schema=schema_name, revision=revision_date, path=path}}
end
function request_handlers.get_state(schema_name, revision_date, path)
   return {method='get-state',
           args={schema=schema_name, revision=revision_date, path=path}}
end
function request_handlers.set(schema_name, revision_date, path, value)
   assert(value ~= nil)
   local config = validate_config(schema_name, revision_date, path, value)
   return {method='set-config',
           args={schema=schema_name, revision=revision_date, path=path,
                 config=config}}
end
function request_handlers.add(schema_name, revision_date, path, value)
   assert(value ~= nil)
   local config = validate_config(schema_name, revision_date, path, value)
   return {method='add-config',
           args={schema=schema_name, revision=revision_date, path=path,
                 config=config}}
end
function request_handlers.remove(schema_name, revision_date, path)
   return {method='remove-config',
           args={schema=schema_name, revision=revision_date, path=path}}
end

local function read_request(client, schema_name, revision_date)
   local json = json_lib.read_json(client)
   if json == nil then
      -- The input pipe is closed.  FIXME: there could still be buffered
      -- responses; we should exit only once we've received them.
      io.stderr:write('Input pipe closed.\n')
      os.exit(0)
   end
   local id, verb, path = assert(json.id), assert(json.verb), json.path or '/'
   path = path_lib.normalize_path(path)
   if json.schema then schema_name = json.schema end
   if json.revision then revision_date = json.revision end
   local handler = assert(request_handlers[data.normalize_id(verb)])
   local req = handler(schema_name, revision_date, path, json.value)
   local function print_reply(reply, output)
      local value
      if verb == 'get' then value = reply.config
      elseif verb == 'get-state' then value = reply.state
      end
      json_lib.write_json(output, {id=id, status='ok', value=value})
      output:flush()
   end
   return req, print_reply
end

local function attach_listener(leader, caller, schema_name, revision_date)
   local msg, parse_reply = rpc.prepare_call(
      caller, 'attach-listener', {schema=schema_name, revision=revision_date})
   common.send_message(leader, msg)
   return parse_reply(mem.open_input_string(common.recv_message(leader)))
end

function run(args)
   args = common.parse_command_line(args, { command='listen' })
   local caller = rpc.prepare_caller('snabb-config-leader-v1')
   local leader = common.open_socket_or_die(args.instance_id)
   attach_listener(leader, caller, args.schema_name, args.revision_date)
   
   local handler = require('lib.fibers.file').new_poll_io_handler()
   file.set_blocking_handler(handler)
   fiber.current_scheduler:add_task_source(handler)
   -- Leader was blocking in call to attach_listener.
   leader:nonblock()

   -- Check if there is a socket path specified, if so use that as method
   -- to communicate, otherwise use stdin and stdout.
   local client_rx, client_tx = nil
   if args.socket then
      local sockfd = open_socket(args.socket)
      local addr = S.t.sockaddr_un()
      -- Wait for a connection
      print("Listening for clients on socket: "..args.socket)
      client_rx = file.fdopen(assert(sockfd:accept(addr)))
      client_tx = client_rx
   else
      client_rx = file.fdopen(S.stdin)
      client_tx = file.fdopen(S.stdout)
   end
      
   local pending_replies = queue.new()
   local function exit_when_finished(f)
      return function()
         local success, res = pcall(f)
         if not success then io.stderr:write('error: '..tostring(res)..'\n') end
         os.exit(success and 0 or 1)
      end
   end
   local function handle_requests()
      while true do
         -- FIXME: Better error message on read-from-client failures.
         local request, print_reply =
            read_request(client_rx, args.schema_name, args.revision_date)
         local msg, parse_reply = rpc.prepare_call(
            caller, request.method, request.args)
         local function have_reply(msg)
            msg = mem.open_input_string(msg)
            return print_reply(parse_reply(msg), client_tx)
         end
         pending_replies:put(have_reply)
         -- FIXME: Better error message on write-to-leader failures.
         common.send_message(leader, msg)
      end
   end
   local function handle_replies()
      while true do
         local handle_reply = pending_replies:get()
         -- FIXME: Better error message on read-from-leader failures.
         -- FIXME: Better error message on write-to-client failures.
         handle_reply(common.recv_message(leader))
      end
   end

   fiber.spawn(exit_when_finished(handle_requests))
   fiber.spawn(exit_when_finished(handle_replies))
   fiber.main()
end
