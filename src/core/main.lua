module(...,package.seeall)

-- Default to not using any Lua code on the filesystem.
-- (Can be overridden with -P argument: see below.)
package.path = ''

local STP = require("lib.lua.StackTracePlus")
local ffi = require("ffi")
local zone = require("jit.zone")
local C   = ffi.C

require("lib.lua.strict")
require("lib.lua.class")

-- Reserve names that we want to use for global module.
-- (This way we avoid errors from the 'strict' module.)
_G.config, _G.engine, _G.memory, _G.link, _G.packet, _G.timer,
   _G.main = nil

ffi.cdef[[
      extern int argc;
      extern char** argv;
]]

local usage = [[
Usage: snabb [options] <module> [args...]
Available options are:
-P pathspec  Set library load path (Lua 'package.path').
-e chunk     Execute string 'chunk'.
-l name      Require library 'name'.
-t name      Test module 'name' with selftest().
-R           Start interactive Snabb REPL.
-dm          Enable developer mode. Enables debug prints and asserts.
-d           Debug unhandled errors with the Lua interactive debugger.
-S           Print enhanced stack traces with more debug information.
-jdump file  Trace JIT decisions to 'file'. (Requires LuaJIT jit.* library.)
-jv file     Prints verbose information about the the JIT compiler to 'file'.
-jp          Profile with the LuaJIT statistical profiler.
-jp=args[,.output]
]]

_G.developer_debug = false
debug_on_error = false
profiling = false
start_repl = false

-- List of parameters passed on the command line.
parameters = {}

function main ()
   zone("startup")
   require "lib.lua.strict"
   initialize()
   local args = command_line_args()
   if #args == 0 then
      print(usage)
      os.exit(1)
   end
   local i = 1
   while i <= #args do
      if args[i] == '-P' and i < #args then
         package.path = args[i+1]
         i = i + 2
      elseif args[i] == '-l' and i < #args then
         require(args[i+1])
         i = i + 2
      elseif args[i] == '-t' and i < #args then
         zone("selftest")  require(args[i+1]).selftest()  zone()
         i = i + 2
      elseif args[i] == '-e' and i < #args then
         local thunk, error = loadstring(args[i+1])
         if thunk then thunk() else print(error) end
         i = i + 2
      elseif args[i] == '-dm' then
         _G.developer_debug = true
         i = i + 1
      elseif args[i] == '-d' then
         debug_on_error = true
         i = i + 1
      elseif args[i] == '-S' then
         debug.traceback = STP.stacktrace
         i = i + 1
      elseif (args[i]):match("-jp") then
         local pargs, poutput = (args[i]):gmatch("-jp=([^,]*),?(.*)")()
         if poutput == '' then poutput = nil end
         require("jit.p").start(pargs, poutput)
         profiling = true
         i = i + 1
      elseif args[i] == '-jdump' and i < #args then
         local jit_dump = require "jit.dump"
         jit_dump.start("", args[i+1])
         i = i + 2
      elseif args[i] == '-jv' and i < #args then
         local jit_verbose = require 'jit.v'
         jit_verbose.start(args[i+1])
         i = i + 2
      elseif args[i] == '-R' then
         start_repl = true
         i = i + 1
      elseif i <= #args then
         -- Syntax: <script> [args...]
         local module = args[i]
         i = i + 1
         while i <= #args do
            table.insert(parameters, args[i])
            i = i + 1
         end
         zone("module "..module)
         dofile(module)
         exit(0)
      else
         print(usage)
         os.exit(1)
      end
   end
   if start_repl then
      zone("REPL")
      repl()
   end
   exit(0)
end

function exit (status)
   if profiling then require("jit.p").stop() end
   os.exit(status)
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

--- Globally initialize some things. Module can depend on this being done.
function initialize ()
   require("core.lib")
   require("core.clib_h")
   require("core.lib_h")
   if C.geteuid() ~= 0 then
      print("error: snabb has to run as root.")
      os.exit(1)
   end
   -- Global API
   _G.config = require("core.config")
   _G.engine = require("core.app")
   _G.memory = require("core.memory")
   _G.link   = require("core.link")
   _G.packet = require("core.packet")
   _G.timer  = require("core.timer")
   _G.main   = getfenv()
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

