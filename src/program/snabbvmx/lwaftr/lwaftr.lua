module(..., package.seeall)

local config = require("core.config")
local ingress_drop_monitor = require("lib.timers.ingress_drop_monitor")
local lib = require("core.lib")
local lwcounter = require("apps.lwaftr.lwcounter")
local lwtypes = require("apps.lwaftr.lwtypes")
local lwutil = require("apps.lwaftr.lwutil")
local setup = require("program.snabbvmx.lwaftr.setup")
local shm = require("core.shm")

local fatal, file_exists = lwutil.fatal, lwutil.file_exists

local DEFAULT_MTU = 9500

local function show_usage (exit_code)
   print(require("program.snabbvmx.lwaftr.README_inc"))
   main.exit(exit_code)
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

   local ingress_drop_action = "flush"
   local ingress_drop_threshold = 100000
   local ingress_drop_interval = 1e6
   local ingress_drop_wait = 20

   if file_exists(conf_file) then
      conf = lib.load_conf(conf_file)
      if not file_exists(conf.lwaftr) then
         -- Search in main config file.
         conf.lwaftr = lib.dirname(conf_file).."/"..conf.lwaftr
      end
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
      if conf.settings.ingress_drop_monitor then
         ingress_drop_action = conf.settings.ingress_drop_monitor
      end
      if conf.settings.ingress_drop_threshold then
         ingress_drop_threshold = conf.settings.ingress_drop_threshold
      end
      if conf.settings.ingress_drop_interval then
         ingress_drop_interval = conf.settings.ingress_drop_interval
      end
      if conf.settings.ingress_drop_wait then
         ingress_drop_wait = conf.settings.ingress_drop_wait
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

   if id then
      local lwaftr_id = shm.create("nic/id", lwtypes.lwaftr_id_type)
      lwaftr_id.value = id
   end

   local vlan = conf.settings and conf.settings.vlan or false

   conf.interface = {
      mac_address = mac,
      pci = pci,
      id = id,
      mtu = DEFAULT_MTU,
      vlan = vlan,
      mirror_id = mirror_id,
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

   if ingress_drop_action then
      assert(ingress_drop_action == "flush" or ingress_drop_action == "warn",
             "Not valid ingress-drop-monitor action")
      print(("Ingress drop monitor: %s (threshold: %d packets; wait: %d seconds; interval: %.2f seconds)"):format(
             ingress_drop_action, ingress_drop_threshold, ingress_drop_wait, 1e6/ingress_drop_interval))
      local counter_path = lwcounter.counters_dir.."/ingress-packet-drops"
      local mon = ingress_drop_monitor.new({
         action = ingress_drop_action,
         threshold = ingress_drop_threshold,
         wait = ingress_drop_wait,
         counter = counter_path,
      })
      timer.activate(mon:timer(ingress_drop_interval))
   end

   engine.busywait = true
   if opts.duration then
      engine.main({duration=opts.duration, report={showlinks=true}})
   else
      engine.main({report={showlinks=true}})
   end
end
