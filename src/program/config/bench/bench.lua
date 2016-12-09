-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local S = require("syscall")
local lib = require("core.lib")
local json_lib = require("program.config.json")

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

local function read_reply(fd)
   local json = read_json_object(client)
   local output = buffered_output()
   write_json_object(output, json)
   output:flush_to_fd(1) -- stdout
end

local function read_commands(file)
   local fd = assert(S.open(file, "rdonly"))
   local input = json_lib.buffered_input_from_fd(fd:getfd())
   local ret = {}
   json_lib.skip_whitespace(input)
   while not input:eof() do
      table.insert(ret, json_lib.read_json_object(input))
      json_lib.skip_whitespace(input)
   end
   fd:close()
   return ret
end

function die(input)
   local chars = {}
   while input:peek() do
      table.insert(chars, input:peek())
      input:discard()
   end
   local str = table.concat(chars)
   io.stderr:write("Error detected reading response:\n"..str)
   main.exit(1)
end

function run(args)
   listen_params, file = parse_command_line(args)
   local commands = read_commands(file)
   local ok, err, input_read, input_write = assert(S.pipe())
   local ok, err, output_read, output_write = assert(S.pipe())
   local pid = S.fork()
   if pid == 0 then
      local argv = {"snabb", "config", "listen"}
      if listen_params.schema_name then
         table.insert(argv, "-s")
         table.insert(argv, listen_params.schema_name)
      end
      if listen_params.revision_date then
         table.insert(argv, "-r")
         table.insert(argv, listen_params.revision_date)
      end
      table.insert(argv, listen_params.instance_id)
      S.prctl("set_pdeathsig", "hup")
      input_write:close()
      output_read:close()
      assert(S.dup2(input_read, 0))
      assert(S.dup2(output_write, 1))
      S.execve(("/proc/%d/exe"):format(S.getpid()), argv, {})
   end
   input_read:close()
   output_write:close()

   local input = json_lib.buffered_input_from_fd(output_read:getfd())
   local start = engine.now()
   for _,json in ipairs(commands) do
      local out = json_lib.buffered_output()
      json_lib.write_json_object(out, json)
      out:flush_to_fd(input_write)
      json_lib.skip_whitespace(input)
      local ok, response = pcall(json_lib.read_json_object, input)
      if ok then
         io.stdout:write(".")
         io.stdout:flush()
      else
         die(input)
      end
   end
   local elapsed = engine.now() - start
   io.stdout:write("\n")
   print(string.format("Issued %s commands in %.2f seconds (%.2f commands/s)",
                       #commands, elapsed, #commands/elapsed))
   main.exit(0)
end
