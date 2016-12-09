-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local S = require("syscall")
local ffi = require("ffi")
local rpc = require("lib.yang.rpc")
local data = require("lib.yang.data")
local path_lib = require("lib.yang.path")
local common = require("program.config.common")
local json_lib = require("program.config.json")

local function validate_value(schema_name, revision_date, path, value_str)
   local parser = common.data_parser(schema_name, path)
   local value = parser(value_str)
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
   local config = validate_value(schema_name, revision_date, path, value)
   return {method='set-config',
           args={schema=schema_name, revision=revision_date, path=path,
                 config=config}}
end
function request_handlers.add(schema_name, revision_date, path, value)
   assert(value ~= nil)
   local config = validate_value(schema_name, revision_date, path, value)
   return {method='add-config',
           args={schema=schema_name, revision=revision_date, path=path,
                 config=config}}
end
function request_handlers.remove(schema_name, revision_date, path)
   return {method='remove-config',
           args={schema=schema_name, revision=revision_date, path=path}}
end

local function read_request(client, schema_name, revision_date)
   local json = json_lib.read_json_object(client)
   local id, verb, path = assert(json.id), assert(json.verb), assert(json.path)
   path = path_lib.normalize_path(path)
   local handler = assert(request_handlers[data.normalize_id(verb)])
   local req = handler(schema_name, revision_date, path, json.value)
   local function print_reply(reply)
      local output = json_lib.buffered_output()
      local value
      if verb == 'get' then value = reply.config
      elseif verb == 'get-state' then value = reply.state
      end
      json_lib.write_json_object(output, {id=id, status='ok', value=value})
      output:flush(S.stdout)
   end
   return req, print_reply
end

local function attach_listener(leader, caller, schema_name, revision_date)
   local msg, parse_reply = rpc.prepare_call(
      caller, 'attach-listener', {schema=schema_name, revision=revision_date})
   common.send_message(leader, msg)
   return parse_reply(common.recv_message(leader))
end

function run(args)
   args = common.parse_command_line(args, { command='listen' })
   local caller = rpc.prepare_caller('snabb-config-leader-v1')
   local leader = common.open_socket_or_die(args.instance_id)
   attach_listener(leader, caller, args.schema_name, args.revision_date)
   local client = json_lib.buffered_input(S.stdin)
   local pollfds = S.types.t.pollfds({
         {fd=leader, events="in"},
         {fd=client, events="in"}})
   local pending_replies = {}
   while true do
      if client:avail() == 0 then
         assert(S.poll(pollfds, -1))
      end
      for _,pfd in ipairs(pollfds) do
         if pfd.fd == leader:getfd() then
            if pfd.ERR or pfd.HUP then
               while #pending_replies > 0 do
                  local have_reply = table.remove(pending_replies)
                  have_reply(common.recv_message(leader))
               end
               io.stderr:write('Leader hung up\n')
               main.exit(1)
            elseif pfd.IN then
               assert(#pending_replies > 0)
               local have_reply = table.remove(pending_replies)
               have_reply(common.recv_message(leader))
            end
            pfd.revents = 0
         elseif pfd.fd == client:getfd() then
            if pfd.ERR or pfd.HUP or pfd.NVAL then
               io.stderr:write('Client hung up\n')
               main.exit(0)
            end
            if pfd.IN then
               -- The JSON objects sent to us by the client can have
               -- whitespace between them.  Make sure we don't block
               -- expecting a new datum when really it was just the
               -- remote side sending whitespace.  (Calling peek()
               -- causes the buffer to fill, which itself shouldn't
               -- block given the IN flag in the revents.)
               client:peek()
               json_lib.drop_buffered_whitespace(client)
            end
            while client:avail() > 0 do
               local request, print_reply =
                  read_request(client, args.schema_name, args.revision_date)
               json_lib.drop_buffered_whitespace(client)
               local msg, parse_reply = rpc.prepare_call(
                  caller, request.method, request.args)
               local function have_reply(msg)
                  return print_reply(parse_reply(msg))
               end
               common.send_message(leader, msg)
               table.insert(pending_replies, 1, have_reply)
            end
            pfd.revents = 0
         else
            error('unreachable')
         end
      end
   end
end
