-- intel.lua -- Intel 82574L driver with Linux integration
-- Copyright 2012 Snabb GmbH. See the file LICENSE.

-- This is a device driver for the Intel 82574L gigabit ethernet controller.
-- The chip is very well documented in Intel's data sheet:
-- http://ark.intel.com/products/32209/Intel-82574L-Gigabit-Ethernet-Controller

module(...,package.seeall)

-- Notes:
-- PSP (pad short packets to 64 bytes)

local ffi = require("ffi")
local snabb = ffi.load("snabb")
local bit = require("bit")
local c = require("c")
local C = ffi.C

ffi.cdef(io.open(os.getenv("SNABB").."/src/c/snabb.h"):read("*a"))

-- Linux-based glue code to access the device.

function pcidev_is_82574 (device)
   return io.open(path(device,"config"), "ro"):read(4) == "\x86\x80\xd3\x10"
end

function path(pcidev, file)
   return "/sys/bus/pci/devices/"..pcidev.."/"..file
end

-- 1. map registers
function map_pci_memory (device, n)
   local filepath = path(device,"resource")..n
   local addr = snabb.map_pci_resource(filepath)
   assert( addr ~= 0 )
   return addr
end

-- Return a table for protected (bounds-checked) memory access.
-- 
-- The table can be indexed like a pointer. Index 0 refers to address
-- BASE+OFFSET, index N refers to address BASE+OFFSET+N*sizeof(TYPE),
-- and access to addresses beyond BASE+OFFSET+SIZE is prohibited.
--
-- Examples:
--   local mem =  protected("uint32_t", 0x1000, 0x0, 0x100)
--   mem[0x000] => <word at 0x1000>
--   mem[0x001] => <word at 0x1004>
--   mem[0x080] => ERROR <address out of bounds: 0x1200>
--   mem.ptr   => cdata<uint32_t *>: 0x1000 (get the raw pointer)
local function protected (type, base, offset, size)
   type = ffi.typeof(type)
   local bound = (size + 0ULL) / ffi.sizeof(type)
   local tptr = ffi.typeof("$ *", type)
   local wrap = ffi.metatype(ffi.typeof("struct { $ _ptr; }", tptr), {
				__index = function(w, idx)
					     assert(idx < bound)
					     return w._ptr[idx]
					  end,
				__newindex = function(w, idx, val)
						assert(idx < bound)
						w._ptr[idx] = val
					     end,
			     })
   return wrap(ffi.cast(tptr, ffi.cast("uint8_t *", base) + offset))
end

-- 2. MMAP physical memory

local dma_start = 0x10000000
local dma_end   = 0x11000000

-- Static DMA memory map. Offsets for each memory region.
local offset_txdesc   = 0x00000000 --  1MB TX descriptors
local offset_rxdesc   = 0x00100000 --  1MB RX descriptors
local offset_buffers  = 0x00200000 -- 14MB packet buffers

local num_descriptors = 32
local buffer_size = 16384

local dma_phys = dma_start -- physical address of DMA memory
local dma_virt = nil       -- virtual mmap'd address of DMA memory
local dma_ptr  = nil       -- pointer to first byte of free DMA memory

local rxdesc  = nil
local txdesc  = nil
local buffers = nil

