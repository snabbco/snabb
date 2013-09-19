module(...,package.seeall)

local ffi = require("ffi")
local C   = ffi.C

require("strict")

ffi.cdef[[
      extern int argc;
      extern char** argv;
]]

local usage = [[
Usage: snabbswitch [options]
Available options are:
-e chunk     Execute string 'chunk'.
-l name      Require library 'name'.
-t name      Test module 'name' with selftest().
-d           Debug unhandled errors with the Lua interactive debugger.
-jdump file  Trace JIT decisions to 'file'. (Requires LuaJIT jit.* library.)
]]

local debug_on_error = false

function main ()
   require "strict"
   initialize()
   local args = command_line_args()
   if #args == 0 then
      print("No arguments given (-h for help). Defaulting to: -l core.selftest")
      args = { '-l', 'core.selftest' }
   end
   local profiling = false
   local i = 1
   while i <= #args do
      if args[i] == '-l' and i < #args then
	 require(args[i+1])
	 i = i + 2
      elseif args[i] == '-t' and i < #args then
         require(args[i+1]).selftest()
         i = i + 2
      elseif args[i] == '-e' and i < #args then
	 local thunk, error = loadstring(args[i+1])
	 if thunk then thunk() else print(error) end
	 i = i + 2
      elseif args[i] == '-d' then
	 debug_on_error = true
	 i = i + 1
      elseif args[i] == '-p' then
         require("jit.tprof").start()
         profiling = true
         i = i + 1
      elseif args[i] == '-jdump' and i < #args then
	 local jit_dump = require "jit.dump"
	 jit_dump.start("", args[i+1])
	 i = i + 2
      else
	 print(usage)
	 os.exit(1)
      end
   end
   if profiling then require("jit.tprof").off() end
   os.exit(0)
end

--- Globally initialize some things. Module can depend on this being done.
function initialize ()
   require("core.lib")
   require("core.clib_h")
   require("core.lib_h")
end

function command_line_args()
   local args = {}
   for i = 1, C.argc - 1 do
      args[i] = ffi.string(C.argv[i])
   end
   return args
end

function handler (reason)
   print(reason)
   print(debug.traceback())
   if debug_on_error then debug.debug() end
   os.exit(1)
end

xpcall(main, handler)

