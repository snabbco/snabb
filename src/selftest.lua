module(...,package.seeall)

local intel = require "intel"
local ffi = require "ffi"
local C = ffi.C

print "selftest"

local nic = intel.new("0000:00:04.0")

print("Initializing controller..")
nic.init()

nic.enable_mac_loopback()
-- nic.enable_phy_loopback()

local dma_start = 0x10000000

local n = 0

while true do
   nic.print_status()
   nic.print_stats()
   print("writing packet")
   nic.add_txbuf(dma_start, 123)
   nic.add_rxbuf(dma_start, 16*1024)
   C.usleep(100000)
end

