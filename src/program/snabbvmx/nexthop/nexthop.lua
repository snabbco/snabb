module(..., package.seeall)

local S = require("syscall")
local ethernet = require("lib.protocol.ethernet")
local ffi = require("ffi")
local lib = require("core.lib")
local shm = require("core.shm")

local macaddress_t = ffi.typeof[[
struct { uint8_t ether[6]; }
]]

local long_opts = {
   help = "h"
}

local function usage (code)
   print(require("program.snabbvmx.nexthop.README_inc"))
   main.exit(code)
end

-- TODO: Refactor to a general common purpose library.
local function file_exists(path)
   local stat = S.stat(path)
   return stat and stat.isreg
end

local function parse_args (args)
   local handlers = {}
   function handlers.h (arg) usage(0) end
   return lib.dogetopt(args, handlers, "h", long_opts)
end

local function is_current_process (pid)
   return pid == S.getpid()
end

function run (args)
   parse_args(args)
   for _, pid in ipairs(shm.children("/")) do
      pid = tonumber(pid)
      if is_current_process(pid) then
         goto continue
      end
      
      -- Print IPv4 next_hop_mac if defined.
      local next_hop_mac_v4 = "/"..pid.."/next_hop_mac_v4"
      if file_exists(shm.root..next_hop_mac_v4) then
         local nh_v4 = shm.open(next_hop_mac_v4, macaddress_t, "readonly")
         print(("PID '%d': next_hop_mac for IPv4 is %s"):format(
            pid, ethernet:ntop(nh_v4.ether)))
         shm.unmap(nh_v4)
      end

      -- Print IPv6 next_hop_mac if defined.
      local next_hop_mac_v6 = "/"..pid.."/next_hop_mac_v6"
      if file_exists(shm.root..next_hop_mac_v6) then
         local nh_v6 = shm.open(next_hop_mac_v6, macaddress_t, "readonly")
         print(("PID '%d': next_hop_mac for IPv6 is %s"):format(
            pid, ethernet:ntop(nh_v6.ether)))
         shm.unmap(nh_v6)
      end

      ::continue::
   end
end
