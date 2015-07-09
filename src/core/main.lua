module(...,package.seeall)

-- Default to not using any Lua code on the filesystem.
-- (Can be overridden with -P argument: see below.)
package.path = ''

local STP = require("lib.lua.StackTracePlus")
local ffi = require("ffi")
local zone = require("jit.zone")
local lib = require("core.lib")
local C   = ffi.C
-- Load ljsyscall early to help detect conflicts
-- (e.g. FFI type name conflict between Snabb and ljsyscall)
require("syscall")

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

_G.developer_debug = false
debug_on_error = false

function main ()
   zone("startup")
   require "lib.lua.strict"
   initialize()
   local program
   local args = parse_command_line()
   if programname(args[1]) == 'snabb' then
      -- Print usage when no arguments or -h/--help
      if #args == 1 or args[2] == '-h' or args[2] == '--help' then
         usage()
         os.exit(1)
      else
         -- Strip 'snabb' and use next argument as program name
         table.remove(args, 1)
      end
   end
   local program = table.remove(args, 1)
   if not lib.have_module(modulename(program)) then
      print("unsupported program: "..programname(program))
      print()
      print("Rename this executable (cp, mv, ln) to choose a supported program:")
      print("  snabb "..(require("program.programs_inc"):gsub("\n", " ")))
      os.exit(1)
   else
      require(modulename(program)).run(args)
   end
end

function usage ()
   print("Usage: "..ffi.string(C.argv[0]).." <program> ...")
   local programs = require("program.programs_inc"):gsub("%S+", "  %1")
   print()
   print("This snabb executable has the following programs built in:")
   print(programs)
   print("For detailed usage of any program run:")
   print("  snabb <program> --help")
   print()
   print("If you rename (or copy or symlink) this executable with one of")
   print("the names above then that program will be chosen automatically.")
end


-- programname("snabbnfv-1.0") => "snabbnfv"
function programname (program) 
   program = program:gsub("^.*/", "") -- /bin/snabb-1.0 => snabb-1.0
   program = program:gsub("[-.].*$", "") -- snabb-1.0   => snabb
   return program
end
-- modulename("nfv-sync-master.2.0") => "program.nfv.nfv_sync_master")
function modulename (program) 
   program = programname(program)
   return ("program.%s.%s"):format(program, program)
end

-- Return all command-line paramters (argv) in an array.
function parse_command_line ()
   local array = {}
   for i = 0, C.argc - 1 do 
      table.insert(array, ffi.string(C.argv[i]))
   end
   return array
end

function exit (status)
   os.exit(status)
end

--- Globally initialize some things. Module can depend on this being done.
function initialize ()
   require("core.lib")
   require("core.clib_h")
   require("core.lib_h")
   -- Global API
   _G.config = require("core.config")
   _G.engine = require("core.app")
   _G.memory = require("core.memory")
   _G.link   = require("core.link")
   _G.packet = require("core.packet")
   _G.timer  = require("core.timer")
   _G.main   = getfenv()
end

function handler (reason)
   print(reason)
   print(debug.traceback())
   if debug_on_error then debug.debug() end
   os.exit(1)
end

xpcall(main, handler)