-- Register addresses as 32-bit word offsets.
local CTRL   = 0x00000 / 4 -- Device Control Register (RW)
local STATUS = 0x00008 / 4 -- Device Status Register (RO)
local PBA    = 0x01000 / 4 -- Packet Buffer Allocation
local IMC    = 0x000D8 / 4 -- Interrupt Mask Clear (W)
local RCTL   = 0x00100 / 4 -- Receive Control Register (RW)
local RFCTL  = 0x05008 / 4 -- Receive Filter Control Register (RW)
local RXDCTL = 0x02828 / 4 -- Receive Descriptor Control (RW)
local RXCSUM = 0x05000 / 4 -- Receive Checksum Control (RW)
local RDBAL  = 0x02800 / 4 -- Receive Descriptor Base Address Low (RW)
local RDBAH  = 0x02804 / 4 -- Receive Descriptor Base Address High (RW)
local RDLEN  = 0x02808 / 4 -- Receive Descriptor Length (RW)
local RDH    = 0x02810 / 4 -- Receive Descriptor Head (RW)
local RDT    = 0x02818 / 4 -- Receive Descriptor Tail (RW)
local TXDCTL = 0x03828 / 4 -- Transmit Descriptor Control (RW)
local TCTL   = 0x00400 / 4 -- Transmit Control Register (RW)
local TIPG   = 0x00410 / 4 -- Transmit Inter-Packet Gap (RW)
local TDBAL  = 0x03800 / 4 -- Transmit Descriptor Base Address Low (RW)
local TDBAH  = 0x03804 / 4 -- Transmit Descriptor Base Address High (RW)
local TDLEN  = 0x03808 / 4 -- Transmit Descriptor Length (RW)
local TDH    = 0x03810 / 4 -- Transmit Descriptor Head (RW)
local TDT    = 0x03818 / 4 -- Transmit Descriptor Tail (RW)
local MDIC   = 0x00020 / 4 -- MDI Control Register (RW)
local EXTCNF_CTRL = 0x00F00 / 4 -- Extended Configuration Control (RW)
local POEMB  = 0x00F10 / 4 -- PHY OEM Bits Register (RW)
local ICR    = 0x00C00 / 4 -- Interrupt Cause Register (RW)

local regs = ffi.cast("uint32_t *", map_pci_memory("0000:00:04.0", 0))          

-- Initialization

function init ()
   reset()
   init_dma_memory()
   init_link()
   init_statistics()
   init_receive()
   init_transmit()
end

function reset ()
   -- Disable interrupts (IMC)
   regs[IMC] = 0
   -- Global reset
   regs[CTRL] = bits({FD=0,SLU=6,RST=26})
   C.usleep(10); assert( not bitset(regs[CTRL],26) )
   -- Disable interrupts
   regs[IMC] = 0
end

function init_dma_memory ()
   dma_virt = snabb.map_physical_ram(dma_start, dma_end, true)
   C.memset(dma_virt, 0, dma_end - dma_start)
   rxdesc  = protected("union rx", dma_virt, offset_rxdesc, 0x100000)
   txdesc  = protected("union tx", dma_virt, offset_txdesc, 0x100000)
   buffers = protected("uint8_t", dma_virt, offset_buffers, 0xe00000)
end

function init_link ()
   reset_phy()
   -- phy_write(9, bit.bor(bits({Adv1GFDX=9})))
   -- force_autoneg()
end

function init_statistics ()
   -- Statistics registers initialize themselves within 1ms of a reset.
   C.usleep(1000)
end

