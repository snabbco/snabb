-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local S = require("syscall")
local ffi = require("ffi")
local lib = require("core.lib")
local schema = require("lib.yang.schema")
local yang = require("lib.yang.yang")
local data = require("lib.yang.data")

-- Number of spaces a tab should consist of when indenting config.
local tab_spaces = 2

local function show_usage(status)
   print(require("program.config.get_config.README_inc"))
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
   local instance_id, path = unpack(args)
   return schema_name, revision_date, instance_id, path
end

local function read_length(socket)
   local len = 0
   while true do
      local ch = assert(socket:read(nil, 1))
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

function prepare_rpc_list(rpcs)
   local schema = yang.load_schema_by_name('snabb-config-leader-v1')
   local print_input = data.rpc_input_printer_from_schema(schema)
   local parse_output = data.rpc_output_parser_from_schema(schema)
   return print_input(rpcs), parse_output
end

function prepare_rpc(id, data)
   local str, parse_responses = prepare_rpc_list({{id=id, data=data}})
   local function parse_response(str)
      local responses = parse_responses(str)
      assert(#responses == 1)
      assert(responses[1].id == id)
      return responses[1].data
   end
   return str, parse_response
end

function run(args)
   local schema_name, revision_date, instance_id, path = parse_args(args)
   local data = { schema = schema_name, revision = revision_date, path = path }
   local message, parse_response = prepare_rpc('get-config', data)

   print(message)

   local socket = assert(S.socket("unix", "stream"))
   local sa = S.t.sockaddr_un(instance_id)
   assert(socket:connect(sa))
   socket:write(tostring(#message)..'\n'..message)
   local len = read_length(socket)
   local msg = read_msg(socket, len)
   socket:close()

   print(parse_response(msg))

   main.exit(0)
end
