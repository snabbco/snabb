module(...,package.seeall)

local lib = require("core.lib")
local main = require("core.main")

local function show_usage(code)
   print(require("program.l2fwd.README_inc"))
   main.exit(code)
end

local function parse_args(args)
   local handlers = {}
   local opts = {}
   function handlers.h() show_usage(0) end
   function handlers.v()
      opts.verbose = true
   end
   function handlers.D(arg)
      opts.duration = assert(tonumber(arg), "duration must be a number")
   end
   args = lib.dogetopt(args, handlers, "hvD:", { help="h", verbose="v", duration="D"})
   if #args ~= 2 then show_usage(1) end
   return opts, unpack(args)
end

local function parse_nic_driver(arg)
   local driver_class, pciaddr = arg:match("(%a+):([%w:.]+)")
   if not driver_class then return "pci", arg end
   return driver_class, pciaddr
end

local function config_nic(c, app_name, pciaddr)
   local driver
   local driver_class, pciaddr  = parse_nic_driver(pciaddr)
   if driver_class == "virtio" then
      driver = require("apps.virtio_net.virtio_net").VirtioNet
      config.app(c, app_name, driver, {pciaddr = pciaddr})
   else
      driver = require("apps.intel.intel_app").Intel82599
      config.app(c, app_name, driver, {pciaddr = pciaddr})
   end
end

function run(args)
   local opts, arg1, arg2 = parse_args(args)
   local c = config.new()

   config_nic(c, "nic1", arg1)
   config_nic(c, "nic2", arg2)

   config.link(c, "nic1.tx -> nic2.rx")
   config.link(c, "nic2.tx -> nic1.rx")

   if opts.verbose then
      local fn = function()
         print("Report (last 1 sec):")
         engine.report_links()
         engine.report_load()
      end
      local t = timer.new("report", fn, 1e9, 'repeating')
      timer.activate(t)
   end

   engine.configure(c)
   if opts.duration then
      engine.main({duration=opts.duration})
   else
      engine.main()
   end
end

function selftest()
   print("selftest: l2fwd")
   local driver_class, pciaddr
   driver_class, pciaddr = parse_nic_driver("virtio:0000:00:01.0")
   assert(driver_class == "virtio" and pciaddr == "0000:00:01.0")
   driver_class, pciaddr = parse_nic_driver("pci:0000:00:01.0")
   assert(driver_class == "pci" and pciaddr == "0000:00:01.0")
   driver_class, pciaddr = parse_nic_driver("0000:00:01.0")
   assert(driver_class == "pci" and pciaddr == "0000:00:01.0")
   print("OK")
end
