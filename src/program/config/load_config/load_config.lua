-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local S = require("syscall")
local ffi = require("ffi")
local lib = require("core.lib")
local shm = require("core.shm")
local rpc = require("lib.yang.rpc")
local yang = require("lib.yang.yang")
local data = require("lib.yang.data")

-- Number of spaces a tab should consist of when indenting config.
local tab_spaces = 2

local function show_usage(status)
   print(require("program.config.load_config.README_inc"))
   main.exit(status)
end

local function parse_args(args)
   local schema_name, revision_date
   local handlers = {}
   function handlers.h() show_usage(0) end
   function handlers.s(arg) schema_name = arg end
   function handlers.r(arg) revision_date = arg end
   args = lib.dogetopt(args, handlers, "h:s:r",
                       {help="h", ['schema-name']="s", schema="s",
                        ['revision-date']="r", revision="r"})
   if not schema_name then show_usage(1) end
   if #args < 2 or #args > 2 then show_usage(1) end
   local instance_id, config_file = unpack(args)
   return schema_name, revision_date, instance_id, config_file
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

local function serialize_config(config, schema_name)
   -- FFS
   local schema = yang.load_schema_by_name(schema_name)
   local grammar = data.data_grammar_from_schema(schema)
   local printer = data.data_string_printer_from_grammar(grammar)
   return printer(config)
end

function run(args)
   local schema_name, revision_date, instance_id, config_file = parse_args(args)
   local caller = rpc.prepare_caller('snabb-config-leader-v1')
   local config = yang.load_configuration(config_file, {schema_name=schema_name})
   local config_str = serialize_config(config, schema_name)
   local data = { schema = schema_name, revision = revision_date,
                  config = config_str }
   local msg, parse = rpc.prepare_call(caller, 'load-config', data)
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
   socket:write(tostring(#msg)..'\n'..msg)
   local len = read_length(socket)
   msg = read_msg(socket, len)
   socket:close()
   main.exit(0)
end