function print_status ()
   local status, tctl, rctl = regs[STATUS], regs[TCTL], regs[RCTL]
   print("MAC status")
   print("  STATUS      = " .. bit.tohex(status))
   print("  Full Duplex = " .. onoff(status, 0))
   print("  Link Up     = " .. onoff(status, 1))
   print("  PHYRA       = " .. onoff(status, 10))
   speed = (({10,100,1000,1000})[1+bit.band(bit.rshift(status, 6),3)])
   print("  Speed       = " .. speed .. ' Mb/s')
   print("Transmit status")
   print("  TCTL        = " .. bit.tohex(tctl))
   print("  TXDCTL      = " .. bit.tohex(regs[TXDCTL]))
   print("  TX Enable   = " .. onoff(tctl, 1))
   print("  TDH         = " .. regs[TDH])
   print("  TDT         = " .. regs[TDT])
   print("  TDBAH       = " .. bit.tohex(regs[TDBAH]))
   print("  TDBAL       = " .. bit.tohex(regs[TDBAL]))
   print("  TDLEN       = " .. regs[TDLEN])
   print("Receive status")
   print("  RCTL        = " .. bit.tohex(rctl))
   print("  RXDCTL      = " .. bit.tohex(regs[RXDCTL]))
   print("  RX Enable   = " .. onoff(rctl, 1))
   print("  RX Loopback = " .. onoff(rctl, 6))
   print("  RDH         = " .. regs[RDH])
   print("  RDT         = " .. regs[RDT])
   print("  RDBAH       = " .. bit.tohex(regs[RDBAH]))
   print("  RDBAL       = " .. bit.tohex(regs[RDBAL]))
   print("  RDLEN       = " .. regs[RDLEN])
   print("PHY status")
   local phystatus, phyext, copperstatus = phy_read(1), phy_read(15), phy_read(17)
   print("  Autonegotiate state    = " .. (bitset(phystatus,5) and 'complete' or 'not complete'))
   print("  Remote fault detection = " .. (bitset(phystatus,4) and 'remote fault detected' or 'no remote fault detected'))
   print("  Copper Link Status     = " .. (bitset(copperstatus,3) and 'copper link is up' or 'copper link is down'))
   print("  Speed and duplex resolved = " .. onoff(copperstatus,11))
   physpeed = (({10,100,1000,'(reserved)'})[1+bit.band(bit.rshift(status, 6),3)])
   print("  Speed                  = " .. physpeed .. 'Mb/s')
   print("  Duplex                 = " .. (bitset(copperstatus,13) and 'full-duplex' or 'half-duplex'))
   local autoneg, autoneg1G = phy_read(4), phy_read(9)
   print("  Advertise 1000 Mb/s FD = " .. onoff(autoneg1G,9))
   print("  Advertise 1000 Mb/s HD = " .. onoff(autoneg1G,8))
   print("  Advertise  100 Mb/s FD = " .. onoff(autoneg,8))
   print("  Advertise  100 Mb/s HD = " .. onoff(autoneg,7))
   print("  Advertise   10 Mb/s FD = " .. onoff(autoneg,6))
   print("  Advertise   10 Mb/s HD = " .. onoff(autoneg,5))
   local partner, partner1G = phy_read(5), phy_read(10)
   print("  Partner   1000 Mb/s FD = " .. onoff(partner1G,11)) -- reg 10
   print("  Partner   1000 Mb/s HD = " .. onoff(partner1G,10))
   print("  Partner    100 Mb/s FD = " .. onoff(partner,8))
   print("  Partner    100 Mb/s HD = " .. onoff(partner,7))
   print("  Partner     10 Mb/s FD = " .. onoff(partner,6))
   print("  Partner     10 Mb/s HD = " .. onoff(partner,5))
end

function onoff (value, bit)
   return bitset(value, bit) and 'on' or 'off'
end

-- Receive functionality

ffi.cdef[[
// RX descriptor written by software.
struct rx_desc {
    uint64_t address;    // 64-bit address of receive buffer
    uint64_t dd;         // low bit must be 0, otherwise reserved
} __attribute__((packed));

// RX writeback descriptor written by hardware.
struct rx_desc_wb {
   uint16_t checksum, ipid;
   uint32_t mrq;
   uint16_t vlan, length;
   uint32_t status;
} __attribute__((packed));

union rx {
   struct rx_desc desc;
   struct rx_desc_wb wb;
};

]]

function init_receive ()
   -- Disable RX and program all the registers
   regs[RCTL] = bits({UPE=3, MPE=4, -- Unicast & Multicast promiscuous mode
		      LPE=5,        -- Long Packet Enable (XXX what is that?)
		      BSIZE1=16, BSEX=25, -- 16KB buffers
		      SECRC=26      -- Strip Ethernet CRC from packets
      })
   regs[RFCTL] = bits({EXSTEN=15})  -- Extended RX writeback descriptor format
   regs[RXDCTL] = bits({WTHRESH0=16}) -- Set to data sheet default value
   regs[RXCSUM] = 0                 -- Disable checksum offload - not needed
   regs[RDLEN] = num_descriptors * ffi.sizeof("union rx")
   regs[RDBAL] = bit.band(dma_phys + offset_rxdesc, 0xffffffff)
   regs[RDBAH] = 0
