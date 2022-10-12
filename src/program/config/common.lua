-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local S = require("syscall")
local ffi = require("ffi")
local lib = require("core.lib")
local shm = require("core.shm")
local mem = require("lib.stream.mem")
local file = require("lib.stream.file")
local rpc = require("lib.yang.rpc")
local yang = require("lib.yang.yang")
local data = require("lib.yang.data")
local path_data = require("lib.yang.path_data")
local path_resolver = require("lib.yang.path_data").resolver

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
   require_schema = { default=false },
   is_config = { default=true },
   usage = { default=show_usage },
   allow_extra_args = { default=false },
}

local function path_grammar(schema_name, path, is_config)
   local schema = yang.load_schema_by_name(schema_name)
   local grammar = data.data_grammar_from_schema(schema, is_config)
   local getter, subgrammar = path_resolver(grammar, path)
   return subgrammar
end

function data_parser(schema_name, path, is_config)
   local grammar = path_grammar(schema_name, path, is_config)
   local parser = data.data_parser_from_grammar(grammar)
   local validator = path_data.consistency_checker_from_grammar(grammar)
   return function (data)
      local config = parser(data)
      validator(config)
      return config
   end
end

function config_parser(schema_name, path)
   return data_parser(schema_name, path, true)
end

function state_parser(schema_name, path)
   return data_parser(schema_name, path, false)
end

function error_and_quit(err)
   io.stderr:write(err .. "\n")
   io.stderr:flush()
   os.exit(1)
end

function validate_path(schema_name, path, is_config)
   local succ, err = pcall(path_grammar, schema_name, path, is_config)
   if succ == false then
      local filename, lineno, msg = err:match("(.+):(%d+):(.+)$")
      error_and_quit(("Invalid path:"..msg) or err)
   end
end

function parse_command_line(args, opts)
   opts = lib.parse(opts, parse_command_line_opts)
   local function err(msg) show_usage(opts.command, 1, msg) end
   local ret = {
      print_default = false,
      format = "yang",
   }
   if opts.usage then show_usage = opts.usage end
   local handlers = {}
   function handlers.h() show_usage(opts.command, 0) end
   function handlers.s(arg) ret.schema_name = arg end
   function handlers.r(arg) ret.revision_date = arg end
   function handlers.c(arg) ret.socket = arg end
   function handlers.f(arg)
      assert(arg == "yang" or arg == "xpath" or arg == "influxdb", "Not valid output format")
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
   if descr.error then
      return descr
   end
   if not ret.schema_name then
      if opts.require_schema then err("missing --schema arg") end
      ret.schema_name = descr.default_schema
   end
   require('lib.yang.schema').set_default_capabilities(descr.capability)
   if not pcall(yang.load_schema_by_name, ret.schema_name) then
      local response = call_leader(
         ret.instance_id, 'get-schema',
         {schema=ret.schema_name, revision=ret.revision_date})
      assert(not response.error, response.error)
      yang.add_schema(response.source, ret.schema_name)
   end
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
      validate_path(ret.schema_name, ret.path, opts.is_config)
   end
   if opts.with_value then
      local parser = data_parser(ret.schema_name, ret.path, opts.is_config)
      local stream
      if #args == 0 then
         stream = file.fdopen(S.stdin, 'rdonly')
      else
         stream = mem.open_input_string(table.remove(args, 1))
      end
      ret.value = parser(stream)
   end
   if not opts.allow_extra_args and #args ~= 0 then err("too many arguments") end
   return ret, args
end

function open_socket(instance_id)
   S.signal('pipe', 'ign')
   local socket = assert(S.socket("unix", "stream"))
   local tail = instance_id..'/config-leader-socket'
   local by_name = S.t.sockaddr_un(shm.root..'/by-name/'..tail)
   local by_pid = S.t.sockaddr_un(shm.root..'/'..tail)
   if not socket:connect(by_name) and not socket:connect(by_pid) then
      socket:close()
      return nil
   end
   return file.fdopen(socket, 'rdwr')
end

function data_serializer(schema_name, path, is_config)
   local grammar = path_grammar(schema_name, path or '/', is_config)
   return data.data_printer_from_grammar(grammar)
end

function serialize_data(data, schema_name, path, is_config)
   local printer = data_serializer(schema_name, path, is_config)
   return mem.call_with_output_string(printer, data)
end

function serialize_config(config, schema_name, path)
   return serialize_data(config, schema_name, path, true)
end

function serialize_state(config, schema_name, path)
   return serialize_data(config, schema_name, path, false)
end

function send_message(socket, msg_str)
   socket:write_chars(tostring(#msg_str))
   socket:write_chars('\n')
   socket:write_chars(msg_str)
   socket:flush()
end

local function read_length(socket)
   local line = socket:read_line()
   if line == nil then error('unexpected EOF when reading length') end
   local len = assert(tonumber(line), 'not a number: '..line)
   assert(len >= 0 and len == math.floor(len), 'bad length: '..len)
   return len
end

local function read_msg(socket, len)
   return socket:read_chars(len)
end

function recv_message(socket)
   return read_msg(socket, read_length(socket))
end

function call_leader(instance_id, method, args)
   local caller = rpc.prepare_caller('snabb-config-leader-v1')
   local socket = open_socket(instance_id)
   if not socket then
      return {
         status = 1,
         error = ("Could not connect to config leader socket on Snabb instance %q")
            :format(instance_id)
      }
   end
   -- FIXME: stream call and response.
   local msg, parse_reply = rpc.prepare_call(caller, method, args)
   send_message(socket, msg)
   local reply = recv_message(socket)
   socket:close()
   return parse_reply(mem.open_input_string(reply))
end

function print_and_exit(response, response_prop)
   if response.error then
      print(response.error)
   elseif response_prop then
      print(response[response_prop])
   end
   main.exit(response.status)
end
