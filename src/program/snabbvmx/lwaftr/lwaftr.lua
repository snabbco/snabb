module(..., package.seeall)

local config = require("core.config")
local constants = require("apps.lwaftr.constants")
local ingress_drop_monitor = require("lib.timers.ingress_drop_monitor")
local lib = require("core.lib")
local counters = require("program.lwaftr.counters")
local lwutil = require("apps.lwaftr.lwutil")
local setup = require("program.snabbvmx.lwaftr.setup")
local shm = require("core.shm")

local fatal, file_exists = lwutil.fatal, lwutil.file_exists

local DEFAULT_MTU = 9500

local function show_usage (exit_code)
   print(require("program.snabbvmx.lwaftr.README_inc"))
   main.exit(exit_code)
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

local function effective_vlan (conf, external_interface, internal_interface)
   if conf.settings and conf.settings.vlan then
      return conf.settings.vlan
   end
   if external_interface.vlan_tag then
      if external_interface.vlan_tag == internal_interface.vlan_tag then
         return external_interface.vlan_tag
      end
      return {v4_vlan_tag = external_interface.vlan_tag,
              v6_vlan_tag = internal_interface.vlan_tag}
   end
   return false
end

function run(args)
   local opts, conf_file, id, pci, mac, sock_path, mirror_id = parse_args(args)

   local conf, lwconf
   local external_interface, internal_interface
   local ring_buffer_size = 2048

   local ingress_drop_action = "flush"
   local ingress_drop_threshold = 100000
   local ingress_drop_interval = 1e6
   local ingress_drop_wait = 20

   if file_exists(conf_file) then
      conf, lwconf = setup.load_conf(conf_file)
      external_interface = lwconf.softwire_config.external_interface
      internal_interface = lwconf.softwire_config.internal_interface
      -- If one interface has vlan tags, then the other one should as well.
      assert((not external_interface.vlan_tag) == (not internal_interface.vlan_tag))
   else
      print(("Interface '%s' set to passthrough mode."):format(id))
      ring_buffer_size = 1024
      conf = {settings = {}}
   end

   if conf.settings then
      if conf.settings.ingress_drop_monitor then
         ingress_drop_action = conf.settings.ingress_drop_monitor
         if ingress_drop_action == 'off' then
            ingress_drop_action = nil
         end
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
   end

   if id then engine.claim_name(id) end

   local vlan = false
   local mtu = DEFAULT_MTU
   if lwconf then
      vlan = effective_vlan(conf, external_interface, internal_interface)
      mtu = internal_interface.mtu
      if external_interface.mtu > mtu then mtu = external_interface.mtu end
      mtu = mtu + constants.ethernet_header_size
      if external_interface.vlan_tag then mtu = mtu + 4 end
   end

   conf.interface = {
      mac_address = mac,
      pci = pci,
      id = id,
      mtu = mtu,
      vlan = vlan,
      mirror_id = mirror_id,
      ring_buffer_size = ring_buffer_size,
   }

   local c = config.new()
   if lwconf then
      setup.lwaftr_app(c, conf, lwconf, sock_path)
   else
      setup.passthrough(c, conf, sock_path)
   end
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
      local counter_path = "apps/lwaftr/ingress-packet-drops"
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
