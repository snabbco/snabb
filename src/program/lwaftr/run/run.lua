module(..., package.seeall)

local S          = require("syscall")
local config     = require("core.config")
local csv_stats  = require("program.lwaftr.csv_stats")
local lib        = require("core.lib")
local setup      = require("program.lwaftr.setup")
local ingress_drop_monitor_timer = require("lib.timers.ingress_drop_monitor")

local function show_usage(exit_code)
   print(require("program.lwaftr.run.README_inc"))
   if exit_code then main.exit(exit_code) end
end

local function fatal(msg)
   show_usage()
   print('error: '..msg)
   main.exit(1)
end

local function file_exists(path)
   local stat = S.stat(path)
   return stat and stat.isreg
end

local function dir_exists(path)
   local stat = S.stat(path)
   return stat and stat.isdir
end

local function nic_exists(pci_addr)
   local devices="/sys/bus/pci/devices"
   return dir_exists(("%s/%s"):format(devices, pci_addr)) or
      dir_exists(("%s/0000:%s"):format(devices, pci_addr))
end

function parse_args(args)
   if #args == 0 then show_usage(1) end
   local conf_file, v4_pci, v6_pci
   local ring_buffer_size
   local opts = { verbosity = 0 }
   local handlers = {}
   function handlers.v () opts.verbosity = opts.verbosity + 1 end
   function handlers.i () opts.virtio_net = true end
   function handlers.D (arg)
      opts.duration = assert(tonumber(arg), "duration must be a number")
   end
   function handlers.c(arg)
      conf_file = arg
      if not arg then
         fatal("Argument '--conf' was not set")
      end
      if not file_exists(conf_file) then
         fatal(("Couldn't locate configuration file at %s"):format(conf_file))
      end
   end
   function handlers.cpu(arg)
      local cpu = tonumber(arg)
      if not cpu or cpu ~= math.floor(cpu) or cpu < 0 then
         fatal("Invalid cpu number: "..arg)
      end
      local cpu_set = S.sched_getaffinity()
      cpu_set:zero()
      cpu_set:set(cpu)
      S.sched_setaffinity(0, cpu_set)
   end
   handlers['real-time'] = function(arg)
      if not S.sched_setscheduler(0, "fifo", 1) then
         fatal('Failed to enable real-time scheduling.  Try running as root.')
      end
   end
   function handlers.n(arg)
      v4_pci = arg
      if not arg then
         fatal("Argument '--v4-pci' was not set")
      end
      if not nic_exists(v4_pci) then
         fatal(("Couldn't locate NIC with PCI address '%s'"):format(v4_pci))
      end
   end
   function handlers.m(arg)
      v6_pci = arg
      if not v6_pci then
         fatal("Argument '--v6-pci' was not set")
      end
      if not nic_exists(v6_pci) then
         fatal(("Couldn't locate NIC with PCI address '%s'"):format(v6_pci))
      end
   end
   function handlers.r (arg)
      ring_buffer_size = tonumber(arg)
      if not ring_buffer_size then fatal("bad ring size: " .. arg) end
      if ring_buffer_size > 32*1024 then
         fatal("ring size too large for hardware: " .. ring_buffer_size)
      end
      if math.log(ring_buffer_size)/math.log(2) % 1 ~= 0 then
         fatal("ring size is not a power of two: " .. arg)
      end
   end
   handlers["no-ingress-drop-monitor"] = function (arg)
      opts.ingress_drop_monitor = false
   end
   function handlers.h() show_usage(0) end
   lib.dogetopt(args, handlers, "b:c:n:m:vD:hir:",
      { conf = "c", ["v4-pci"] = "n", ["v6-pci"] = "m",
        verbose = "v", duration = "D", help = "h",
        virtio = "i", ["ring-buffer-size"] = "r", cpu = 1,
        ["real-time"] = 0, ["no-ingress-drop-monitor"] = 0, })
   if ring_buffer_size ~= nil then
      if opts.virtio_net then
         fatal("setting --ring-buffer-size does not work with --virtio")
      end
      require('apps.intel.intel10g').num_descriptors = ring_buffer_size
   end
   if not conf_file then fatal("Missing required --conf argument.") end
   if not v4_pci then fatal("Missing required --v4-pci argument.") end
   if not v6_pci then fatal("Missing required --v6-pci argument.") end
   return opts, conf_file, v4_pci, v6_pci
end

function run(args)
   local opts, conf_file, v4_pci, v6_pci = parse_args(args)
   local conf = require('apps.lwaftr.conf').load_lwaftr_config(conf_file)

   local c = config.new()
   if opts.virtio_net then
      setup.load_virt(c, conf, 'inetNic', v4_pci, 'b4sideNic', v6_pci)
   else
      setup.load_phy(c, conf, 'inetNic', v4_pci, 'b4sideNic', v6_pci)
   end
   engine.configure(c)

   if opts.verbosity >= 2 then
      local function lnicui_info() engine.report_apps() end
      local t = timer.new("report", lnicui_info, 1e9, 'repeating')
      timer.activate(t)
   end

   if opts.verbosity >= 1 then
      local csv = csv_stats.CSVStatsTimer.new()
      csv:add_app('inetNic', { 'tx', 'rx' }, { tx='IPv4 RX', rx='IPv4 TX' })
      csv:add_app('b4sideNic', { 'tx', 'rx' }, { tx='IPv6 RX', rx='IPv6 TX' })
      csv:activate()
   end

   if opts.ingress_drop_monitor or opts.ingress_drop_monitor == nil then
      timer.activate(ingress_drop_monitor_timer)
   end

   engine.busywait = true
   if opts.duration then
      engine.main({duration=opts.duration, report={showlinks=true}})
   else
      engine.main({report={showlinks=true}})
   end
end
