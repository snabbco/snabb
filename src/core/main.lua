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
   local args = parse_command_line()
   local program = programname(args[1])
   if program == 'snabb' then
      -- Print usage with exit status 0 if help requested
      if args[2] == '-h' or args[2] == '--help' then
         usage(0)
      end
      -- Print usage with exit status 1 if no arguments supplied
      if #args == 1 then
         usage(1)
      end
      -- Strip 'snabb' and use next argument as program name
      table.remove(args, 1)
   end
   program = select_program(program, args)
   if not lib.have_module(modulename(program)) then
      print("unsupported program: "..program:gsub("_", "-"))
      print()
      print("Rename this executable (cp, mv, ln) to choose a supported program:")
      print("  snabb "..(require("programs_inc"):gsub("\n", " ")))
      os.exit(1)
   else
      require(modulename(program)).run(args)
   end
end

-- If program stars with prefix 'snabb_' removes the prefix
-- If not, use the next argument as program name
function select_program (program, args)
   if program:match("^snabb_") then
      return program:gsub("^snabb_", "")
   end
   return programname(table.remove(args, 1)):gsub("^snabb_", "")
end

function usage (status)
   print("Usage: "..ffi.string(C.argv[0]).." <program> ...")
   local programs = require("programs_inc"):gsub("%S+", "  %1")
   print()
   print("This snabb executable has the following programs built in:")
   print(programs)
   print("For detailed usage of any program run:")
   print("  snabb <program> --help")
   print()
   print("If you rename (or copy or symlink) this executable with one of")
   print("the names above then that program will be chosen automatically.")
   os.exit(status)
end

function programname (name)
   return name:gsub("^.*/", "")
              :gsub("-[0-9.]+[-%w]+$", "")
              :gsub("-", "_")
end

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

function selftest ()
   print("selftest")
   assert(programname("/bin/snabb-1.0") == "snabb",
      "Incorrect program name parsing")
   assert(programname("/bin/snabb-1.0-alpha2") == "snabb",
      "Incorrect program name parsing")
   assert(programname("/bin/snabb-nfv") == "snabb_nfv",
      "Incorrect program name parsing")
   assert(programname("/bin/snabb-nfv-1.0") == "snabb_nfv",
      "Incorrect program name parsing")
   assert(modulename("nfv-sync-master-2.0") == "program.nfv_sync_master.nfv_sync_master",
      "Incorrect module name parsing")
   local pn = programname
   -- snabb foo => foo
   assert(select_program(pn'snabb', { pn'foo' }) == "foo",
      "Incorrect program name selected")
   -- snabb-foo => foo
   assert(select_program(pn'snabb-foo', { }) == "foo",
      "Incorrect program name selected")
   -- snabb snabb-foo => foo
   assert(select_program(pn'snabb', { pn'snabb-foo' }) == "foo",
      "Incorrect program name selected")
end

xpcall(main, handler)
