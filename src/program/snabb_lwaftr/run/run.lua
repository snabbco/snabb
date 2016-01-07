module(..., package.seeall)

local S          = require("syscall")
local config     = require("core.config")
local lib        = require("core.lib")
local csv_stats  = require("lib.csv_stats")
local ethernet   = require("lib.protocol.ethernet")
local Intel82599 = require("apps.intel.intel_app").Intel82599
local basic_apps = require("apps.basic.basic_apps")
local lwaftr     = require("apps.lwaftr.lwaftr")
local ipv4_apps  = require("apps.lwaftr.ipv4_apps")
local ipv6_apps  = require("apps.lwaftr.ipv6_apps")
local setup      = require("program.snabb_lwaftr.setup")

local function show_usage(exit_code)
   print(require("program.snabb_lwaftr.run.README_inc"))
   if exit_code then main.exit(exit_code) end
end

local function fatal(msg)
   show_usage()
   print(msg)
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
   local opts = { verbosity = 0 }
   local handlers = {}
   function handlers.v () opts.verbosity = opts.verbosity + 1 end
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
   function handlers.h() show_usage(0) end
   lib.dogetopt(args, handlers, "b:c:n:m:vD:h",
      { conf = "c", ["v4-pci"] = "n", ["v6-pci"] = "m",
        verbose = "v", duration = "D", help = "h" })
   return opts, conf_file, v4_pci, v6_pci
end

function run(args)
   local opts, conf_file, v4_pci, v6_pci = parse_args(args)

   local c = setup.load(conf_file, 'inetNic', v4_pci, 'b4sideNic', v6_pci)

   engine.configure(c)

   if opts.verbosity >= 2 then
      local function lnicui_info()
         app.report_apps()
      end
      local t = timer.new("report", lnicui_info, 1e9, 'repeating')
      timer.activate(t)
   end

   if opts.verbosity >= 1 then
      local csv = csv_stats.CSVStatsTimer.new()
      csv:add_app('inetNic', { 'tx', 'rx' }, { tx='IPv4 RX', rx='IPv4 TX' })
      csv:add_app('b4sideNic', { 'tx', 'rx' }, { tx='IPv6 RX', rx='IPv6 TX' })
      csv:activate()
   end

   if opts.duration then
      engine.main({duration=opts.duration, report={showlinks=true}})
   else
      engine.main({report={showlinks=true}})
   end
end
