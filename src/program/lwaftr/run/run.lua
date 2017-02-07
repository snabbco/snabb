module(..., package.seeall)

local S          = require("syscall")
local config     = require("core.config")
local csv_stats  = require("program.lwaftr.csv_stats")
local lib        = require("core.lib")
local numa       = require("lib.numa")
local setup      = require("program.lwaftr.setup")
local ingress_drop_monitor = require("lib.timers.ingress_drop_monitor")
local lwutil = require("apps.lwaftr.lwutil")

local fatal, file_exists = lwutil.fatal, lwutil.file_exists
local nic_exists = lwutil.nic_exists

local function show_usage(exit_code)
   print(require("program.lwaftr.run.README_inc"))
   if exit_code then main.exit(exit_code) end
end

function parse_args(args)
   if #args == 0 then show_usage(1) end
   local conf_file, v4, v6
   local ring_buffer_size
   local opts = { verbosity = 0, bench_file = 'bench.csv' }
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
      local cpu = tonumber(arg)
      if not cpu or cpu ~= math.floor(cpu) or cpu < 0 then
         fatal("Invalid cpu number: "..arg)
      end
      scheduling.cpu = cpu
   end
   handlers['real-time'] = function(arg)
      scheduling.real_time = true
   end
   function handlers.v4(arg)
      v4 = arg
      if not nic_exists(v4) then
         fatal(("Couldn't locate NIC with PCI address '%s'"):format(v4))
      end
   end
   handlers["v4-pci"] = function(arg)
      print("WARNING: Deprecated argument '--v4-pci'. Use '--v4' instead.")
      handlers.v4(arg)
   end
   function handlers.v6(arg)
      v6 = arg
      if not nic_exists(v6) then
         fatal(("Couldn't locate NIC with PCI address '%s'"):format(v6))
      end
   end
   handlers["v6-pci"] = function(arg)
      print("WARNING: Deprecated argument '--v6-pci'. Use '--v6' instead.")
      handlers.v6(arg)
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
   function handlers.reconfigurable() opts.reconfigurable = true end
   function handlers.h() show_usage(0) end
   lib.dogetopt(args, handlers, "b:c:vD:yhir:n:",
      { conf = "c", v4 = 1, v6 = 1, ["v4-pci"] = 1, ["v6-pci"] = 1,
        verbose = "v", duration = "D", help = "h", virtio = "i", cpu = 1,
        ["ring-buffer-size"] = "r", ["real-time"] = 0, ["bench-file"] = "b",
        ["ingress-drop-monitor"] = 1, ["on-a-stick"] = 1, mirror = 1,
        hydra = "y", reconfigurable = 0, name="n" })
   if ring_buffer_size ~= nil then
      if opts.virtio_net then
         fatal("setting --ring-buffer-size does not work with --virtio")
      end
      require("apps.intel.intel10g").ring_buffer_size(ring_buffer_size)
   end
   if not conf_file then fatal("Missing required --conf argument.") end
   if opts.mirror then
      assert(opts["on-a-stick"], "Mirror option is only valid in on-a-stick mode")
   end
   if opts["on-a-stick"] then
      scheduling.pci_addrs = { v4 }
      return opts, scheduling, conf_file, v4
   else
      if not v4 then fatal("Missing required --v4 argument.") end
      if not v6 then fatal("Missing required --v6 argument.") end
      scheduling.pci_addrs = { v4, v6 }
      return opts, scheduling, conf_file, v4, v6
   end
end

-- Requires a V4V6 splitter if running in on-a-stick mode and VLAN tag values
-- are the same for the internal and external interfaces.
local function requires_splitter (opts, conf)
   if opts["on-a-stick"] then
      local internal_interface = conf.softwire_config.internal_interface
      local external_interface = conf.softwire_config.external_interface
      return internal_interface.vlan_tag == external_interface.vlan_tag
   end
   return false
end

function run(args)
   local opts, scheduling, conf_file, v4, v6 = parse_args(args)
   local conf = require('apps.lwaftr.conf').load_lwaftr_config(conf_file)
   local use_splitter = requires_splitter(opts, conf)

   if opts.name then engine.claim_name(opts.name) end

   local c = config.new()
   local setup_fn, setup_args
   if opts.virtio_net then
      setup_fn, setup_args = setup.load_virt, { 'inetNic', v4, 'b4sideNic', v6 }
   elseif opts["on-a-stick"] then
      setup_fn = setup.load_on_a_stick
      setup_args =
         { { v4_nic_name = 'inetNic', v6_nic_name = 'b4sideNic',
             v4v6 = use_splitter and 'v4v6', pciaddr = v4,
             mirror = opts.mirror } }
   else
      setup_fn, setup_args = setup.load_phy, { 'inetNic', v4, 'b4sideNic', v6 }
   end

   if opts.reconfigurable then
      setup.reconfigurable(scheduling, setup_fn, c, conf, unpack(setup_args))
   else
      setup.apply_scheduling(scheduling)
      setup_fn(c, conf, unpack(setup_args))
   end

   engine.configure(c)

   if opts.verbosity >= 2 then
      local function lnicui_info() engine.report_apps() end
      local t = timer.new("report", lnicui_info, 1e9, 'repeating')
      timer.activate(t)
   end

   if opts.verbosity >= 1 then
      function add_csv_stats_for_pid(pid)
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
         csv:activate()
      end
      if opts.reconfigurable then
         local pids = engine.configuration.apps['leader'].arg.follower_pids
         for _,pid in ipairs(pids) do
            local function start_sampling()
               -- The worker will be fed its configuration by the
               -- leader, but we don't know when that will all be ready.
               -- Just retry if this doesn't succeed.
               if not pcall(add_csv_stats_for_pid, pid) then
                  io.stderr:write("Waiting on follower "..pid.." to start "..
                                     "before recording statistics...\n")
                  timer.activate(timer.new('retry_csv', start_sampling, 2e9))
               end
            end
            timer.activate(timer.new('spawn_csv_stats', start_sampling, 50e6))
         end
      else
         add_csv_stats_for_pid(S.getpid())
      end
   end

   if opts.ingress_drop_monitor then
      if opts.reconfigurable then
         io.stderr:write("Warning: Ingress drop monitor not yet supported "..
                            "in multiprocess mode.\n")
      else
         local mon = ingress_drop_monitor.new({action=opts.ingress_drop_monitor})
         timer.activate(mon:timer())
      end
   end

   if not opts.reconfigurable then
      -- The leader does not need all the CPU, only the followers do.
      engine.busywait = true
   end
   if opts.duration then
      engine.main({duration=opts.duration, report={showlinks=true}})
   else
      engine.main({report={showlinks=true}})
   end
end
