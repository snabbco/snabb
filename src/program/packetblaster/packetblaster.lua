module(..., package.seeall)

local app       = require("core.app")
local config    = require("core.config")
local timer     = require("core.timer")
local pci       = require("lib.hardware.pci")
local intel_app = require("apps.intel.intel_app")
local basic_apps = require("apps.basic.basic_apps")
local main      = require("core.main")
local PcapReader= require("apps.pcap.pcap").PcapReader
local LoadGen   = require("apps.intel.loadgen").LoadGen
local ffi = require("ffi")
local C = ffi.C

function run (args)
   if #args < 2 then
      print(require("program.packetblaster.README_inc"))
      os.exit(1)
   end
   local filename = table.remove(args, 1)
   local patterns = args
   local c = config.new()
   config.app(c, "pcap", PcapReader, filename)
   config.app(c, "loop", basic_apps.Repeater)
   config.app(c, "tee", basic_apps.Tee)
   config.link(c, "pcap.output -> loop.input")
   config.link(c, "loop.output -> tee.input")
   local nics = 0
   pci.scan_devices()
   for _,device in ipairs(pci.devices) do
      if is_device_suitable(device, patterns) then
         nics = nics + 1
         local name = "nic"..nics
         config.app(c, name, LoadGen, device.pciaddress)
         config.link(c, "tee."..tostring(nics).."->"..name..".input")
      end
   end
   app.configure(c)
   local fn = function ()
                 print("Transmissions (last 1 sec):")
                 app.report_each_app()
              end
   local t = timer.new("report", fn, 1e9, 'repeating')
   timer.activate(t)
   app.main()
end

function is_device_suitable (pcidev, patterns)
   if not pcidev.usable or pcidev.driver ~= 'apps.intel.intel10g' then
      return false
   end
   if #patterns == 0 then
      return true
   end
   for _, pattern in ipairs(patterns) do
      if pcidev.pciaddress:gmatch(pattern)() then
         return true
      end
   end
end


