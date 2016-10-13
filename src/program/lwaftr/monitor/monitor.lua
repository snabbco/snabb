module(..., package.seeall)

local ffi = require("ffi")
local ipv4 = require("lib.protocol.ipv4")
local lib = require("core.lib")
local lwutil = require("apps.lwaftr.lwutil")
local shm = require("core.shm")

local fatal, file_exists = lwutil.fatal, lwutil.file_exists
local uint32_ptr_t = ffi.typeof('uint32_t*')

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
   if #args == 1 then
      local maybe_pid = tonumber(args[1])
      if maybe_pid then
         return MIRROR_NOTHING, maybe_pid
      end
      return args[1]
   end
   return args[1], args[2]
end

local function ipv4_to_num (addr)
   local arr = ipv4:pton(addr)
   return arr[3] * 2^24 + arr[2] * 2^16 + arr[1] * 2^8 + arr[0]
end

local function find_lwaftr_process (pid)
   -- Check process has v4v6_mirror defined.
   if pid then
      pid = assert(tonumber(pid), ("Incorrect PID value: '%s'"):format(pid))
      local v4v6_mirror = "/"..pid.."/v4v6_mirror"
      if not file_exists(shm.root..v4v6_mirror) then
         fatal(("lwAFTR process '%d' is not running in mirroring mode"):format(pid))
      end
      return v4v6_mirror
   end

   -- Return first process which has v4v6_mirror defined.
   for _, pid in ipairs(shm.children("/")) do
      pid = tonumber(pid)
      if pid then
         local v4v6_mirror = "/"..pid.."/v4v6_mirror"
         if file_exists(shm.root..v4v6_mirror) then
            return v4v6_mirror
         end
      end
   end
end

function run (args)
   local action, pid = parse_args(args)
   local path = find_lwaftr_process(pid)
   if not path then
      fatal("Couldn't find lwAFTR process running in mirroring mode")
   end

   local ipv4_address
   if action == "none" then
      print("Monitor none")
      ipv4_address = MIRROR_NOTHING
   elseif action == "all" then
      print("Monitor all")
      ipv4_address = MIRROR_EVERYTHING
   else
      assert(ipv4:pton(action),
            ("Invalid action or incorrect IPv4 address: '%s'"):format(action))
      ipv4_address = action
      print(("Mirror address set to '%s'"):format(ipv4_address))
   end

   local ipv4_num = ipv4_to_num(ipv4_address)
   local v4v6_mirror = shm.open(path, "struct { uint32_t ipv4; }")
   v4v6_mirror.ipv4 = ipv4_num
   shm.unmap(v4v6_mirror)
end
