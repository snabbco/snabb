-- intel.lua -- Intel 82574L driver with Linux integration
-- Copyright 2012 Snabb GmbH. See the file LICENSE.

-- This is a device driver for the Intel 82574L gigabit ethernet controller.
-- The chip is very well documented in Intel's data sheet:
-- http://ark.intel.com/products/32209/Intel-82574L-Gigabit-Ethernet-Controller

module(...,package.seeall)

-- Notes:
-- PSP (pad short packets to 64 bytes)

local ffi = require("ffi")
local C = ffi.C
local bit = require("bit")
local pci = require("pci")
local lib = require("lib")
local bits, bitset = lib.bits, lib.bitset

require("clib_h")
require("snabb_h")

local dma_start = 0x10000000
local dma_end   = 0x11000000

function new (pciaddress)

   -- Method dictionary for Intel NIC objects.
   local M = {}

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

   local pci_config_fd = nil

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
   local TARC   = 0x03840 / 4 -- Transmit Arbitration Count - TARC (RW)
   local MDIC   = 0x00020 / 4 -- MDI Control Register (RW)
   local EXTCNF_CTRL = 0x00F00 / 4 -- Extended Configuration Control (RW)
   local POEMB  = 0x00F10 / 4 -- PHY OEM Bits Register (RW)
   local ICR    = 0x00C00 / 4 -- Interrupt Cause Register (RW)

   local regs = ffi.cast("uint32_t *", pci.map_pci_memory(pciaddress, 0))

   -- Initialization

   function M.init ()
      reset()
      init_pci()
      init_dma_memory()
      init_link()
      init_statistics()
      init_receive()
      init_transmit()
   end

   function reset ()
      regs[IMC] = 0			  -- Disable interrupts
      regs[CTRL] = bits({FD=0,SLU=6,RST=26}) -- Global reset
      C.usleep(10); assert( not bitset(regs[CTRL],26) )
      regs[IMC] = 0		          -- Disable interrupts
   end

   function init_pci ()
      -- PCI bus mastering has to be enabled for DMA to work.
      pci_config_fd = pci.open_config(pciaddress)
      pci.set_bus_master(pci_config_fd, true)
   end

   function init_dma_memory ()
      dma_virt = C.map_physical_ram(dma_start, dma_end, true)
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

   function M.print_status ()
      local status, tctl, rctl = regs[STATUS], regs[TCTL], regs[RCTL]
      print("MAC status")
      print("  STATUS      = " .. bit.tohex(status))
      print("  Full Duplex = " .. yesno(status, 0))
      print("  Link Up     = " .. yesno(status, 1))
      print("  PHYRA       = " .. yesno(status, 10))
      speed = (({10,100,1000,1000})[1+bit.band(bit.rshift(status, 6),3)])
      print("  Speed       = " .. speed .. ' Mb/s')
      print("Transmit status")
      print("  TCTL        = " .. bit.tohex(tctl))
      print("  TXDCTL      = " .. bit.tohex(regs[TXDCTL]))
      print("  TX Enable   = " .. yesno(tctl, 1))
      print("  TDH         = " .. regs[TDH])
      print("  TDT         = " .. regs[TDT])
      print("  TDBAH       = " .. bit.tohex(regs[TDBAH]))
      print("  TDBAL       = " .. bit.tohex(regs[TDBAL]))
      print("  TDLEN       = " .. regs[TDLEN])
      print("  TARC        = " .. bit.tohex(regs[TARC]))
      print("  TIPG        = " .. bit.tohex(regs[TIPG]))
      print("Receive status")
      print("  RCTL        = " .. bit.tohex(rctl))
      print("  RXDCTL      = " .. bit.tohex(regs[RXDCTL]))
      print("  RX Enable   = " .. yesno(rctl, 1))
      print("  RX Loopback = " .. yesno(rctl, 6))
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
      print("  Speed and duplex resolved = " .. yesno(copperstatus,11))
      physpeed = (({10,100,1000,'(reserved)'})[1+bit.band(bit.rshift(status, 6),3)])
      print("  Speed                  = " .. physpeed .. 'Mb/s')
      print("  Duplex                 = " .. (bitset(copperstatus,13) and 'full-duplex' or 'half-duplex'))
      local autoneg, autoneg1G = phy_read(4), phy_read(9)
      print("  Advertise 1000 Mb/s FD = " .. yesno(autoneg1G,9))
      print("  Advertise 1000 Mb/s HD = " .. yesno(autoneg1G,8))
      print("  Advertise  100 Mb/s FD = " .. yesno(autoneg,8))
      print("  Advertise  100 Mb/s HD = " .. yesno(autoneg,7))
      print("  Advertise   10 Mb/s FD = " .. yesno(autoneg,6))
      print("  Advertise   10 Mb/s HD = " .. yesno(autoneg,5))
      local partner, partner1G = phy_read(5), phy_read(10)
      print("  Partner   1000 Mb/s FD = " .. yesno(partner1G,11)) -- reg 10
      print("  Partner   1000 Mb/s HD = " .. yesno(partner1G,10))
      print("  Partner    100 Mb/s FD = " .. yesno(partner,8))
      print("  Partner    100 Mb/s HD = " .. yesno(partner,7))
      print("  Partner     10 Mb/s FD = " .. yesno(partner,6))
      print("  Partner     10 Mb/s HD = " .. yesno(partner,5))
      --   print("Power state              = D"..bit.band(regs[PMCSR],3))
   end

   function yesno (value, bit)
      return bitset(value, bit) and 'yes' or 'no'
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
      regs[RDH] = 0
      regs[RDT] = 0
      -- Enable RX
      regs[RCTL] = bit.bor(regs[RCTL], bits{EN=1})
   end

   -- Enqueue a receive descriptor to receive a packet.
   function M.add_rxbuf (address, size)
      -- NOTE: RDT points to the next unused descriptor
      local index = regs[RDT]
      rxdesc[index].desc.address = address
      rxdesc[index].desc.dd = 0
      regs[RDT] = (index + 1) % num_descriptors
      return true
   end

   function M.is_rx_descriptor_available ()
      return regs[RDT] ~= (regs[RDH] + 1) % num_descriptors
   end

   -- Transmit functionality

   ffi.cdef[[
	 // TX Extended Data Descriptor written by software.
	 struct tx_desc {
	    uint64_t address;
	    uint64_t options;
	 } __attribute__((packed));

	 union tx {
	    struct tx_desc desc;
	    // XXX context descriptor
	 };
   ]]

   function init_transmit ()
      regs[TCTL]        = 0x3103f0f8
      regs[TXDCTL]      = 0x01410000
      regs[TIPG] = 0x00602006 -- Suggested value in data sheet
      init_transmit_ring()
      -- Enable transmit
      regs[TDH] = 0
      regs[TDT] = 0
      regs[TXDCTL]      = 0x01410000
      regs[TCTL]        = 0x3103f0fa

   end

   function init_transmit_ring ()
      regs[TDBAL] = bit.band(dma_phys + offset_txdesc, 0xffffffff)
      regs[TDBAH] = 0
      -- Hardware requires the value to be 128-byte aligned
      assert( num_descriptors * ffi.sizeof("union tx") % 128 == 0 )
      regs[TDLEN] = num_descriptors * ffi.sizeof("union tx")
   end

   -- Enqueue a transmit descriptor to send a packet.
   function M.add_txbuf (address, size)
      local index = regs[TDT]
      txdesc[index].desc.address = address
      txdesc[index].desc.options = bit.bor(size, bits({dtype=20, eop=24, ifcs=25, dext=29}))
      regs[TDT] = (index + 1) % num_descriptors
   end

   function M.add_txbuf_tso (address, size)
      
   end

   -- 
   function M.is_tx_descriptor_available ()
      return regs[TDT] ~= (regs[TDH] + 1) % num_descriptors
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

   -- Link control.

   function M.linkup ()
      return bit.band(phy_read(17), bits({CopperLink=10})) ~= 0
   end

   function M.enable_phy_loopback ()
      phy_write(0x01, bit.bor(phy_read(0x01), bits({LOOPBACK=14})))
   end

   function M.enable_mac_loopback ()
      regs[RCTL] = bit.bor(bits({LBM0=6}, regs[RCTL]))
   end

   -- Statistics

   local stats = {tx_packets=0, tx_bytes=0, tx_errors=0,
		  rx_packets=0, rx_bytes=0, rx_errors=0}

   local GPRC  = 0x04074/4 -- Good Packets Received Count (R)
   local GPTC  = 0x04080/4 -- Good Packets Transmitted Count (R)
   -- NOTE: Octet counter registers reset when the high word is read.
   local GORCL = 0x04088/4 -- Good Octets Received Count Low (R)
   local GORCH = 0x0408C/4 -- Good Octets Received Count High (R)
   local GOTCL = 0x04090/4 -- Good Octets Transmitted Count Low (R)
   local GOTCH = 0x04094/4 -- Good Octets Transmitted Count High (R)

   function M.print_stats ()
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

   return M
end

