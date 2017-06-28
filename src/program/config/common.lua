-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local S = require("syscall")
local ffi = require("ffi")
local lib = require("core.lib")
local shm = require("core.shm")
local rpc = require("lib.yang.rpc")
local yang = require("lib.yang.yang")
local data = require("lib.yang.data")
local path_resolver = require("lib.yang.path").resolver

function show_usage(command, status, err_msg)
   if err_msg then print('error: '..err_msg) end
   print(require("program.config."..command:gsub('-','_')..".README_inc"))
   main.exit(status)
end

local parse_command_line_opts = {
   command = { required=true },
   with_config_file = { default=false },
   with_path = { default=false },
   with_value = { default=false },
   require_schema = { default=false }
}

local function path_grammar(schema_name, path)
   local schema = yang.load_schema_by_name(schema_name)
   local grammar = data.data_grammar_from_schema(schema)
   local getter, subgrammar = path_resolver(grammar, path)
   return subgrammar
end

function data_parser(schema_name, path)
   return data.data_parser_from_grammar(path_grammar(schema_name, path))
end

function error_and_quit(err)
   io.stderr:write(err .. "\n")
   io.stderr:flush()
   os.exit(1)
end

function validate_path(schema_name, path)
   local succ, err = pcall(path_grammar, schema_name, path)
   if succ == false then
      error_and_quit(err)
   end
end

function parse_command_line(args, opts)
   opts = lib.parse(opts, parse_command_line_opts)
   local function err(msg) show_usage(opts.command, 1, msg) end
   local ret = {
      print_default = false,
      format = "yang",
   }
   local handlers = {}
   function handlers.h() show_usage(opts.command, 0) end
   function handlers.s(arg) ret.schema_name = arg end
   function handlers.r(arg) ret.revision_date = arg end
   function handlers.c(arg) ret.socket = arg end
   function handlers.f(arg)
      assert(arg == "yang" or arg == "xpath", "Not valid output format")
      ret.format = arg
   end
   handlers['print-default'] = function ()
      ret.print_default = true
   end
   args = lib.dogetopt(args, handlers, "hs:r:c:f:",
                       {help="h", ['schema-name']="s", schema="s",
                        ['revision-date']="r", revision="r", socket="c",
                        ['print-default']=0, format="f"})
   if #args == 0 then err() end
   ret.instance_id = table.remove(args, 1)
   local descr = call_leader(ret.instance_id, 'describe', {})
   if not ret.schema_name then
      if opts.require_schema then err("missing --schema arg") end
      ret.schema_name = descr.native_schema
   end
   require('lib.yang.schema').set_default_capabilities(descr.capability)
   if opts.with_config_file then
      if #args == 0 then err("missing config file argument") end
      local file = table.remove(args, 1)
      local opts = {schema_name=ret.schema_name,
                    revision_date=ret.revision_date}
      ret.config_file = file
      ret.config = yang.load_configuration(file, opts)
   end
   if opts.with_path then
      if #args == 0 then err("missing path argument") end
      ret.path = table.remove(args, 1)
      validate_path(ret.schema_name, ret.path)
   end
   if opts.with_value then
      local parser = data_parser(ret.schema_name, ret.path)
      if #args == 0 then
         ret.value_str = io.stdin:read('*a')
      else
         ret.value_str = table.remove(args, 1)
      end
      ret.value = parser(ret.value_str)
   end
   if #args ~= 0 then err("too many arguments") end
   return ret
end

function open_socket_or_die(instance_id)
   S.signal('pipe', 'ign')
   local socket = assert(S.socket("unix", "stream"))
   local tail = instance_id..'/config-leader-socket'
   local by_name = S.t.sockaddr_un(shm.root..'/by-name/'..tail)
   local by_pid = S.t.sockaddr_un(shm.root..'/'..tail)
   if not socket:connect(by_name) and not socket:connect(by_pid) then
      io.stderr:write(
         "Could not connect to config leader socket on Snabb instance '"..
            instance_id.."'.\n")
      main.exit(1)
   end
   return socket
end

function serialize_config(config, schema_name, path)
   local grammar = path_grammar(schema_name, path or '/')
   local printer = data.data_printer_from_grammar(grammar)
   return printer(config, yang.string_output_file())
end

function send_message(socket, msg_str)
   socket:write(tostring(#msg_str)..'\n'..msg_str)
end

local function read_length(socket)
   local len = 0
   while true do
      local ch = assert(socket:read(nil, 1))
      assert(ch ~= '', 'short read')
      if ch == '\n' then return len end
      assert(tonumber(ch), 'not a number: '..ch)
      len = len * 10 + tonumber(ch)
      assert(len < 1e8, 'length too long: '..len)
   end
end

local function read_msg(socket, len)
   local buf = ffi.new('uint8_t[?]', len)
   local pos = 0
   while pos < len do
      local count = assert(socket:read(buf+pos, len-pos))
      if count == 0 then error('short read') end
      pos = pos + count
   end
   return ffi.string(buf, len)
end

function recv_message(socket)
   return read_msg(socket, read_length(socket))
end

function call_leader(instance_id, method, args)
   local caller = rpc.prepare_caller('snabb-config-leader-v1')
   local socket = open_socket_or_die(instance_id)
   local msg, parse_reply = rpc.prepare_call(caller, method, args)
   send_message(socket, msg)
   local reply = recv_message(socket)
   socket:close()
   return parse_reply(reply)
end

function print_and_exit(response, response_prop)
   if response.error then
      print(response.error)
   elseif response_prop then
      print(response[response_prop])
   end
   main.exit(response.status)
end
