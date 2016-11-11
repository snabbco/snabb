-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local S = require("syscall")
local ffi = require("ffi")
local lib = require("core.lib")
local schema = require("lib.yang.schema")
local yang_data = require("lib.yang.data")

-- Number of spaces a tab should consist of when indenting config.
local tab_spaces = 2

local function show_usage(status)
   print(require("program.config.get_config.README_inc"))
   main.exit(status)
end

local function parse_args(args)
   local handlers = {}
   handlers.h = function() show_usage(0) end
   args = lib.dogetopt(args, handlers, "h", {help="h"})
   if #args ~= 2 then show_usage(1) end
   return unpack(args)
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

function run(args)
   local socket_file_name, msg = parse_args(args)

   local socket = assert(S.socket("unix", "stream"))

   local sa = S.t.sockaddr_un(socket_file_name)
   assert(socket:connect(sa))

   socket:write(tostring(#msg)..'\n'..msg)

   local len = read_length(socket)
   local msg = read_msg(socket, len)
   print(msg)

   socket:close()
   main.exit(0)
end
