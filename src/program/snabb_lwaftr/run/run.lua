module(..., package.seeall)

local lib        = require("core.lib")
local nic_common = require("apps.lwaftr.nic_common")
local syscall    = require("syscall")

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
   local stat = syscall.stat(path)
   return stat and stat.isreg
end

local function dir_exists(path)
   local stat = syscall.stat(path)
   return stat and stat.isdir
end

local function nic_exists(pci_addr)
   local devices="/sys/bus/pci/devices"
   return dir_exists(("%s/%s"):format(devices, pci_addr)) or
      dir_exists(("%s/0000:%s"):format(devices, pci_addr))
end

function run(parameters)
   if #parameters == 0 then show_usage(1) end
   local bt_file, conf_file, v4_pci, v6_pci
   local opts = { verbose = true }
   local handlers = {}
   function handlers.v () opts.verbose = true  end
   function handlers.u () opts.ultra_verbose = true opts.verbose = true end
   function handlers.D (arg)
      opts.duration = assert(tonumber(arg), "duration must be a number")
   end
   function handlers.b(arg)
      bt_file = arg
      if not arg then
         fatal("Argument '--bt' was not set")
      end
      if not file_exists(bt_file) then
         fatal(("Couldn't locate binding-table at %s"):format(bt_file))
      end
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
   lib.dogetopt(parameters, handlers, "b:c:n:m:vuDh",
      { bt = "b", conf = "c", ["v4-pci"] = "n", ["v6-pci"] = "m",
         verbose = "v", ultraverbose = "u", duration = "D", help = "h" })
   nic_common.run(bt_file, conf_file, v4_pci, v6_pci, opts)
end
