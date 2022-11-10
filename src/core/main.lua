-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

-- Default to not using any Lua code on the filesystem.
-- (Can be overridden with -P argument: see below.)
package.path = ''

local STP = require("lib.lua.StackTracePlus")
local ffi = require("ffi")
local jit = require("jit")
local lib = require("core.lib")
local shm = require("core.shm")
local C   = ffi.C
-- Load ljsyscall early to help detect conflicts
-- (e.g. FFI type name conflict between Snabb and ljsyscall)
local S = require("syscall")

require("lib.lua.strict")
require("lib.lua.class")

-- ljsyscall returns error as a cdata instead of a string, and the standard
-- assert doesn't use tostring on it.
_G.assert = function (v, ...)
   if v then return v, ... end
   error(tostring(... or "assertion failed!"))
end

-- Reserve names that we want to use for global module.
-- (This way we avoid errors from the 'strict' module.)
_G.config, _G.engine, _G.memory, _G.link, _G.packet, _G.timer,
   _G.main = nil

ffi.cdef[[
      extern int argc;
      extern char** argv;
]]

-- Enable developer-level debug if SNABB_DEBUG env variable is set.
_G.developer_debug = lib.getenv("SNABB_DEBUG") ~= nil
debug_on_error = _G.developer_debug

function main ()
   require "lib.lua.strict"
   -- Warn on unsupported platforms
   if ffi.arch ~= 'x64' or ffi.os ~= 'Linux' then
      error("fatal: "..ffi.os.."/"..ffi.arch.." is not a supported platform\n")
   end
   initialize()
   -- Setup audit.log, vmprofile
   engine.enable_auditlog()
   engine.setvmprofile("program")
   jit.vmprofile.start()
   if lib.getenv("SNABB_PROGRAM_LUACODE") then
      -- Run the given Lua code instead of the command-line
      local expr = lib.getenv("SNABB_PROGRAM_LUACODE")
      local f = loadstring(expr)
      if f == nil then
         error(("Failed to load $SNABB_PROGRAM_LUACODE: %q"):format(expr))
      else
         f()
      end
   else
      -- Choose a program based on the command line
      local program, args = select_program(parse_command_line())
      if not lib.have_module(modulename(program)) then
         print("unsupported program: "..program:gsub("_", "-"))
         usage(1)
      else
         require(modulename(program)).run(args)
      end
   end
   jit.vmprofile.stop()
end

-- Take the program name from the first argument, unless the first
-- argument is "snabb", in which case pop it off, handle any options
-- passed to snabb itself, and use the next argument.
function select_program (args)
   local program = programname(table.remove(args, 1))
   if program == 'snabb' then
      while #args > 0 and args[1]:match('^-') do
         local opt = table.remove(args, 1)
         if opt == '-h' or opt == '--help' then
            usage(0)
         elseif opt == '-v' or opt == '--version' then
            version()
            os.exit(0)
         else
            print("unrecognized option: "..opt)
            usage(1)
         end
      end
      if #args == 0 then usage(1) end
      program = programname(table.remove(args, 1))
   end
   return program, args
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

