-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local S = require("syscall")
local lib = require("core.lib")
local shm = require("core.shm")

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

local function compute_snabb_instances()
   -- Produces set of snabb instances, excluding this one.
   local pids = {}
   local my_pid = S.getpid()
   for _, name in ipairs(shm.children("/")) do
      -- This could fail as the name could be for example "by-name"
      local p = tonumber(name)
      if p and p ~= my_pid then table.insert(pids, p) end
   end
   return pids
end

function run (args)
   parse_args (args)
   local instances = compute_snabb_instances()
   for _, instance in ipairs(instances) do print(instance) end
   main.exit(0)
end
