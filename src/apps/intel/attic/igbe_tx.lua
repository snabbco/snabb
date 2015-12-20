-- igbe_tx.lua -- Intel Gigabit Ethernet: transmit driver

local igbe_tx = {}

local ffi = require("ffi")
local pci = require("lib.hardware.pci")

local virtual_to_physical = require("core.memory").virtual_to_physical

local ndescriptors = 256
local txdesc_t = ffi.typeof("struct { uint64_t address, options; }")
local txdesc_ring_t = ffi.typeof("txdesc_t[?]", ndescriptors)

-- Transmit descriptor array: txdesc_ring_t allocated in DMA memory.
local desc

local pci_mmio -- char* to PCI config registers
local pci_fd   -- file descriptor for PCI device

local function configure (conf)
   print("pciaddress: " .. conf.pciaddress)
   initialize()
end

-- [4.6.10 Transmit Initialization]
local function initialize ()
   desc = ffi.cast(txdesc_ring_t, memory.dma_alloc(ffi.sizeof(txdesc_ring_t)))
   local phys = virtual_to_physical(desc)
   poke(r.TDBAL, phys % 2^32)
   poke(r.TDBAH, phys / 2^32)
   poke(r.TDLEN, ffi.sizeof(txdesc_ring_t))
   poke(r.TXDCTL, {wthresh=16}) -- throttle/suppress descriptor writeback
   poke(r.TXDCTL, {enable=25})
   wait(r.TXDCTL, {enable=25})
end

local tdh, tdt = 0, 0
local txdesc_flags = bits({ifcs=25, dext=29, dtyp0=20, dtyp1=21, eop=24})

-- Transmit a packet asynchronously.
local function transmit (packet)
   desc[tdt].address = virtual_to_physical(packet.data)
   desc.flags = bor(packet.length, txdesc_flags)
   txpackets[tdt] = packet
   tdt = band(tdt+1, ndescriptors-1)
end

-- Return true if a new packet can be transmitted.
local function can_transmit ()
   return band(tdt+1, ndescriptors-1) ~= tdh
end

-- Synchronize ring state with hardware.
-- Free packets that have now been transmitted.
local function sync ()
   local cursor = tdh
   tdh = peek(r.TDH)
   free_packets(
   if cursor ~= tdh then
      while cursor ~= tdh do
         packet.free(packets[cursor])
         packets[cursor] = nil
         cursor = band(cursor+1, ndescriptors-1)
      end
   end
   poke(r.TDT, tdt)
end

-- App callbacks.

function igbe_tx.configure (conf)
   configure(conf)
end

function igbe_tx.push ()
   assert(#input == 1, "igbe_tx expects one input link")
   while link.can_receive(input[1]) and can_transmit() do
      transmit(link.receive(input[1]))
   end
end

function igbe_tx.stop ()
   free_packets(tdh, tdt)
   if pci_fd then pci.close_pci_resource(pci_fd) end
end

return igbe_tx
