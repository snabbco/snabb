module(...,package.seeall)

local intel = require "intel"
local ffi = require "ffi"
local C = ffi.C
local test = require("test")
local memory = require("memory")

memory.selftest({verbose = true})

print "selftest"
assert(C.lock_memory() == 0)

pci.selftest()

for _,device in ipairs(pci.suitable_devices()) do
   local pciaddress = device.pciaddress
   print("Testing device: "..pciaddress)
   pci.prepare_device(pciaddress)
   local nic = intel.new(pciaddress)
   print("Initializing controller..")
   nic.init()
   test.waitfor("linkup", nic.linkup, 20, 250000)
   nic.selftest2()
   -- nic.enable_mac_loopback()
   -- nic.selftest({packets=10000000})
end

