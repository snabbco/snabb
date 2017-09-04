-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local S = require("syscall")
local lib = require("core.lib")
local shm = require("core.shm")
local app = require("core.app")

local basename, dirname = lib.basename, lib.dirname

local function usage (code)
   local f = code == 0 and io.stdout or io.stderr
   f:write(require("program.ps.README_inc"))
   main.exit(code)
end

local function parse_args (args)
   local opt = {}
   function opt.h (arg) usage(0) end
   args = lib.dogetopt(args, opt, "h", {help='h'})
   if #args ~= 0 then usage(1) end
end

function appname_resolver()
    local instances = {}
    for name, pid in pairs(app.enumerate_named_programs()) do
        instances[pid] = name
    end
    return function (pid) return instances[pid] end
end

function is_worker (pid)
   return shm.exists("/"..pid.."/group")
end

local function is_addressable (pid)
   local socket = assert(S.socket("unix", "stream"))
   local tail = pid.."/config-leader-socket"
   local by_name = S.t.sockaddr_un(shm.root..'/by-name/'..tail)
   local by_pid = S.t.sockaddr_un(shm.root..'/'..tail)
   if socket:connect(by_name) or socket:connect(by_pid) then
      socket:close()
      return true
   end
   return false
end

function get_leader_pid (pid)
   local fq = shm.root.."/"..pid.."/group"
   local path = S.readlink(fq)
   return basename(dirname(path))
end

local function compute_snabb_instances()
   -- Produces set of snabb instances, excluding this one.
   local whichname = appname_resolver()
   local pids = {}
   local my_pid = S.getpid()
   for _, name in ipairs(shm.children("/")) do
      -- This could fail as the name could be for example "by-name"
      local p = tonumber(name)
      local name = whichname(p)
      if p and p ~= my_pid then
         local instance = {pid=p, name=name}
         if is_worker(p) then
            instance.leader = get_leader_pid(p)
         end
         if is_addressable(p) then
            instance.addressable = true
         end
         table.insert(pids, instance)
      end
   end
   table.sort(pids, function(a, b)
      return tonumber(a.pid) < tonumber(b.pid)
   end)
   return pids
end

function run (args)
   parse_args(args)
   local instances = compute_snabb_instances()
   for _, instance in ipairs(instances) do
      -- Check instance is a worker.
      if instance.leader then
         io.write("  \\- "..instance.pid.."   worker for "..instance.leader)
      else
         io.write(instance.pid)
         if instance.name then
            io.write("\t["..instance.name.."]")
         end
      end
      if instance.addressable then
         io.write(" *")
      end
      io.write("\n")
   end
   main.exit(0)
end
