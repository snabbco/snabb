module(..., package.seeall)

local S          = require("syscall")
local config     = require("core.config")
local cpuset     = require("lib.cpuset")
local csv_stats  = require("program.lwaftr.csv_stats")
local lib        = require("core.lib")
local setup      = require("program.lwaftr.setup")
local cltable    = require("lib.cltable")
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

   if v4 and v4 ~= device then
      print("Migrating instance '"..device.."' to '"..v4.."'")
      config.softwire_config.instance[v4] = instance
      config.softwire_config.instance[device] = nil
   end

   if v6 then
      for id, queue in cltable.pairs(instance.queue) do
         queue.external_interface.device = v6
      end
   end
end

function parse_args(args)
   if #args == 0 then show_usage(1) end
   local conf_file, v4, v6
   local ring_buffer_size
   local opts = { verbosity = 0 }
   local scheduling = { ingress_drop_monitor = 'flush' }
   local handlers = {}
   function handlers.n (arg) opts.name = assert(arg) end
   function handlers.v () opts.verbosity = opts.verbosity + 1 end
   function handlers.i () opts.virtio_net = true end
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
      opts["on-a-stick"] = true
      v4 = arg
      if not nic_exists(v4) then
         fatal(("Couldn't locate NIC with PCI address '%s'"):format(v4))
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
   function handlers.reconfigurable()
      io.stderr:write("Warning: the --reconfigurable flag has been deprecated")
      io.stderr:write(" as the lwaftr is now always reconfigurable.\n")
   end
   function handlers.j(arg) scheduling.j = arg end
   function handlers.h() show_usage(0) end
   lib.dogetopt(args, handlers, "b:c:vD:yhir:n:j:",
     { conf = "c", v4 = 1, v6 = 1, ["v4-pci"] = 1, ["v6-pci"] = 1,
     verbose = "v", duration = "D", help = "h", virtio = "i", cpu = 1,
     ["ring-buffer-size"] = "r", ["real-time"] = 0, ["bench-file"] = "b",
     ["ingress-drop-monitor"] = 1, ["on-a-stick"] = 1, mirror = 1,
     hydra = "y", reconfigurable = 0, name="n" })
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
local function requires_splitter (opts, conf)
   local device, id, queue = lwutil.parse_instance(conf)
   if opts["on-a-stick"] then
      local internal_interface = queue.internal_interface
      local external_interface = queue.external_interface
      return internal_interface.vlan_tag == external_interface.vlan_tag
   end
   return false
end

function run(args)
   local opts, scheduling, conf_file, v4, v6 = parse_args(args)
   local conf = setup.read_config(conf_file)

   -- If the user passed --v4, --v6, or --on-a-stick, migrate the
   -- configuration's device.
   if v4 or v6 then migrate_device_on_config(conf, v4, v6) end

   -- If there is a name defined on the command line, it should override
   -- anything defined in the config.
   if opts.name then conf.softwire_config.name = opts.name end

   local function setup_fn(graph, lwconfig)
      -- If --virtio has been specified, always use this.
      if opts.virtio_net then
	 return setup_fn(graph, lwconfig, 'inetNic', 'b4sideNic')
      end

      -- If instance has external-interface.device configure as bump-in-the-wire
      -- otherwise configure it in on-a-stick mode.
      local device, id, queue = lwutil.parse_instance(lwconfig)
      if queue.external_interface.device then
	 return setup.load_phy(graph, lwconfig, 'inetNic', 'b4sideNic',
			       opts.ring_buffer_size)
      else
	 local use_splitter = requires_splitter(opts, lwconfig)
	 local options = {
	    v4_nic_name = 'inetNic', v6_nic_name = 'b4sideNic',
	    v4v6 = use_splitter and 'v4v6', mirror = opts.mirror,
	    ring_buffer_size = opts.ring_buffer_size
	 }
	 return setup.load_on_a_stick(graph, lwconfig, options)
      end
   end

   local manager = setup.ptree_manager(scheduling, setup_fn, conf)

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
         if use_splitter then
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