--   regs[RDBAH] = bit.rshift(dma_phys + offset_rxdesc, 32)
   regs[RDH] = 0
   regs[RDT] = 0
   -- Enable RX
   regs[RCTL] = bit.bor(regs[RCTL], bits{EN=1})
end

-- Enqueue a receive descriptor to receive a packet.
function add_rxbuf (address, size)
   -- NOTE: RDT points to the next unused descriptor
   local index = regs[RDT]
   rxdesc[index].desc.address = address
   rxdesc[index].desc.dd = 0
   regs[RDT] = index + 1 % num_descriptors
   return true
end

function is_rx_descriptor_available ()
   return regs[RDT] ~= regs[RDH] + 1 % num_descriptors
end

-- Transmit functionality

ffi.cdef[[
// TX Extended Data Descriptor written by software.
struct tx_desc {
   uint64_t address;
   uint64_t options;
/*
--   unsigned int vlan:16;
--   unsigned int popts:8;
--   unsigned int extcmd:4;
--   unsigned int sta:4;
--   unsigned int dcmd:8;
--   unsigned int dtype:4;
--   unsigned int dtalen:20;
 */
} __attribute__((packed));

union tx {
   struct tx_desc desc;
   // XXX context descriptor
};
]]

function init_transmit ()
   regs[TCTL] = bit.bor(bits({PSP=3}),
			bit.lshift(0x3F, 12)) -- COLD value for full duplex
   regs[TXDCTL] = bits({GRAN=24, WTHRESH0=16})
   regs[TIPG] = 0x00602006 -- Suggested value in data sheet
   init_transmit_ring()
   -- Enable transmit
   regs[TCTL] = bit.bor(regs[TCTL], bits({EN=1}))
end

function init_transmit_ring ()
   regs[TDBAL] = bit.band(dma_phys + offset_txdesc, 0xffffffff)
   regs[TDBAH] = 0
--   regs[TDBAH] = bit.rshift(dma_phys + offset_txdesc, 32)
   print(bit.tohex(dma_phys + offset_txdesc),
	 bit.tohex(bit.band(dma_phys + offset_txdesc, 0xffffffff)),
	 bit.tohex(bit.rshift(dma_phys + offset_txdesc, 32)))
   assert(regs[TDBAL] ~= regs[TDBAH])
   -- Hardware requires the value to be 128-byte aligned
   assert( num_descriptors * ffi.sizeof("union tx") % 128 == 0 )
   regs[TDLEN] = num_descriptors * ffi.sizeof("union tx")
end

-- Enqueue a transmit descriptor to send a packet.
function add_txbuf (address, size)
   local index = regs[TDT]
   txdesc[index].desc.address = address
   txdesc[index].desc.options = bit.bor(size, bits({dtype=20, eop=24, dext=29}))
   -- txdesc[index].desc.dtalen = size
   -- txdesc[index].desc.dtype  = 0x1
   -- txdesc[index].desc.sta    = 0
   -- txdesc[index].desc.dcmd   = 0x20 -- EOP(0)=0 DEXT(5)=1
   regs[TDT] = index + 1 % num_descriptors
end

-- 
function is_tx_descriptor_available ()
   return regs[TDT] ~= regs[TDH] + 1 % num_descriptors
end

-- PHY.

-- Read a PHY register.
function phy_read (phyreg)
   regs[MDIC] = bit.bor(bit.lshift(phyreg, 16), bits({OP1=27,PHYADD0=21}))
   phy_wait_ready()
   local mdic = regs[MDIC]
   -- phy_unlock_semaphore()
   assert(bit.band(mdic, bits({ERROR=30})) == 0)
   return bit.band(mdic, 0xffff)
end

-- Write to a PHY register.
function phy_write (phyreg, value)
   regs[MDIC] = bit.bor(value, bit.lshift(phyreg, 16), bits({OP0=26,PHYADD0=21}))
   phy_wait_ready()
   return bit.band(regs[MDIC], bits({ERROR=30})) == 0
