module(..., package.seeall)

local S          = require("syscall")
local config     = require("core.config")
local cpuset     = require("lib.cpuset")
local csv_stats  = require("program.lwaftr.csv_stats")
local ethernet   = require("lib.protocol.ethernet")
local lib        = require("core.lib")
local setup      = require("program.lwaftr.setup")
local ingress_drop_monitor = require("lib.timers.ingress_drop_monitor")
local lwutil = require("apps.lwaftr.lwutil")
local engine = require("core.app")

local fatal, file_exists = lwutil.fatal, lwutil.file_exists
local nic_exists = lwutil.nic_exists

local function show_usage(exit_code)
   print(require("program.lwaftr.run.README_inc"))
   if exit_code then main.exit(exit_code) end
end
local function migrate_device_on_config(config, v4, v6)
   -- Validate there is only one instance, otherwise the option is ambiguous.
   local device, instance
   for k, v in pairs(config.softwire_config.instance) do
      assert(device == nil,
             "Unable to specialize config for specified NIC(s) as"..
                "there are multiple instances configured.")
      device, instance = k, v
   end
   assert(device ~= nil,
          "Unable to specialize config for specified NIC(s) as"..
             "there are no instances configured.")

   if v6 and v6 ~= device then
      print("Migrating instance '"..device.."' to '"..v6.."'")
      config.softwire_config.instance[v6] = instance
      config.softwire_config.instance[device] = nil
   end

   if v4 then
      instance.external_device = v4
   end
end

function parse_args(args)
   if #args == 0 then show_usage(1) end
   local conf_file, v4, v6
   local ring_buffer_size
   local opts = { verbosity = 0 }
   local scheduling = { ingress_drop_monitor = 'flush', profile = false }
   local handlers = {}
   function handlers.n (arg) opts.name = assert(arg) end
   function handlers.v () opts.verbosity = opts.verbosity + 1 end
   function handlers.t (arg) opts.trace = assert(arg) end
   function handlers.i () opts.virtio_net = true end
   handlers['xdp'] = function(arg)
      opts['xdp'] = true
      scheduling.enable_xdp = {} -- XXX - maybe configure num_chunks here?
   end
   function handlers.D (arg)
      opts.duration = assert(tonumber(arg), "duration must be a number")
      assert(opts.duration >= 0, "duration can't be negative")
   end
   function handlers.c(arg)
      conf_file = arg
      if not file_exists(conf_file) then
         fatal(("Couldn't locate configuration file at %s"):format(conf_file))
      end
   end
   function handlers.cpu(arg)
      cpuset.global_cpuset():add_from_string(arg)
   end
   handlers['real-time'] = function(arg)
      scheduling.real_time = true
   end
   function handlers.r (arg)
      ring_buffer_size = tonumber(arg)
   end
   handlers["on-a-stick"] = function(arg)
      if lib.is_iface(arg) or nic_exists(arg) then
         v4 = arg
         opts['on-a-stick'] = arg
      else
         fatal(("Couldn't locate NIC with PCI address '%s'"):format(arg))
      end
   end
   handlers["mirror"] = function (ifname)
      opts["mirror"] = ifname
   end
   function handlers.v4(arg) v4 = arg end
   function handlers.v6(arg) v6 = arg end
   function handlers.y() opts.hydra = true end
   function handlers.b(arg) opts.bench_file = arg end
   handlers["ingress-drop-monitor"] = function (arg)
      if arg == 'flush' or arg == 'warn' then
         scheduling.ingress_drop_monitor = arg
      elseif arg == 'off' then
         scheduling.ingress_drop_monitor = false
      else
         fatal("invalid --ingress-drop-monitor argument: " .. arg
                  .." (valid values: flush, warn, off)")
      end
   end
   function handlers.profile() scheduling.profile = true end
   function handlers.h() show_usage(0) end
   lib.dogetopt(args, handlers, "b:c:vD:yhir:n:t:",
     { conf = "c", name = "n", cpu = 1, v4 = 1, v6 = 1,
       ["on-a-stick"] = 1, virtio = "i", ["ring-buffer-size"] = "r",
       ["xdp"] = 0,
       ["real-time"] = 0, mirror = 1, ["ingress-drop-monitor"] = 1,
       verbose = "v", trace = "t", ["bench-file"] = "b", ["profile"] = 0,
       duration = "D", hydra = "y", help = "h" })
   if ring_buffer_size ~= nil then
      if opts.virtio_net then
         fatal("setting --ring-buffer-size does not work with --virtio")
      end
      opts.ring_buffer_size = ring_buffer_size
   end
   if not conf_file then fatal("Missing required --conf argument.") end
   if opts.mirror then
      assert(opts["on-a-stick"], "Mirror option is only valid in on-a-stick mode")
   end
   if opts["on-a-stick"] and v6 then
      fatal("Options --on-a-stick and --v6 are mutually exclusive.")
   end
   return opts, scheduling, conf_file, v4, v6
