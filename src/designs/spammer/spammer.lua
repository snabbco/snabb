module(...,package.seeall)

local app       = require("core.app")
local buffer    = require("core.buffer")
local timer     = require("core.timer")
local bus       = require("lib.hardware.bus")
local intel_app = require("apps.intel.intel_app")
local basic_apps = require("apps.basic.basic_apps")

function main ()
   bus.scan_devices()
   app.apps.source = app.new(basic_apps.Source:new())
   local nics = 0
   for _,device in ipairs(bus.devices) do
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
   local t = timer.new("report", fn, 1e9, 'repeating')
   timer.activate(t)
   buffer.preallocate(100000)
   while true do
      app.breathe()
      timer.run()
   end
end

main()

