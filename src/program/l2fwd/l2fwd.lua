module(...,package.seeall)

local lib = require("core.lib")
local main = require("core.main")

L2Fwd = {}

function L2Fwd.new(conf)
   local o = {}
   return setmetatable(o, { __index = L2Fwd })
end

function L2Fwd:push()
   local input, output = assert(self.input.input), assert(self.output.output)

   while not link.empty(input) do
      link.transmit(output, link.receive(input))
   end
end

local function show_usage(code)
   print(require("program.l2fwd.README_inc"))
   main.exit(code)
end

local function parse_args(args)
   local handlers = {}
   local opts = { duration = 3 }
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
   local driver_class, pciaddr_or_iface = arg:match("(%a+):([%w:.]+)")
   if not driver_class then return "pci", arg end
   return driver_class, pciaddr_or_iface
end

local function config_nic(c, app_name, dev_addr)
   local driver
   local driver_class, pciaddr_or_iface  = parse_nic_driver(dev_addr)
   if driver_class == "tap" then
      driver = require("apps.socket.raw").RawSocket
      config.app(c, app_name, driver, pciaddr_or_iface)
   elseif driver_class == "virtio" then
      driver = require("apps.virtio_net.virtio_net").VirtioNet
      config.app(c, app_name, driver, {pciaddr = pciaddr_or_iface})
   else
      driver = require("apps.intel.intel_app").Intel82599
      config.app(c, app_name, driver, {pciaddr = pciaddr_or_iface})
   end
end

function run(args)
   local opts, arg1, arg2 = parse_args(args)
   local c = config.new()

   config.app(c, "l2fwd", L2Fwd)
   config_nic(c, "nic1", arg1)
   config_nic(c, "nic2", arg2)

   config.link(c, "nic1.tx -> l2fwd.input")
   config.link(c, "l2fwd.output -> nic2.rx")

   engine.configure(c)
   if opts.verbose then
      while true do
         engine.main({duration = opts.duration, report = {showlinks=true, showload=true}})
      end
   else
      engine.main({duration = opts.duration, noreport = true})
   end
end

function selftest()
   print("selftest: l2fwd")
   local driver_class, pciaddr_or_iface
   driver_class, pciaddr_or_iface = parse_nic_driver("virtio:0000:00:01.0")
   assert(driver_class == "virtio" and pciaddr_or_iface == "0000:00:01.0")
   driver_class, pciaddr_or_iface = parse_nic_driver("tap:eth0")
   assert(driver_class == "tap" and pciaddr_or_iface == "eth0")
   driver_class, pciaddr_or_iface = parse_nic_driver("pci:0000:00:01.0")
   assert(driver_class == "pci" and pciaddr_or_iface == "0000:00:01.0")
   driver_class, pciaddr_or_iface = parse_nic_driver("0000:00:01.0")
   assert(driver_class == "pci" and pciaddr_or_iface == "0000:00:01.0")
   print("OK")
end
