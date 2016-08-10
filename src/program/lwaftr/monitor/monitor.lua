module(..., package.seeall)

local S = require("syscall")
local ffi = require("ffi")
local ipv4 = require("lib.protocol.ipv4")
local lib = require("core.lib")
local shm = require("core.shm")

local uint32_ptr_t = ffi.typeof('uint32_t*')

local long_opts = {
   help = "h"
}

local DEFAULT_IPV4 = "0.0.0.0"

local function fatal (msg)
   print(msg)
   main.exit(1)
end

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
   if #args > 2 then usage(1) end
   if #args == 0 then
      return DEFAULT_IPV4
   end
   if #args == 1 then
      local maybe_pid = tonumber(args[1])
      if maybe_pid then
         return DEFAULT_IPV4, maybe_pid
      end
      return args[1]
   end
   return args[1], args[2]
end

local function ipv4_to_num (addr)
   local arr = ipv4:pton(addr)
   return arr[3] * 2^24 + arr[2] * 2^16 + arr[1] * 2^8 + arr[0]
end

-- TODO: Refactor to a common library.
local function file_exists(path)
   local stat = S.stat(path)
   return stat and stat.isreg
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
   local ipv4_address, pid = parse_args(args)
   local path = find_lwaftr_process(pid)
   if not path then
      fatal("Couldn't find lwAFTR process running in mirroring mode")
   end

   local ipv4_num = ipv4_to_num(ipv4_address)
   local v4v6_mirror = shm.open(path, "struct { uint32_t ipv4; }")
   v4v6_mirror.ipv4 = ipv4_num
   shm.unmap(v4v6_mirror)

   if ipv4_address == DEFAULT_IPV4 then
      print("Monitor off")
   else
      print(("Mirror address set to '%s'"):format(ipv4_address))
   end
end
