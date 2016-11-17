-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local S = require("syscall")
local ffi = require("ffi")
local lib = require("core.lib")
local shm = require("core.shm")
local rpc = require("lib.yang.rpc")
local yang = require("lib.yang.yang")
local data = require("lib.yang.data")

function show_usage(command, status, err_msg)
   if err_msg then print('error: '..err_msg) end
   print(require("program.config."..command:gsub('-','_')..".README_inc"))
   main.exit(status)
end

local parse_command_line_opts = {
   command = { required=true },
   with_config_file = { default=false },
   with_path = { default=false },
   with_value = { default=false }
}

function parse_command_line(args, opts)
   opts = lib.parse(opts, parse_command_line_opts)
   local function err(msg) show_usage(opts.command, 1, msg) end
   local schema_name, revision_date
   local handlers = {}
   function handlers.h() show_usage(opts.command, 0) end
   function handlers.s(arg) schema_name = arg end
   function handlers.r(arg) revision_date = arg end
   args = lib.dogetopt(args, handlers, "hs:r:",
                       {help="h", ['schema-name']="s", schema="s",
                        ['revision-date']="r", revision="r"})
   if not schema_name then err("missing --schema arg") end
   if #args == 0 then err() end
   local instance_id = table.remove(args, 1)
   local ret = { schema_name, revision_date, instance_id }
   if opts.with_config_file then
      if #args == 0 then err("missing config file argument") end
      local file = table.remove(args, 1)
      local opts = {schema_name=schema_name, revision_date=revision_date}
      table.insert(ret, yang.load_configuration(file, opts))
   end
   if opts.with_path then
      if #args == 0 then err("missing path argument") end
      local path = table.remove(args, 1)
      -- Waiting on our XPath parsing library :)
      if path ~= '/' then err("paths other than / currently unimplemented") end
      table.insert(ret, path)
   end
   if opts.with_value then
      local parser = data_parser(schema_name, path)
      if #args == 0 then
         table.insert(ret, parser(io.stdin:read('*a')))
      else
         table.insert(ret, parser(table.remove(args, 1)))
      end
   end
   if #args ~= 0 then err("too many arguments") end
   return unpack(ret)
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
   assert(path == nil or path == "/")
   -- FFS
   local schema = yang.load_schema_by_name(schema_name)
   local grammar = data.data_grammar_from_schema(schema)
   local printer = data.data_string_printer_from_grammar(grammar)
   return printer(config)
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
