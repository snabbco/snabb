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

local CTRL   = 0x00000 -- Device Control Register (RW)
local STATUS = 0x00008
local PBA    = 0x01000 -- Packet Buffer Allocation
local IMC    = 0x000D8 -- Interrupt Mask Clear (W)
local RCTL   = 0x00100 -- Receive Control Register (RW)
local RFCTL  = 0x05008 -- Receive Filter Control Register (RW)
local RXDCTL = 0x02828 -- Receive Descriptor Control (RW)
local RXCSUM = 0x05000 -- Receive Checksum Control (RW)
local RDBAL  = 0x02800 -- Receive Descriptor Base Address Low (RW)
local RDBAH  = 0x02804 -- Receive Descriptor Base Address High (RW)
local RDLEN  = 0x02808 -- Receive Descriptor Length (RW)
local RDH    = 0x02810 -- Receive Descriptor Head (RW)
local RDT    = 0x02818 -- Receive Descriptor Tail (RW)
local TXDCTL = 0x03828 -- Transmit Descriptor Control (RW)
local TCTL   = 0x00400 -- Transmit Control Register (RW)
local TIPG   = 0x00410 -- Transmit Inter-Packet Gap (RW)
local TDBAL  = 0x03800 -- Transmit Descriptor Base Address Low (RW)
local TDBAH  = 0x03804 -- Transmit Descriptor Base Address High (RW)
local TDLEN  = 0x03808 -- Transmit Descriptor Length (RW)
local TDH    = 0x03810 -- Transmit Descriptor Head (RW)
local TDT    = 0x03818 -- Transmit Desciprotr Tail (RW)

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
   rxdesc  = protected("union rx", dma_virt, offset_rxdesc, 0x100000)
   txdesc  = protected("union tx", dma_virt, offset_txdesc, 0x100000)
   buffers = protected("uint8_t", dma_virt, offset_buffers, 0xe00000)
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
   regs[RDBAH] = bit.rshift(dma_phys + offset_rxdesc, 32)
   regs[RDH] = 0
   regs[RDT] = 0
   -- Enable RX
   regs[RCTL] = bit.bor(regs[RCTL], bits{EN=1})
end

ffi.cdef[[
// TX Extended Data Descriptor written by software.
struct tx_desc {
   uint64_t address;
   unsigned int vlan:16;
   unsigned int popts:8;
   unsigned int extcmd:4;
   unsigned int sta:4;
   unsigned int dcmd:8;
   unsigned int dtype:4;
   unsigned int dtalen:20;
} __attribute__((packed));

union tx {
   struct tx_desc desc;
   // XXX context descriptor
};
]]

function init_transmit ()
   regs[TXDCTL] = bits({GRAN=24, WTHRESH0=16})
   regs[TCTL] = bit.bor(bits({PSP=3}),
			bit.lshift(0x3F, 12)) -- COLD value for full duplex
   regs[TIPG] = 0x00602006 -- Suggested value in data sheet
   regs[TDBAL] = bit.band(dma_phys + offset_txdesc, 0xffffffff)
   regs[TDBAH] = bit.rshift(dma_phys + offset_txdesc, 32)
   init_transmit_ring()
   -- Enable transmit
   regs[TCTL] = bit.bor(regs[TCTL], bits({EN=1}))
end

function init_transmit_ring ()
   -- Hardware requires the value to be 128-byte aligned
   assert( num_descriptors * ffi.sizeof("union tx") % 128 == 0 )
   regs[TDLEN] = num_descriptors * ffi.sizeof("union tx")
   regs[TDH] = 0
   regs[TDT] = 0
end

function enable_mac_loopback ()
   regs[RCTL] = bits({LBM0=6}, regs[RCTL])
   print(bit.tohex(regs[RCTL]))
end

-- Enqueue a receive descriptor to receive a packet.
function add_rxbuf (address, size)
   -- NOTE: RDT points to the next unused descriptor
   local index = regs[RDT]
   rxdesc[rdt].desc.address = address
   rxdesc[rdt].desc.dd = 0
   regs[RDT] = index + 1 % num_descriptors
   return true
end

function is_rx_descriptor_available ()
   return regs[RDT] ~= regs[RDH] + 1 % num_descriptors
end

-- Enqueue a transmit descriptor to send a packet.
function add_txbuf (address, size)
   local index = regs[TDT]
   txdesc[index].desc.address = address
   txdesc[index].desc.dtalen = size
   txdesc[index].desc.dtype  = 0x1
   -- XXX I don't like calling bits() on the transmit path.
   txdesc[index].desc.dcmd   = bits({EOP=0, DEXT=5})
   txdesc[index].desc.dtalen = size
   regs[TDT] = index + 1 % num_descriptors
   print("IDX = " .. (index + 1 % num_descriptors))
   print(regs[TDT])
end

-- 
function is_tx_descriptor_available ()
   return regs[TDT] ~= regs[TDH] + 1 % num_descriptors
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

local mem = snabb.map_physical_ram(0x10000000, 0x11000000, true)

init()
init_receive()
enable_mac_loopback()

print("TX available: " .. tostring(is_tx_descriptor_available()))
for i = 0, 100, 1 do
   add_txbuf(dma_phys, 123)

end
C.usleep(100000)

print("TDH = " .. regs[TDH])
print("TDT = " .. regs[TDT])


print_stats()

print "Survived!"

