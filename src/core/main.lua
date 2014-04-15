module(...,package.seeall)

local ffi = require("ffi")
local C   = ffi.C

require("lib.lua.strict")
require("lib.lua.class")

ffi.cdef[[
      extern int argc;
      extern char** argv;
]]

local usage = [[
Usage: snabbswitch [options] <module> [args...]
Available options are:
-e chunk     Execute string 'chunk'.
-l name      Require library 'name'.
-t name      Test module 'name' with selftest().
-d           Debug unhandled errors with the Lua interactive debugger.
-jdump file  Trace JIT decisions to 'file'. (Requires LuaJIT jit.* library.)
-jp          Profile with the LuaJIT statistical profiler.
-jp=args[,.output]
]]

local debug_on_error = false
local profiling = false

-- List of parameters passed on the command line.
parameters = {}

function main ()
   require "lib.lua.strict"
   initialize()
   local args = command_line_args()
   if #args == 0 then
      print(usage)
      os.exit(1)
   end
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
      elseif (args[i]):match("-jp") then
	 local pargs, poutput = (args[i]):gmatch("-jp=(%w*),?(.*)")()
	 if poutput == '' then poutput = nil end
	 require("jit.p").start(pargs, poutput)
	 profiling = true
	 i = i + 1
      elseif args[i] == '-jdump' and i < #args then
	 local jit_dump = require "jit.dump"
	 jit_dump.start("", args[i+1])
	 i = i + 2
      elseif i <= #args then
         -- Syntax: <module> [args...]
         local module = args[i]
         i = i + 1
         while i <= #args do
            table.insert(parameters, args[i])
            i = i + 1
         end
         require(module)
         exit(0)
      else
	 print(usage)
	 os.exit(1)
      end
   end
   exit(0)
end

function exit (status)
   if profiling then require("jit.p").stop() end
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

