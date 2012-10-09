-- intel.lua -- Intel 82574L driver with Linux integration
-- Copyright 2012 Snabb GmbH. See the file LICENSE.

-- This is a device driver for the Intel 82574L gigabit ethernet controller.
-- The chip is very well documented in Intel's data sheet:
-- http://ark.intel.com/products/32209/Intel-82574L-Gigabit-Ethernet-Controller

module(...,package.seeall)

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
function protected (type, base, offset, size)
   local bound = size / ffi.sizeof(type)
   local ptr = ffi.cast(type.."*", ffi.cast("uint8_t*", base) + offset)
   local table = { ptr = ptr }
   setmetatable(
      table,
      { __index    = function (table, key)
			assert(key >= 0 and key < bound)
			return ptr[key]
		     end,
	__newindex = function (table, key, value)
			assert(key >= 0 and key < bound)
			ptr[key] = value
		     end })
   return table
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

local CTRL   = 0x00000 -- Device Control Register (RW)
local STATUS = 0x00008
local PBA    = 0x01000 -- Packet Buffer Allocation
local IMC    = 0x000D8 -- Interrupt Mask Clear (W)
local RCTL   = 0x00100 -- Receive Control Register (RW)
local RFCTL  = 0x05008 -- Receive Filter Control Register (RW)

local regs = ffi.cast("uint32_t *", map_pci_memory("0000:00:04.0", 0))          
print(string.format("CTRL   = 0x%x", regs[CTRL]))
print(string.format("STATUS = 0x%x", regs[STATUS]))
print(string.format("PBA    = 0x%x", regs[PBA]))

-- Initialization

function init ()
   reset()
   init_dma_memory()
   init_link()
   init_statistics()
   init_receive()
   init_transmit()
end

function init_dma_memory ()
   dma_virt = snabb.map_physical_ram(dma_start, dma_end, true)
   C.memset(dma_virt, 0, dma_end - dma_start)
   rxdesc = protected("union rx", dma_virt, offset_rxdesc, 0x1000000)
   rxbuffer = protected("uint8_t", dma_virt, offset_rxbuf, 0xf000000)
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

function init_link ()
   -- Currently using autoneg for everything, as recommended in data sheet.
   -- I have a feeling that autoneg speed + forced FDX is most practical.
end

function init_statistics ()
   -- Statistics registers initialize themselves within 1ms of a reset.
   C.usleep(1000)
end

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
   for i = 0, num_descriptors-1, 1 do
      rxdesc[i].desc.address = 0
      rxdesc[i].desc.address = dma_phys + offset_rxbuf + i*buffer_size
      rxdesc[i].desc.dd      = 0
   end
   regs[RCTL] = bits({EN=1,         -- Enable packet receive
		      UPE=3, MPE=4, -- Unicast & Multicast promiscuous mode
		      LPE=5,        -- Long Packet Enable (XXX what is that?)
		      BSIZE1=16, BSEX=25, -- 16KB buffers
		      SECRC=26      -- Strip Ethernet CRC from packets
      })
   regs[RFCTL] = bits({EXSTEN=15})  -- Extended RX writeback descriptor format
end

function init_transmit ()
end

function enable_mac_loopback ()
   regs[RCTL] = bits({LBM0=6}, regs[RCTL])
   print(bit.tohex(regs[RCTL]))
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

local mem = snabb.map_physical_ram(0x10000000, 0x11000000, true)

init()
init_receive()
enable_mac_loopback()

print "Survived!"

