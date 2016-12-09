-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local S = require("syscall")
local lib = require("core.lib")
local ffi = require("ffi")
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
   output:flush(S.stdout)
end

local function read_commands(file)
   local fd = assert(S.open(file, "rdonly"))
   local input = json_lib.buffered_input(fd)
   json_lib.skip_whitespace(input)
   local ret = {}
   while not input:eof() do
      local json = json_lib.read_json_object(input)
      json_lib.skip_whitespace(input)
      local out = json_lib.buffered_output()
      json_lib.write_json_object(out, json)
      table.insert(ret, out:flush())
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

function full_write(fd, str)
   local ptr = ffi.cast("const char*", str)
   local written = 0
   while written < #str do
      local count = assert(fd:write(ptr + written, #str - written))
      written = written + count
   end
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
      input_read:close()
      output_write:close()
      S.execve(("/proc/%d/exe"):format(S.getpid()), argv, {})
   end
   input_read:close()
   output_write:close()

   local write_buffering = assert(input_write:fcntl(S.c.F.GETPIPE_SZ))

   local input = json_lib.buffered_input(output_read)
   local start = engine.now()
   local next_write, next_read = 1, 1
   local buffered_bytes = 0
   io.stdout:setvbuf("no")
   while next_read <= #commands do
      while next_write <= #commands do
         local str = commands[next_write]
         if buffered_bytes + #str > write_buffering then break end
         full_write(input_write, str)
         io.stdout:write("w")
         buffered_bytes = buffered_bytes + #str
         next_write = next_write + 1
      end
      while next_read < next_write do
         json_lib.skip_whitespace(input)
         local ok, response = pcall(json_lib.read_json_object, input)
         if ok then
            buffered_bytes = buffered_bytes - #commands[next_read]
            next_read = next_read + 1
            io.stdout:write("r")
         else
            die(input)
         end
      end
   end
   local elapsed = engine.now() - start
   io.stdout:write("\n")
   print(string.format("Issued %s commands in %.2f seconds (%.2f commands/s)",
                       #commands, elapsed, #commands/elapsed))
   main.exit(0)
end
