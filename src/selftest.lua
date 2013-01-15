module(...,package.seeall)

local intel = require "intel"
local ffi = require "ffi"
local C = ffi.C
local test = require("test")
local memory = require("memory")

assert(C.lock_memory() == 0)

memory.selftest({verbose = false})
pci.selftest()

for _,device in ipairs(pci.suitable_devices()) do
   local pciaddress = device.pciaddress
   print("selftest: intel device "..pciaddress)
   if not pci.prepare_device(pciaddress) then
      error("Failed to prepare PCI device: " .. device.pciaddress)
   end
   local nic = intel.new(pciaddress)
   print "NIC transmit test"
   nic.init()
   nic.selftest({secs=1})
   print "NIC transmit+receive loopback test"
   nic.init()
   nic.reset_stats()
   nic.selftest({secs=1,loopback=true,receive=true})
   -- nic.selftest({packets=10000000})
end

