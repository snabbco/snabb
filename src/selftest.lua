module(...,package.seeall)

local intel = require "intel"
local ffi = require "ffi"
local C = ffi.C
local test = require("test")

print "selftest"

local nic = intel.new("0000:00:04.0")

print("Initializing controller..")
nic.init()

nic.enable_mac_loopback()
-- nic.enable_phy_loopback()

local dma_start = 0x10000000

local n = 100000

test.waitfor("linkup", nic.linkup, 20, 250000)

print("Transmitting "..n.." packets..")
nic.add_rxbuf(dma_start, 2048)
for i = 1,n do
   while (nic.tx_full() or nic.rx_full()) do
      C.usleep(1)
   end
   nic.add_txbuf(dma_start + math.random(100) * 1024, 996) -- 1000 bytes w/ CRC
   nic.add_rxbuf(dma_start, 2048)
end

print("TX pending", nic.tx_pending())

nic.update_stats()
nic.print_stats()

test.waitfor("receive on loopback",
	     function ()
		nic.update_stats()
		nic.print_stats()
		print(nic.stats.rx_packets)
		return nic.stats.rx_packets == n
	     end,
	     20,
	     100000)

while false do
   nic.print_status()
   nic.print_stats()
   print("writing packet")
   nic.add_txbuf(dma_start + math.random(100) * 1024, 128)
   nic.add_rxbuf(dma_start + math.random(100) * 1024, 16*1024)
   C.usleep(100000)
end