end

-- Requires a V4V6 splitter if running in on-a-stick mode and VLAN tag values
-- are the same for the internal and external interfaces.
local function requires_splitter (conf)
   local queue = select(3, lwutil.parse_instance(conf))
   local int = queue.internal_interface
   local ext = queue.external_interface
   return ethernet:ntop(int.mac) == ethernet:ntop(ext.mac) and
          int.vlan_tag == ext.vlan_tag
end

function run(args)
   local opts, scheduling, conf_file, v4, v6 = parse_args(args)
   local conf = setup.read_config(conf_file)

   -- If the user passed --v4, --v6, or --on-a-stick, migrate the
   -- configuration's device.
   if opts['on-a-stick'] then assert(v4); v6 = v4 end
   if v4 or v6 then migrate_device_on_config(conf, v4, v6) end

   -- If there is a name defined on the command line, it should override
   -- anything defined in the config.
   if opts.name then conf.softwire_config.name = opts.name end

   -- If we’re using XDP, setup interfaces here
   if opts.xdp then
      setup.xdp_ifsetup(conf)
   end

   local function setup_fn(graph, lwconfig)
      -- If --virtio has been specified, always use this.
      if opts.virtio_net then
         return setup_fn(graph, lwconfig, 'inetNic', 'b4sideNic')
      end

      -- If --xdp has been specified, always use this.
      if opts.xdp then
         return setup.load_xdp(graph, lwconfig, 'inetNic', 'b4sideNic',
                               opts.ring_buffer_size)
      end

      -- If instance has external-device configure as bump-in-the-wire
      -- otherwise configure it in on-a-stick mode.
      local device = lwutil.parse_instance(lwconfig)
      local instance = lwconfig.softwire_config.instance[device]
      if not lwutil.is_on_a_stick(lwconfig, device) then
         if lib.is_iface(instance.external_device) then
            return setup.load_kernel_iface(graph, lwconfig, 'inetNic', 'b4sideNic')
         else
            return setup.load_phy(graph, lwconfig, 'inetNic', 'b4sideNic',
                                  opts.ring_buffer_size)
         end
      else
         local use_splitter = requires_splitter(lwconfig)
         local options = {
            v4_nic_name = 'inetNic', v6_nic_name = 'b4sideNic',
            v4v6 = use_splitter and 'v4v6', mirror = opts.mirror,
            ring_buffer_size = opts.ring_buffer_size
         }
         if lib.is_iface(opts['on-a-stick']) then
            return setup.load_on_a_stick_kernel_iface(graph, lwconfig, options)
         else
            return setup.load_on_a_stick(graph, lwconfig, options)
         end
      end
   end

   local manager_opts = { worker_default_scheduling=scheduling,
                          rpc_trace_file=opts.trace }
   local manager = setup.ptree_manager(setup_fn, conf, manager_opts)

   -- FIXME: Doesn't work in multi-process environment.
   if false and opts.verbosity >= 2 then
      local function lnicui_info() engine.report_apps() end
      local t = timer.new("report", lnicui_info, 1e9, 'repeating')
      timer.activate(t)
   end

   if opts.verbosity >= 1 then
      local stats = {csv={}}
      function stats:worker_starting(id) end
      function stats:worker_started(id, pid)
         local csv = csv_stats.CSVStatsTimer:new(opts.bench_file, opts.hydra, pid)
         -- Link names like "tx" are from the app's perspective, but
         -- these labels are from the perspective of the lwAFTR as a
         -- whole so they are reversed.
         local ipv4_tx = opts.hydra and 'ipv4rx' or 'IPv4 RX'
         local ipv4_rx = opts.hydra and 'ipv4tx' or 'IPv4 TX'
         local ipv6_tx = opts.hydra and 'ipv6rx' or 'IPv6 RX'
         local ipv6_rx = opts.hydra and 'ipv6tx' or 'IPv6 TX'
         if requires_splitter(conf) then
            csv:add_app('v4v6', { 'v4', 'v4' }, { tx=ipv4_tx, rx=ipv4_rx })
            csv:add_app('v4v6', { 'v6', 'v6' }, { tx=ipv6_tx, rx=ipv6_rx })
         else
            csv:add_app('inetNic', { 'tx', 'rx' }, { tx=ipv4_tx, rx=ipv4_rx })
            csv:add_app('b4sideNic', { 'tx', 'rx' }, { tx=ipv6_tx, rx=ipv6_rx })
         end
         self.csv[id] = csv
         self.csv[id]:start()
      end
      function stats:worker_stopping(id)
         self.csv[id]:stop()
         self.csv[id] = nil
      end
      function stats:worker_stopped(id) end
      manager:add_state_change_listener(stats)
   end

   manager:main(opts.duration)
   manager:stop()
end