end

function phy_wait_ready ()
   while bit.band(regs[MDIC], bits({READY=28,ERROR=30})) == 0 do
      ffi.C.usleep(2000)
   end
end

function reset_phy ()
   phy_write(0, bits({AutoNeg=12,Duplex=8,RestartAutoNeg=9}))
   ffi.C.usleep(1)
   phy_write(0, bit.bor(bits({RST=15}), phy_read(0)))
end

function force_autoneg ()
   ffi.C.usleep(1)
   regs[POEMB] = bit.bor(regs[POEMB], bits({reautoneg_now=5}))
end

-- Lock and unlock the PHY semaphore. This is used to avoid race
-- conditions between software and hardware both accessing the PHY.

function phy_lock ()
   regs[EXTCNF_CTRL] = bits({MDIO_SW=5})
   while bit.band(regs[EXTCNF_CTRL], bits({MDIO_SW=5})) == 0 do
      ffi.C.usleep(2000)
   end
end

function phy_unlock ()
   regs[EXTCNF_CTRL] = 0
end

function linkup ()
   return bit.band(phy_read(17), bits({CopperLink=10})) ~= 0
end

-- Link control.

function linkup ()
   return bit.band(phy_read(17), bits({CopperLink=10})) ~= 0
end

function enable_phy_loopback ()
   phy_write(0x01, bit.bor(phy_read(0x01), bits({LOOPBACK=14})))
end

function enable_mac_loopback ()
   regs[RCTL] = bit.bor(bits({LBM0=6}, regs[RCTL]))
end

-- Statistics

local stats = {tx_packets=0, tx_bytes=0, tx_errors=0,
	       rx_packets=0, rx_bytes=0, rx_errors=0}

local GPRC  = 0x04074 -- Good Packets Received Count (R)
local GPTC  = 0x04080 -- Good Packets Transmitted Count (R)
-- NOTE: Octet counter registers reset when the high word is read.
local GORCL = 0x04088 -- Good Octets Received Count Low (R)
local GORCH = 0x0408C -- Good Octets Received Count High (R)
local GOTCL = 0x04090 -- Good Octets Transmitted Count Low (R)
local GOTCH = 0x04094 -- Good Octets Transmitted Count High (R)

function print_stats ()
   update_stats()
   print("TX Packets: " .. stats.tx_packets)
   print("RX Packets: " .. stats.rx_packets)
   print("TX Bytes  : " .. stats.rx_bytes)
   print("RX Bytes  : " .. stats.rx_bytes)
end

function update_stats ()
   stats.tx_packets = stats.tx_packets + regs[GPTC]
   stats.rx_packets = stats.rx_packets + regs[GPRC]
   stats.tx_bytes = stats.tx_bytes + regs[GOTCL] + bit.lshift(regs[GOTCH], 32)
   stats.rx_bytes = stats.rx_bytes + regs[GORCL] + bit.lshift(regs[GORCH], 32)
end

-- Return a bitmask using the values of `bitset' as indexes.
-- The keys of bitset are ignored (and can be used as comments).
-- Example: bits({RESET=0,ENABLE=4}, 123) => 1<<0 | 1<<4 | 123
function bits (bitset, basevalue)
   local sum = basevalue or 0
   for _,n in pairs(bitset) do
      sum = bit.bor(sum, bit.lshift(1, n))
   end
   return sum
end

-- Return true if bit number 'n' of 'value' is set.
function bitset (value, n)
   return bit.band(value, bit.lshift(1, n)) ~= 0
end

print("Initializing controller..")
init()

print("UP2? " .. tostring(linkup()))

print_stats()
print "Survived!"

while true do
   print_status()
   print("RDH = " .. regs[RDH] .. " RDT = " .. regs[RDT])
   print("TDH = " .. regs[TDH] .. " TDT = " .. regs[TDT])
   print("writing packet")
   add_txbuf(dma_phys, 123)
   add_rxbuf(dma_phys, 16*1024)
   C.usleep(1000000)
end


