module(..., package.seeall)

local ffi = require("ffi")
local ipv4 = require("lib.protocol.ipv4")
local lib = require("core.lib")
local lwtypes = require("apps.lwaftr.lwtypes")
local lwutil = require("apps.lwaftr.lwutil")
local shm = require("core.shm")

local fatal = lwutil.fatal

local long_opts = {
   help = "h"
}

local MIRROR_NOTHING = "0.0.0.0"
local MIRROR_EVERYTHING = "255.255.255.255"

local function usage (code)
   print(require("program.lwaftr.monitor.README_inc"))
   main.exit(code)
end

local function parse_args (args)
   local handlers = {}
   function handlers.h ()
      usage(0)
   end
   args = lib.dogetopt(args, handlers, "h", long_opts)
   if #args < 1 or #args > 2 then usage(1) end

   -- Return address and pid.
   if #args == 1 then
      local maybe_pid = tonumber(args[1])
      if maybe_pid then
         return MIRROR_NOTHING, maybe_pid
      end
      return args[1]
   end
   return args[1], args[2]
end

local function find_pid_by_id (id)
   for _, pid in ipairs(shm.children("/")) do
      local path = "/"..pid.."/nic/id"
      if shm.exists(path) then
         local lwaftr_id = shm.open(path, lwtypes.lwaftr_id_type)
         if ffi.string(lwaftr_id.value) == id then
            return pid
         end
      end
   end
end

local function find_mirror_path (pid)
   -- Check process has v4v6_mirror defined.
   if pid then
      -- Pid is an id.
      if not tonumber(pid) then
         pid = find_pid_by_id(pid)
         if not pid then
            fatal("Invalid lwAFTR id '%s'"):format(pid)
         end
      end
      -- Pid exists?
      if not shm.exists("/"..pid) then
         fatal(("No Snabb instance with pid '%d'"):format(pid))
      end
      -- Check process has v4v6_mirror defined.
      local path = "/"..pid.."/v4v6_mirror"
      if not shm.exists(path) then
         fatal(("lwAFTR process '%d' is not running in mirroring mode"):format(pid))
      end
      return path, pid
   end

   -- Return first process which has v4v6_mirror defined.
   for _, pid in ipairs(shm.children("/")) do
      local path = "/"..pid.."/v4v6_mirror"
      if shm.exists(path) then
         return path, pid
      end
   end
end

local function set_mirror_address (address, path)
   local function ipv4_to_num (addr)
      local arr = ipv4:pton(addr)
      return arr[3] * 2^24 + arr[2] * 2^16 + arr[1] * 2^8 + arr[0]
   end

   -- Validate address.
   if address == "none" then
      print("Monitor none")
      address = MIRROR_NOTHING
   elseif address == "all" then
      print("Monitor all")
      address = MIRROR_EVERYTHING
   else
      if not ipv4:pton(address) then
         fatal(("Invalid action or incorrect IPv4 address: '%s'"):format(address))
      end
   end

   -- Set v4v6_mirror.
   local ipv4_num = ipv4_to_num(address)
   local v4v6_mirror = shm.open(path, "struct { uint32_t ipv4; }")
   v4v6_mirror.ipv4 = ipv4_num
   shm.unmap(v4v6_mirror)
end

function run (args)
   local address, pid = parse_args(args)
   local path, pid_number = find_mirror_path(pid)
   if not path then
      fatal("Couldn't find lwAFTR process running in mirroring mode")
   end

   set_mirror_address(address, path)
   io.write(("Mirror address set to '%s'"):format(address))
   if not tonumber(pid) then
      io.write((" in PID '%d'"):format(pid_number))
   end
   io.write("\n")
end
