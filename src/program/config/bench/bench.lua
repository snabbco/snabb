-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local S = require("syscall")
local lib = require("core.lib")
local ffi = require("ffi")
local file = require("lib.stream.file")
local mem = require("lib.stream.mem")
local fiber = require("lib.fibers.fiber")
local json_lib = require("lib.ptree.json")

function show_usage(command, status, err_msg)
   if err_msg then print('error: '..err_msg) end
   print(require("program.config.bench.README_inc"))
   main.exit(status)
end

function parse_command_line(args)
   local function err(msg) show_usage(1, msg) end
   local listen_params = {}
   local handlers = {}
   function handlers.h() show_usage(0) end
   function handlers.s(arg) listen_params.schema_name = arg end
   function handlers.r(arg) listen_params.revision_date = arg end
   args = lib.dogetopt(args, handlers, "hs:r:",
                       {help="h", ['schema-name']="s", schema="s",
                        ['revision-date']="r", revision="r"})
   if #args ~= 2 then err() end
   local commands_file
   listen_params.instance_id, commands_file = unpack(args)
   return listen_params, commands_file
end

local function read_commands(filename)
   local input = assert(file.open(filename, 'r'))
   local ret = {}
   while true do
      local obj = json_lib.read_json(input)
      if obj == nil then break end
      local function write_json(out)
         json_lib.write_json(out, obj)
      end
      table.insert(ret, mem.call_with_output_string(write_json))
   end
   input:close()
   return ret
end

-- The stock Lua popen interface does not support full-duplex operation;
-- it would need to return two pipes.
local function popen_rw(filename, argv)
   local ok, err, input_read, input_write = assert(S.pipe())
   local ok, err, output_read, output_write = assert(S.pipe())
   local pid = S.fork()
   if pid == 0 then
      S.prctl("set_pdeathsig", "hup")
      input_write:close()
      output_read:close()
      assert(S.dup2(input_read, 0))
      assert(S.dup2(output_write, 1))
      input_read:close()
      output_write:close()
      lib.execv(filename, argv)
   end
   input_read:close()
   output_write:close()

   return pid, file.fdopen(input_write), file.fdopen(output_read)
end

local function spawn_snabb_config_listen(params)
   local argv = {"snabb", "config", "listen"}
   if params.schema_name then
      table.insert(argv, "-s")
      table.insert(argv, params.schema_name)
   end
   if params.revision_date then
      table.insert(argv, "-r")
      table.insert(argv, params.revision_date)
   end
   table.insert(argv, params.instance_id)
   return popen_rw("/proc/self/exe", argv)
end

function run(args)
   local handler = require('lib.fibers.file').new_poll_io_handler()
   file.set_blocking_handler(handler)
   fiber.current_scheduler:add_task_source(handler)

   local listen_params, filename = parse_command_line(args)
   local pid, tx, rx = spawn_snabb_config_listen(listen_params)
   local commands = read_commands(filename)

   io.stdout:setvbuf("no")

   local function exit_if_error(f)
      return function()
         local success, res = pcall(f)
         if not success then
            io.stderr:write('error: '..tostring(res)..'\n')
            os.exit(1)
         end
      end
   end

   local function send_requests()
      for i,command in ipairs(commands) do
         tx:write_chars(command)
         io.stdout:write("w")
      end
      io.stdout:write("!")
      tx:flush()
   end
   local function read_replies()
      for i=1,#commands do
         local ok, obj = pcall(json_lib.read_json, rx)
         if not ok then error('failed to read json obj: '..tostring(obj)) end
         if not obj then error('unexpected EOF while reading response') end
         io.stdout:write("r")
      end
      fiber.stop()
   end

   fiber.spawn(exit_if_error(send_requests))
   fiber.spawn(exit_if_error(read_replies))

   local start = engine.now()
   fiber.main()
   local elapsed = engine.now() - start
   io.stdout:write("\n")
   print(string.format("Issued %s commands in %.2f seconds (%.2f commands/s)",
                       #commands, elapsed, #commands/elapsed))
   main.exit(0)
end
