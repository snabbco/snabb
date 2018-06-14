-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local S = require("syscall")
local lib = require("core.lib")
local shm = require("core.shm")
local file = require("lib.stream.file")
local socket = require("lib.stream.socket")
local fiber = require("lib.fibers.fiber")
local json = require("lib.ptree.json")

function show_usage(status, err_msg)
   if err_msg then print('error: '..err_msg) end
   print(require("program.alarms.listen.README_inc"))
   main.exit(status)
end

local function parse_command_line(args)
   local handlers = {}
   function handlers.h() show_usage(0) end
   args = lib.dogetopt(args, handlers, "h", {help="h"})
   if #args ~= 1 then show_usage(1) end
   return unpack(args)
end

local function connect(instance_id)
   local tail = instance_id..'/notifications'
   local ok, ret = pcall(socket.connect_unix, shm.root..'/by-name/'..tail)
   if not ok then
      ok, ret = pcall(socket.connect_unix, shm.root..'/'..tail)
   end
   if ok then return ret end
   error("Could not connect to notifications socket on Snabb instance '"..
            instance_id.."'.\n")
end

function run(args)
   local instance_id = parse_command_line(args)
   local handler = require('lib.fibers.file').new_poll_io_handler()
   file.set_blocking_handler(handler)
   fiber.current_scheduler:add_task_source(handler)
   require('lib.stream.compat').install()

   local function print_notifications()
      local socket = connect(instance_id)
      while true do
         local obj = json.read_json(socket)
         if obj == nil then return end
         json.write_json(io.stdout, obj)
         io.stdout:write_chars("\n")
         io.stdout:flush_output()
      end
   end

   local function exit_when_finished(f)
      return function()
         local success, res = pcall(f)
         if not success then io.stderr:write('error: '..tostring(res)..'\n') end
         os.exit(success and 0 or 1)
      end
   end

   fiber.spawn(exit_when_finished(print_notifications))
   fiber.main()
end
