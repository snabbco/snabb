module(...,package.seeall)

local app       = require("core.app")
local timer     = require("core.timer")
local pci       = require("lib.hardware.pci")
local intel_app = require("apps.intel.intel_app")

function main ()
   app.apps.source = app.new(app.Source)
   local nics = 0
   for _,device in ipairs(pci.devices) do
      if device.usable and device.driver == 'apps.intel.intel10g' then
         nics = nics + 1
         local name = "nic"..nics
         app.apps[name] = intel_app.Intel82599:new(device.pciaddress)
         app.connect("source", tostring(nics),
                     name, "rx")
      end
   end
   app.relink()
   timer.init()
   local fn = function () app.report() end
   local t = timer.new("report", fn, 2e9, 'repeating')
   timer.activate(t)
   while true do
      app.breathe()
      timer.run()
   end
end

main()

