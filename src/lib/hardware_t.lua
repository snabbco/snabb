
local pci = require("lib.hardware.pci")
local vfio = require("lib.hardware.vfio")
local bus = require("lib.hardware.bus")

return {
   bus = function ()
       bus.scan_devices()
       for _,info in ipairs(bus.devices) do
           print (string.format("device %s: %s", info.pciaddress, info.bus))
       end
   end,
   
   --- PCI selftest scans for available devices and performs our driver's
   --- self-test on each of them.
   pci = pci.print_device_summary,
   
   --- ditto for VFIO
   vfio = vfio.print_device_summary,
}
