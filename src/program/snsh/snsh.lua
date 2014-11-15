module(..., package.seeall)

local lib = require("core.lib")
local usage = require("program.snsh.README_inc")

local long_opts = {
   ["package-path"] = "P",
   eval = "e",
   load = "l",
   test = "t",
   interactive = "i",
   debug = "d",
   jit = "j",
   help = "h",
   pflua = "p",
}

function run (parameters)
   local profiling = false
   local start_repl = false
   local noop = true -- are we doing nothing?
   -- Table of functions implementing command-line arguments
   local opt = {}
   function opt.h (arg) print(usage) main.exit(0)            end
   function opt.l (arg) require(arg)            noop = false end
   function opt.t (arg) require(arg).selftest() noop = false end
   function opt.d (arg) _G.developer_debug = true            end
   function opt.p (arg) 
      _G["pflua"] = {
         
      }
   end
   function opt.i (arg) start_repl = true       noop = false end
   function opt.j (arg)
      if arg:match("^v") then
	 local file = arg:match("^v=(.*)")
	 if file == '' then file = nil end
	 require("jit.v").start(file)
      elseif arg:match("^p") then 
	 local opts, file = arg:match("^p=([^,]*),?(.*)")
	 if file == '' then file = nil end
	 require("jit.p").start(opts, file)
	 profiling = true
      elseif arg:match("^dump") then
	 local opts, file = arg:match("^dump=([^,]*),?(.*)")
	 if file == '' then file = nil end
	 require("jit.dump").on(opts, file)
      end
   end
   function opt.e (arg)
      local thunk, error = loadstring(arg)
      if thunk then thunk() else print(error) end
      noop = false
   end
   function opt.P (arg)
      package.path = arg
   end

   -- Execute command line arguments
   parameters = lib.dogetopt(parameters, opt, "hl:t:die:j:P:p:", long_opts)

   if #parameters > 0 then
      run_script(parameters)
   elseif noop then
      print(usage) 
      main.exit(1)
   end
   
   if start_repl then repl() end
   if profiling then require("jit.p").stop() end
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


