module(..., package.seeall)

local getopt = require("lib.lua.alt_getopt")

local usage = [[
Usage: snsh [OPTION]... [SCRIPT] [PARAMETER]...

Snabb Shell: Load the Snabb Switch core and execute Lua source code.

Execute SCRIPT if specified and then exit.

  -i,        --interactive   Start an interactive Read-Eval-Print Loop.
  -e EXPR,   --eval EXPR     Evaluate the Lua expression EXPR.
  -l MODULE, --load MODULE   Load (require) the Lua module MODULE.
  -t MODULE, --test MODULE   Test (selftest) the Lua module MODULE.
  -d,        --debug         Enable additional debugging checks.
  -j CMD,    --jit CMD       Control LuaJIT behavior. Available commands:
                               -jv=FILE, --jit v=FILE
                                 Write verbose JIT trace output to FILE.
                               -jdump=OPTS[,FILE] --jit dump=OPTS[,FILE]
                                 Output JIT traces, optionally to a file.
                               -jp=OPTS[,FILE] --jit p=OPTS[,FILE]
                                 Profile execution with low-overhead sampling.
                             See luajit documentation for more information:
                               http://luajit.org/running.html
  -P PATH,   --package-path PATH
                             Use PATH as the Lua 'package.path'.
  -h,        --help          Print this usage message.
]]

local long_opts = {
   ["package-path"] = "P",
   eval = "e",
   load = "l",
   test = "t",
   interactive = "i",
   debug = "d",
   jv = "v",
   help = "h",
}

function run (parameters)
   local start_repl = false
   local noop = true -- are we doing nothing?
   -- Table of functions implementing command-line arguments
   local opt = {}
   function opt.h (arg) print(usage) main.exit(0)            end
   function opt.l (arg) require(arg)            noop = false end
   function opt.t (arg) require(arg).selftest() noop = false end
   function opt.d (arg) _G.developer_debug = true            end
   function opt.i (arg) start_repl = true       noop = false end
   function opt.e (arg)
      local thunk, error = loadstring(arg)
      if thunk then thunk() else print(error) end
      noop = false
   end

   -- Execute command line arguments
   local opts,optind,optarg = getopt.get_ordered_opts(parameters, "hl:t:die:", long_opts)
   for i,v in ipairs(opts) do
      opt[v](optarg[i])
   end

   -- Drop arguments that are alraedy processed.
   for i = 1, optind-1 do table.remove(parameters, 1) end

   if #parameters > 0 then
      run_script(parameters)
   elseif noop then
      print(usage) 
      main.exit(1)
   end
   
   if start_repl then repl() end
end

function run_script (parameters)
   local command = table.remove(parameters, 1)
   main.parameters = parameters -- make remaining args available to script
   local r, error = pcall(dofile, command)
   if not r then
      print(error)
      main.exit(1)
   end
end

-- This is a simple REPL similar to LuaJIT's built-in REPL. It can only
-- read single-line statements but does support the `=<expr>' syntax.
function repl ()
   local line = nil
   local function eval_line ()
      if line:sub(0,1) == "=" then
         -- Evaluate line as expression.
         print(loadstring("return "..line:sub(2))())
      else
         -- Evaluate line as statement
         local load = loadstring(line)
         if load then load() end
      end
   end
   repeat
      io.stdout:write("Snabb> ")
      io.stdout:flush()
      line = io.stdin:read("*l")
      if line then
         local status, err = pcall(eval_line)
         if not status then
            io.stdout:write(("Error in %s\n"):format(err))
         end
         io.stdout:flush()
      end
   until not line
end


