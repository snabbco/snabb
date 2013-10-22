module(...,package.seeall)

local app       = require("core.app")
local buffer    = require("core.buffer")
local timer     = require("core.timer")
local pci       = require("lib.hardware.pci")
local intel_app = require("apps.intel.intel_app")
local basic_apps = require("apps.basic.basic_apps")
local main      = require("core.main")
local PcapReader= require("apps.pcap.pcap").PcapReader
local LoadGen   = require("apps.intel.LoadGen")
local ffi = require("ffi")
local C = ffi.C

function run (args)
   local filename = table.remove(args, 1)
   local patterns = args
   app.apps.pcap = app.new(PcapReader:new(filename))
   app.apps.loop = app.new(basic_apps.Repeater:new())
   app.apps.tee  = app.new(basic_apps.Tee:new(filename))
   app.connect("pcap", "output", "loop", "input")
   app.connect("loop", "output", "tee", "input")
   local nics = 0
   for _,device in ipairs(pci.devices) do
      if is_device_suitable(device, patterns) then
         nics = nics + 1
         local name = "nic"..nics
         app.apps[name] = app.new(LoadGen:new(device.pciaddress))
         app.connect("tee", tostring(nics),
                     name, "input")
      end
   end
   app.relink()
   timer.init()
   local fn = function ()
                 app.report()
              end
   local t = timer.new("report", fn, 1e9, 'repeating')
   timer.activate(t)
   buffer.preallocate(100000)
   while true do
      app.breathe()
      timer.run()
      C.usleep(1000)
   end
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

run(main.parameters)

