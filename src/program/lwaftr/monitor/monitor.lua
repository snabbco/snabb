module(..., package.seeall)

local ffi = require("ffi")
local ipv4 = require("lib.protocol.ipv4")
local lib = require("core.lib")
local lwutil = require("apps.lwaftr.lwutil")
local shm = require("core.shm")
local engine = require("core.app")

local fatal = lwutil.fatal

local long_opts = {
   help = "h",
   name = "n",
}

local MIRROR_NOTHING = "0.0.0.0"
local MIRROR_EVERYTHING = "255.255.255.255"

local function usage (code)
   print(require("program.lwaftr.monitor.README_inc"))
   main.exit(code)
end

local function parse_args (args)
   local handlers = {}
   local opts = {}
   function handlers.h ()
      usage(0)
   end
   function handlers.n (arg)
      opts.name = assert(arg)
   end
   args = lib.dogetopt(args, handlers, "hn:", long_opts)
   if #args < 1 or #args > 2 then usage(1) end
   return opts, unpack(args)
end

local function find_mirror_path (pid)
   local path = "/"..pid.."/v4v6_mirror"
   if not shm.exists(path) then
      fatal(("lwAFTR process '%d' is not running in mirroring mode"):format(pid))
   end
   return path
end

local function set_mirror_address (address, path)
   local function ipv4_to_num (addr)
      local arr = ipv4:pton(addr)
      return arr[3] * 2^24 + arr[2] * 2^16 + arr[1] * 2^8 + arr[0]
   end

   -- Validate address.
   if address == "none" then
      address = MIRROR_NOTHING
   elseif address == "all" then
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

   return address
end

function run (args)
   local opts, address, pid = parse_args(args)
   if opts.name then
      local programs = engine.enumerate_named_programs(opts.name)
      pid = programs[opts.name]
      if not pid then
         fatal(("Couldn't find process with name '%s'"):format(opts.name))
      end
   end
   if not lwutil.dir_exists(shm.root..'/'..pid) then
      fatal("No such Snabb instance: "..pid)
   end
   local path = find_mirror_path(pid)
   address = set_mirror_address(address, path)
   print(("Mirror address set to '%s' in PID '%s'"):format(address, pid))
end
