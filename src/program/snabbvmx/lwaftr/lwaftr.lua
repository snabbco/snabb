module(..., package.seeall)

local S = require("syscall")
local config = require("core.config")
local lib = require("core.lib")
local lwtypes = require("apps.lwaftr.lwtypes")
local setup = require("program.snabbvmx.lwaftr.setup")
local shm = require("core.shm")

local function show_usage (exit_code)
   print(require("program.snabbvmx.lwaftr.README_inc"))
   main.exit(exit_code)
end

local function fatal (msg)
   print(msg)
   main.exit(1)
end

local function file_exists (path)
   local stat = S.stat(path)
   return stat and stat.isreg
end

local function set_ring_buffer_size(ring_buffer_size)
   print(("Ring buffer size set to %d"):format(ring_buffer_size))
   require('apps.intel.intel10g').num_descriptors = ring_buffer_size
end

function parse_args (args)
   if #args == 0 then show_usage(1) end
   local conf_file, id, pci, mac, sock_path, mirror_id
   local opts = { verbosity = 0 }
   local handlers = {}
   function handlers.v () opts.verbosity = opts.verbosity + 1 end
   function handlers.D (arg)
      opts.duration = assert(tonumber(arg), "Duration must be a number")
   end
   function handlers.c(arg)
      conf_file = arg
      if not arg then
         fatal("Argument '--conf' was not set")
      end
      if not file_exists(conf_file) then
         print(("Warning: config file %s not found"):format(conf_file))
      end
   end
   function handlers.i(arg)
      id = arg
      if not arg then
         fatal("Argument '--id' was not set")
      end
   end
   function handlers.p(arg)
      pci = arg
      if not arg then
         fatal("Argument '--pci' was not set")
      end
   end
   function handlers.m(arg)
      mac = arg
      if not arg then
         fatal("Argument '--mac' was not set")
      end
   end
   function handlers.s(arg)
      sock_path = arg
      if not arg then
         fatal("Argument '--sock' was not set")
      end
   end
   function handlers.mirror (arg)
      mirror_id = arg
   end
   function handlers.h() show_usage(0) end
   lib.dogetopt(args, handlers, "c:s:i:p:m:vD:h", {
      ["conf"] = "c", ["sock"] = "s", ["id"] = "i", ["pci"] = "p", ["mac"] = "m",
      ["mirror"] = 1, verbose = "v", duration = "D", help = "h" })
   return opts, conf_file, id, pci, mac, sock_path, mirror_id
end

function run(args)
   local opts, conf_file, id, pci, mac, sock_path, mirror_id = parse_args(args)

   local conf = {}
   local lwconf = {}
   local ring_buffer_size = 2048
   local discard_threshold = 100000
   local discard_check_timer = 1
   local discard_wait = 20

   if file_exists(conf_file) then
      conf = lib.load_conf(conf_file)
      if not file_exists(conf.lwaftr) then
         fatal(("lwAFTR conf file '%s' not found"):format(conf.lwaftr))
      end
      lwconf = require('apps.lwaftr.conf').load_lwaftr_config(conf.lwaftr)
      lwconf.ipv6_mtu = lwconf.ipv6_mtu or 1500
      lwconf.ipv4_mtu = lwconf.ipv4_mtu or 1460
   else
      print(("Interface '%s' set to passthru mode"):format(id))
      ring_buffer_size = 1024
      conf.settings = {}
   end

   if conf.settings then
      if conf.settings.discard_threshold then
         discard_threshold = conf.settings.discard_threshold
      end
      if conf.settings.discard_check_timer then
         discard_check_timer = conf.settings.discard_check_timer
      end
      if conf.settings.discard_wait then
         discard_wait = conf.settings.discard_wait
      end
      if conf.settings.ring_buffer_size then
         ring_buffer_size = tonumber(conf.settings.ring_buffer_size)
         if not ring_buffer_size then
            fatal("Bad ring size: " .. conf.settings.ring_buffer_size)
         end
         if ring_buffer_size > 32*1024 then
            fatal("Ring size too large for hardware: " .. ring_buffer_size)
         end
         if math.log(ring_buffer_size)/math.log(2) % 1 ~= 0 then
            fatal("Ring size is not a power of two: " .. ring_buffer_size)
         end
      end
   end

   set_ring_buffer_size(ring_buffer_size)

   local mtu = lwconf.ipv6_mtu
   if mtu < lwconf.ipv4_mtu then
      mtu = lwconf.ipv4_mtu
   end

   if id then
      local lwaftr_id = shm.create("nic/id", lwtypes.lwaftr_id_type)
      lwaftr_id.value = id
   end

   local vlan = conf.settings.vlan

   conf.interface = { 
      mac_address = mac,
      pci = pci, 
      id = id, 
      mtu = mtu,
      vlan = vlan,
      mirror_id = mirror_id,
      discard_threshold = discard_threshold,
      discard_wait = discard_wait,
      discard_check_timer = discard_check_timer,
   }

   local c = config.new()
   setup.lwaftr_app(c, conf, lwconf, sock_path)
   engine.configure(c)

   if opts.verbosity >= 2 then
      local function lnicui_info()
         engine.report_apps()
      end
      local t = timer.new("report", lnicui_info, 1e9, 'repeating')
      timer.activate(t)
   end

   engine.busywait = true
   if opts.duration then
      engine.main({duration=opts.duration, report={showlinks=true}})
   else
      engine.main({report={showlinks=true}})
   end
end