function version ()
   local v = require('core.version')
   local version_str = v.version
   if v.extra_version ~= '' then
      version_str = version_str.." ("..v.extra_version..")"
   end
   print(ffi.string(C.basename(C.argv[0])).." "..version_str)
   print([[
Copyright (C) 2012-2017 Snabb authors; see revision control logs for details.
License: <https://www.apache.org/licenses/LICENSE-2.0>

Snabb is open source software.  For more information on Snabb, see
https://github.com/snabbco/snabb.]])
end

function programname (name)
   return name:gsub("^.*/", "")
              :gsub("-[0-9.]+[-%w]+$", "")
              :gsub("-", "_")
              :gsub("^snabb_", "")
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
   lib.randomseed(tonumber(lib.getenv("SNABB_RANDOM_SEED")))
   -- Global API
   _G.config = require("core.config")
   _G.engine = require("core.app")
   _G.memory = require("core.memory")
   _G.link   = require("core.link")
   _G.packet = require("core.packet"); _G.packet.initialize()
   _G.timer  = require("core.timer")
   _G.main   = getfenv()
end

function handler (reason)
   local ok, bt = pcall(STP.stacktrace)
   if ok and bt then
      io.stderr:write(reason)
      io.stderr:write("\n")
      io.stderr:write(bt)
      io.stderr:write("\n")
   else
      io.stderr:write(debug.traceback(reason))
      io.stderr:write("\n")
   end
   if debug_on_error then debug.debug() end
   os.exit(1)
end

-- Cleanup after Snabb process.
function shutdown (pid)
   -- simple pcall helper to print error and continue
   local function safely (f)
      local ok, err = pcall(f)
      if not ok then print(err) end
   end
   -- Run cleanup hooks
   safely(function () require("core.packet").shutdown(pid) end)
   safely(function () require("apps.interlink.receiver").shutdown(pid) end)
   safely(function () require("apps.interlink.transmitter").shutdown(pid) end)
   safely(function () require("apps.mellanox.connectx").shutdown(pid) end)
   -- Parent process performs additional cleanup steps.
   -- (Parent is the process whose 'group' folder is not a symlink.)

   -- Restore non-blocking flags on file descriptions, as these are
   -- shared with the parent.
   S.stdin:block(); S.stdout:block(); S.stderr:block()
   local st, err = S.lstat(shm.root.."/"..pid.."/group")
   local is_parent = st and st.isdir
   if is_parent then
      safely(function () require("lib.hardware.pci").shutdown(pid) end)
      safely(function () require("core.memory").shutdown(pid) end)
   end
   -- Free shared memory objects
   if not _G.developer_debug and not lib.getenv("SNABB_SHM_KEEP") then
      -- Try cleaning up symlinks for named apps, if none exist, fail silently.
      local backlink = shm.root.."/"..pid.."/name"
      local name_link = S.readlink(backlink)
      S.unlink(name_link)
      S.unlink(backlink)

      shm.unlink("/"..pid)
   end
end

function selftest ()
   print("selftest")
   assert(programname("/bin/snabb-1.0") == "snabb",
      "Incorrect program name parsing")
   assert(programname("/bin/snabb-1.0-alpha2") == "snabb",
      "Incorrect program name parsing")
   assert(programname("/bin/snabb-nfv") == "nfv",
      "Incorrect program name parsing")
   assert(programname("/bin/nfv-1.0") == "nfv",
      "Incorrect program name parsing")
   assert(modulename("nfv-sync-master-2.0") == "program.nfv_sync_master.nfv_sync_master",
      "Incorrect module name parsing")
   local pn = programname
   -- snabb foo => foo
   assert(select_program({ 'foo' }) == "foo",
      "Incorrect program name selected")
   -- snabb-foo => foo
   assert(select_program({ 'snabb-foo' }) == "foo",
      "Incorrect program name selected")
   -- snabb snabb-foo => foo
   assert(select_program({ 'snabb', 'snabb-foo' }) == "foo",
      "Incorrect program name selected")
end

-- Fork a child process that monitors us and performs cleanup actions
-- when we terminate.
local snabbpid = S.getpid()
local lockfile = os.tmpname()
local lock = S.open(lockfile, "wronly")
S.unlink(lockfile)
S.sigprocmask("block", "hup, int, quit, term")
lock:lockf("lock", 0)
if assert(S.fork()) ~= 0 then
   -- Parent process; run Snabb.
   S.sigprocmask("unblock", "hup, int, quit, term")
   xpcall(main, handler)
   -- Lock will be released however the process exits.
else
   -- Child process: Supervise parent & perform cleanup.  Lock not
   -- inherited from parent.
   S.prctl("set_name", "[snabb sup]")
   -- Wait for parent to release lock.
   lock:lockf("lock", 0)
   -- Finally, clean up after parent process.
   shutdown(snabbpid)
   os.exit(128)
end
