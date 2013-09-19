-- This is a device driver for the Intel 82574L gigabit ethernet controller.
-- The chip is very well documented in Intel's data sheet:
-- http://ark.intel.com/products/32209/Intel-82574L-Gigabit-Ethernet-Controller

local moduleinstance,pciaddress = ...

if pciaddress == nil then
   print("WARNING: intel loaded as normal module; should be device-specific.")
end

module(moduleinstance,package.seeall)

-- Notes:
-- PSP (pad short packets to 64 bytes)

local ffi = require("ffi")
local C = ffi.C
local bit = require("bit")
local pci = require("pci")
local lib = require("lib")
local test = require("test")
local bits, bitset = lib.bits, lib.bitset

require("clib_h")
require("intel_h")

-- FFI definitions for receive and transmit descriptors

-- PCI device ID
local device = pci.device_info(pciaddress).device

-- Return a table for protected (bounds-checked) memory access.
-- 
-- The table can be indexed like a pointer. Index 0 refers to address
-- BASE+OFFSET, index N refers to address BASE+OFFSET+N*sizeof(TYPE),
-- and access to indices >= SIZE is prohibited.
--
-- Examples:
--   local mem =  protected("uint32_t", 0x1000, 0x0, 0x080)
--   mem[0x000] => <word at 0x1000>
--   mem[0x001] => <word at 0x1004>
--   mem[0x07F] => <word at 0x11FC>
--   mem[0x080] => ERROR <address out of bounds: 0x1200>
--   mem._ptr   => cdata<uint32_t *>: 0x1000 (get the raw pointer)
function protected (type, base, offset, size)
   type = ffi.typeof(type)
   local bound = ((size * ffi.sizeof(type)) + 0ULL) / ffi.sizeof(type) 
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

local num_descriptors = 64 * 1024
local buffer_count = 2 * 1024 * 1024

local rxdesc, rxdesc_phy
local txdesc, txdesc_phy
local buffers, buffers_phy

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
local RADV   = 0x0282C / 4 -- Receive Interrupt Absolute Delay Timer (RW)
local RDTR   = 0x02820 / 4 -- Rx Interrupt Delay Timer [Packet Timer] (RW)
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
local ICR    = 0x000C0 / 4 -- Interrupt Cause Register (RW)
local MANC   = 0x05820 / 4 -- Management Control Register (RW / 82571)
local SWSM   = 0x05B50  / 4 -- Software Semaphore (RW / 82571)
local EEMNGCTL = 0x01010 / 4 -- MNG EEPROM Control (RW / 82571)

local regs = ffi.cast("uint32_t *", pci.map_pci_memory(pciaddress, 0))

-- Initialization

function init ()
   reset()
   init_pci()
   init_dma_memory()
   init_link()
   init_statistics()
   init_receive()
   init_transmit()
end

function reset ()
   regs[IMC] = 0xffffffff                 -- Disable interrupts
   regs[CTRL] = bits({FD=0,SLU=6,RST=26}) -- Global reset
   C.usleep(10); assert( not bitset(regs[CTRL],26) )
   regs[IMC] = 0xffffffff                 -- Disable interrupts
end

function init_pci ()
   -- PCI bus mastering has to be enabled for DMA to work.
   pci.set_bus_master(pciaddress, true)
end

function init_dma_memory ()
   --local descriptor_bytes = 1024 * 1024
   --local buffers_bytes = 2 * 1024 * 1024
   rxdesc, rxdesc_phy = memory.dma_alloc(num_descriptors * ffi.sizeof("union rx"))
   txdesc, txdesc_phy = memory.dma_alloc(num_descriptors * ffi.sizeof("union tx"))
   buffers, buffers_phy = memory.dma_alloc(buffer_count * ffi.sizeof("uint8_t"))
   -- Add bounds checking
   rxdesc  = protected("union rx", rxdesc, 0, num_descriptors)
   txdesc  = protected("union tx", txdesc, 0, num_descriptors)
   buffers = protected("uint8_t", buffers, 0, buffer_count)
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
   print("  RADV        = " .. regs[RADV])
   print("PHY status")
   local phystatus, phyext, copperstatus = phy_read(1), phy_read(15), phy_read(17)
   print("  Autonegotiate state    = " .. (bitset(phystatus,5) and 'complete' or 'not complete'))
   print("  Remote fault detection = " .. (bitset(phystatus,4) and 'remote fault detected' or 'no remote fault detected'))
   if device == "0x105e" then
      print("  Copper Link Status     = " .. (bitset(copperstatus,10) and 'copper link is up' or 'copper link is down'))
   elseif device == "0x10d3" then
      print("  Copper Link Status     = " .. (bitset(copperstatus,3) and 'copper link is up' or 'copper link is down'))
   end
   if device == "0x10d3" then
      print("  Speed and duplex resolved = " .. yesno(copperstatus,11))
   end
   physpeed = (({10,100,1000,'(reserved)'})[1+bit.band(bit.rshift(status, 6),3)])
   print("  Speed                  = " .. physpeed .. 'Mb/s')
   if device == "0x105e" then
      print("  Duplex                 = " .. (bitset(copperstatus,9) and 'full-duplex' or 'half-duplex'))
   elseif device == "0x10d3" then
      print("  Duplex                 = " .. (bitset(copperstatus,13) and 'full-duplex' or 'half-duplex'))
   end
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

local rxnext = 0
local rxbuffers = {}
local rdh, rdt = 0, 0

function init_receive ()
   -- Disable RX and program all the registers
   regs[RCTL] = bits({UPE=3, MPE=4, -- Unicast & Multicast promiscuous mode
         LPE=5,        -- Long Packet Enable (over 1522 bytes)
         BSIZE1=17, BSIZE0=16, BSEX=25, -- 4KB buffers
         SECRC=26,      -- Strip Ethernet CRC from packets
         BAM=15         -- Broadcast Accept Mode
      })
   regs[RFCTL] = bits({EXSTEN=15})  -- Extended RX writeback descriptor format

   -- RXDCTL Threshold Settings
   -- e1000e Settings (82563/6/7, 82571/2/3/4/7/8/9, 82583)
   --   pthresh 32 descriptors
   --   hthresh 4 descriptors
   --   wthresh 4 descriptors
   --
   -- igb Settings (82575/6-, 82580-, and I350-based):
   --   pthresh 8 descriptors
   --   hthresh 8 descriptors
   --   wthresh 4 descriptors
   --
   -- ixgbe (82598-, 82599-, and X540 10Gig)
   --   pthresh 32 descriptors
   --   hthresh 4 descriptors
   --   wthresh 8 descriptors
   --
   -- Values for 82571 and 82574 controllers (same as e1000e driver).
   regs[RXDCTL] = bits({GRAN=24, PTHRESH5=5, HTHRESH2=10, WTHRESH2=18})

   regs[RXCSUM] = 0                 -- Disable checksum offload - not needed

   -- e1000e Settings (82563/6/7, 82571/2/3/4/7/8/9, 82583)
   --   RDTR 0x20
   --   RADV 0x20
   -- We should probably switch to using ITR instead per specsheet
   regs[RDTR] = 0x20
   regs[RADV] = 0x20

   regs[RDLEN] = num_descriptors * ffi.sizeof("union rx")
   regs[RDBAL] = rxdesc_phy % (2^32)
   regs[RDBAH] = rxdesc_phy / (2^32)
   regs[RDH] = 0
   regs[RDT] = 0
   rxnext = 0
   -- Enable RX
   regs[RCTL] = bit.bor(regs[RCTL], bits{EN=1})
   rdt = 0
end

-- Enqueue a receive descriptor to receive a packet.
function add_receive_buffer (buf)
   -- NOTE: RDT points to the next unused descriptor
   -- FIXME: size
   rxdesc[rdt].data.address = buf.phy
   rxdesc[rdt].data.dd = 0
   rxbuffers[rdt] = buf
   rdt = (rdt + 1) % num_descriptors
   buffer.ref(buf)
   return true
end

function sync_receive ()
   regs[RDT] = rdt
   rdh = regs[RDH]
end

function can_add_receive_buffer ()
   return not rx_full()
end

function can_receive ()
   return rdh ~= rxnext
end

function ring_pending(head, tail)
   if head == tail then return 0 end
   if head <  tail then return tail - head
   else                 return num_descriptors + tail - head end
end

function rx_full ()
   return rdh == (rdt + 1) % num_descriptors
end

function rx_empty ()
   return rdh == rdt
end

function rx_pending ()
   return ring_pending(rdh, rdt)
end

function rx_available ()
   return num_descriptors - rx_pending() - 1
end

function rx_load ()
   return rx_pending() / num_descriptors
end

function receive ()
   if rdh ~= rxnext then
      local buf = rxbuffers[rxnext]
      buf.size = rxdesc[rxnext].length
      rxnext = (rxnext + 1) % num_descriptors
      buffer.deref(buf)
      return buf
   end
end

function ack ()
end

-- Transmit functionality

-- Locally cached copy of the Transmit Descriptor Tail (TDT) register.
-- Updates are kept locally here until flush_tx() is called.
-- That's because updating the hardware register is relatively expensive.
local tdh, tdt = 0, 0

function init_transmit ()
   regs[TCTL] = 0x3103f0f8 -- Disable 'transmit enable'
   regs[TIPG] = 0x00602006 -- Suggested value in data sheet
   init_transmit_ring()

   -- Enable transmit
   regs[TDH] = 0
   regs[TDT] = 0

   -- TXDCTL Threshold Settings
   -- e1000e Settings (82563/6/7, 82571/2/3/4/7/8/9, 82583)
   --   pthresh 31 descriptors
   --   hthresh 1 descriptors
   --   wthresh 1 descriptors (comment from e1000.h header file):
   --     in the case of WTHRESH, it appears at least the 82571/2
   --     hardware writes back 4 descriptors when WTHRESH=5, and 3
   --     descriptors when WTHRESH=4, so a setting of 5 gives the
   --     most efficient bus utilization but to avoid possible Tx
   --     stalls, set it to 1.
   --   https://patchwork.kernel.org/patch/1614951/
   --
   -- igb Settings (82575/6-, 82580-, and I350-based):
   --   pthresh 8 descriptors
   --   hthresh 1 descriptors
   --   wthresh 16 descriptors
   --
   -- ixgbe (82598-, 82599-, and X540 10Gig)
   --   pthresh 32 descriptors
   --   hthresh 1 descriptors
   --   wthresh 8 descriptors (or 1 if ITR is disabled)
   --
   -- Use same as e1000e for now
   regs[TXDCTL] = bits({GRAN=24,
                        PTHRESH0=0, PTHRESH1=1, PTHRESH2=2, PTHRESH3=3, PTHRESH4=4,
                        HTHRESH0=8,
                        WTHRESH0=16})

   regs[TCTL] = 0x3103f0fa -- Enable 'transmit enable'
   tdt = 0
end

function init_transmit_ring ()
   regs[TDBAL] = txdesc_phy % (2^32)
   regs[TDBAH] = txdesc_phy / (2^32)
   -- Hardware requires the value to be 128-byte aligned
   assert( num_descriptors * ffi.sizeof("union tx") % 128 == 0 )
   regs[TDLEN] = num_descriptors * ffi.sizeof("union tx")
end

-- Flags for transmit descriptors.
local txdesc_flags = bits({dtype=20, eop=24, ifcs=25, dext=29})

-- API function.
function transmit (buf)
   txdesc[tdt].data.address = buf.phy
   txdesc[tdt].data.options = bit.bor(buf.size, txdesc_flags)
   tdt = (tdt + 1) % num_descriptors
   buffer.ref(buf)
end

-- API function.
function sync_transmit ()
   C.full_memory_barrier()
   regs[TDT] = tdt
   tdh = regs[TDH]
   -- FIXME deref buffers that have been transmitted
end

function add_txbuf_tso (address, size, mss, ctx)
   ctx = ffi.cast("struct tx_context_desc *", txdesc + tdt)
   ctx.tucse = 0
   ctx.tucso = 0
   ctx.tucss = 0
   ctx.ipcse = 0
   ctx.ipcso = 0
   ctx.ipcss = 0
   ctx.mss = 1440
   ctx.hdrlen = 0
   ctx.sta = 0
   ctx.tucmd = 0
   ctx.dtype = 0
   ctx.paylen = 0
end

function can_transmit () return not tx_full() end

function can_reclaim_buffer ()
   -- FIXME
   return false
end

function tx_full  () return tx_pending() == num_descriptors - 1 end
function tx_empty () return tx_pending() == 0 end

function tx_pending ()
   return ring_pending(tdh, tdt)
end

function tx_available ()
   return num_descriptors - tx_pending() - 1
end

function tx_load ()
   return tx_pending() / num_descriptors
end

--[[

   EEPROM/PHY Firmware/Software Synchronization (82571EB)

   For the 82571EB, there are two semaphores located in the Software
   Semaphore (SWSM) register (see Section 13.8.17).

   * Bit0 (SWSSMBI) is the software/software semaphore. This bit is
     needed in multi-process environments to prevent software running
     on one port from interferring with software on another the other
     port.

   * Bit1SWSSWESMBI is the software/firmware semaphore. This is
     always needed when accessing the PHY or EEPROM (reads, writes, or
     resets). This prevents the firmware and software from accessing
     the PHY and or EEPROM at the same time.

   If resetting the PHY, the software/software semaphore should not be
   released until 1 ms after CFG_DONE (bit 18) is set in the MNG
   EEPROM Control Register (EEMNGCTL) register (see Section
   13.3.26). The software/firmware semaphore should be released
   approximately 10 ms after the PHY reset is deasserted before
   polling of CFG_DONE is attempted. For details on how to reset the
   PHY see section Section 14.9.

   For EEPROM or PHY register access:

   1. Software reads SWSSMBI. If SWSSMBI is 0b, then it owns the
      software/software semaphore and can continue. If SWSSMBI is
      1b, then some other software already has the semaphore.
   2. Software writes 1b to the SWSSWESMBI bit and then reads it. If
      the value is 1b, then software owns the software/firmware
      semaphore and can continue; otherwise, firmware has the
      semaphore.  
      Software can now access the EEPROM and/or PHY.
   3. Release the software/firmware semaphore by clearing SWSSWESMBI.
   4. Release the software/software semaphore by clearing SWSSMBI.
--]]

-- Read a PHY register.
function phy_read (phyreg)
   phy_lock()
   regs[MDIC] = bit.bor(bit.lshift(phyreg, 16), bits({OP1=27,PHYADD0=21}))
   phy_wait_ready()
   local mdic = regs[MDIC]
   phy_unlock()
   assert(bit.band(mdic, bits({ERROR=30})) == 0)
   return bit.band(mdic, 0xffff)
end

-- Write to a PHY register.
function phy_write (phyreg, value)
   phy_lock()
   regs[MDIC] = bit.bor(value, bit.lshift(phyreg, 16), bits({OP0=26,PHYADD0=21}))
   phy_wait_ready()
   local mdic = regs[MDIC]
   phy_unlock()
   return bit.band(mdic, bits({ERROR=30})) == 0
end

function phy_wait_ready ()
   -- Calling function should call this in between calls to phy_lock/unlock
   while bit.band(regs[MDIC], bits({READY=28,ERROR=30})) == 0 do
      ffi.C.usleep(2000)
   end
end

--[[
   PHY Reset (82571EB/82572EI):
   To reset the PHY using software:
   
   1. Obtain the Software/Software semaphore (SWSSMBI - 05B50h; bit
      0). This is needed for multi-threaded environments.
   2. Read (MANC.BLK_Phy_Rst_On_IDE - 05820h; bit 18) and then wait
      until it becomes 0b.
   3. Obtain the Software/Firmware semaphore (SWSSWESMBI - 05B50h;
      bit 1).
   4. Drive PHY reset (CTRL.PHY_RST at offset 0000h [bit 31], write
      1b, wait 100 us, and then write 0b).
   5. Release the Software/Firmware semaphore (SWSSWESMBI - 05B50h;
      bit 1).
   6. Wait for the CFG_DONE (EEMNGCTL.CFG_DONE at offset 1010h [bit
      18] becomes 1b).
   7. Wait for a 1 ms delay. The PHY should now be ready. If
      additional access to the PHY is necessary (reads or writes) the
      Software/Firmware semaphore (SWSSWESMBI - 05B50h; bit 1) must be
      re-acquired and then released once done.
   8. Release the Software/Software semaphore (SWSSMBI - 05B50h; bit
      0). This is needed for multi-threaded environments.
--]]

function reset_phy ()
   -- Step 1
   phy_lock({sw=true})

   if device == "0x105e" then
      -- Step 2
      while bit.band(regs[MANC], bits({Blk_Phy_Rst_On_IDE=18})) ~= 0 do
         ffi.C.usleep(2000)
      end

      -- Step 3
      phy_lock({fw=true})

      -- Step 4
      regs[CTRL] = bit.bor(regs[CTRL], bits({PHY_RST=31}))
      ffi.C.usleep(100)
      regs[CTRL] = bit.band(regs[CTRL], bit.bnot(bits({PHY_RST=31})))

      -- Step 5
      phy_unlock({fw=true})

      -- Step 6
      while bit.band(regs[EEMNGCTL], bits({CFG_DONE=18})) == 0 do
         ffi.C.usleep(2000)
      end
   end

   -- Step 7
   -- Must unlock software lock here as the next phy_write's 
   -- will obtain both locks as part of any write or read.
   phy_unlock({sw=true}) 

   ffi.C.usleep(1000)
   phy_write(0, bits({AutoNeg=12,Duplex=8,RestartAutoNeg=9}))
   ffi.C.usleep(1)

   -- I'm not sure if this next line is required to reset the PHY
   -- in the 82571 as the data sheet doesn't even mention the need
   -- to set the RST in the PHY.PCTRL register to reset the PHY
   -- (see steps above). However, in testing this does not seem to
   -- have any negative effects.
   phy_write(0, bit.bor(bits({RST=15}), phy_read(0)))
end

function force_autoneg ()
   ffi.C.usleep(1)
   regs[POEMB] = bit.bor(regs[POEMB], bits({reautoneg_now=5}))
end

-- Lock and unlock the PHY semaphore. This is used to avoid race
-- conditions between software and hardware both accessing the PHY.

-- Obtain lock for PHY access. If no options are passed, obtain
-- both a software lock and a firmware lock. Software lock is
-- obtained first. A software only lock can be requested by passing
-- {sw=true}, while a firmware only lock can be requested by
-- passing {fw=true}.
function phy_lock (options)
   options = options or {sw=true, fw=true}

   if options.sw then
      -- Obtain the software/software semaphore. We need to do so
      -- with the 82571 as it is a two-port card and another driver
      -- could be trying to configure the controller at the same
      -- time. It's not as important for the 82574 because it is
      -- single port, but it's still a good idea to play it safe.
      while bit.band(regs[SWSM], bits({SMBI=0})) ~= 0 do
         ffi.C.usleep(2000)
      end
   end

   if options.fw then
      -- Firmware/software locking is different between cards
      if device == "0x105e" then
         regs[SWSM] = bit.bor(regs[SWSM], bits({SWESMBI=1}))
         while bit.band(regs[SWSM], bits({SWESMBI=1})) == 0 do
            ffi.C.usleep(2000)
            regs[SWSM] = bit.bor(regs[SWSM], bits({SWESMBI=1}))
         end
      elseif device == "0x10d3" then
         regs[EXTCNF_CTRL] = bits({MDIO_SW=5})
         while bit.band(regs[EXTCNF_CTRL], bits({MDIO_SW=5})) == 0 do
            ffi.C.usleep(2000)
         end
      end
   end
end

function phy_unlock (options)
   options = options or {sw=true, fw=true}

   if options.fw then
      -- Firmware/software unlocking is different between cards
      if device == "0x105e" then
         regs[SWSM] = bit.band(regs[SWSM], bit.bnot(bits({SWESMBI=1})))
      elseif device == "0x10d3" then         
         regs[EXTCNF_CTRL] = 0
      end
   end

   if options.sw then
      regs[SWSM] = bit.band(regs[SWSM], bit.bnot(bits({SMBI=0})))
   end
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

local statistics_regs = {
   {"CRCERRS",  0x04000, "CRC Error Count"},
   {"ALGNERRC", 0x04004, "Alignment Error Count"},
   {"RXERRC",   0x0400C, "RX Error Count"},
   {"MPC",      0x04010, "Missed Packets Count"},
   {"SCC",      0x04014, "Single Collision Count"},
   {"ECOL",     0x04018, "Excessive Collision Count"},
   {"MCC",      0x0401C, "Multiple Collision Count"},
   {"LATECOL",  0x04020, "Late Collisions Count"},
   {"COLC",     0x04028, "Collision Count"},
   {"DC",       0x04030, "Defer Count"},
   {"TNCRS",    0x04034, "Transmit with No CRS"},
   {"CEXTERR",  0x0403C, "Carrier Extension Error Count"},
   {"RLEC",     0x04040, "Receive Length Error Count"},
   {"XONRXC",   0x04048, "XON Received Count"},
   {"XONTXC",   0x0403C, "XON Transmitted Count"},
   {"XOFFRXC",  0x04050, "XOFF Received Count"},
   {"XOFFTXC",  0x04054, "XOFF Transmitted Count"},
   {"FCRUC",    0x04058, "FC Received Unsupported Count"},
   {"PRC64",    0x0405C, "Packets Received [64 Bytes] Count"},
   {"PRC127",   0x04060, "Packets Received [65-127 Bytes] Count"},
   {"PRC255",   0x04064, "Packets Received [128-255 Bytes] Count"},
   {"PRC511",   0x04068, "Packets Received [256-511 Bytes] Count"},
   {"PRC1023",  0x0406C, "Packets Received [512-1023 Bytes] Count"},
   {"PRC1522",  0x04070, "Packets Received [1024 to Max Bytes] Count"},
   {"GPRC",     0x04074, "Good Packets Received Count"},
   {"BPRC",     0x04078, "Broadcast Packets Received Count"},
   {"MPRC",     0x0407C, "Multicast Packets Received Count"},
   {"GPTC",     0x04080, "Good Packets Transmitted Count"},
   {"GORCL",    0x04088, "Good Octets Received Count"},
   {"GORCH",    0x0408C, "Good Octets Received Count"},
   {"GOTCL",    0x04090, "Good Octets Transmitted Count"},
   {"GOTCH",    0x04094, "Good Octets Transmitted Count"},
   {"RNBC",     0x040A0, "Receive No Buffers Count"},
   {"RUC",      0x040A4, "Receive Undersize Count"},
   {"RFC",      0x040A8, "Receive Fragment Count"},
   {"ROC",      0x040AC, "Receive Oversize Count"},
   {"RJC",      0x040B0, "Receive Jabber Count"},
   {"MNGPRC",   0x040B4, "Management Packets Received Count"},
   {"MPDC",     0x040B8, "Management Packets Dropped Count"},
   {"MPTC",     0x040BC, "Management Packets Transmitted Count"},
   {"TORL",     0x040C0, "Total Octets Received (Low)"},
   {"TORH",     0x040C4, "Total Octets Received (High)"},
   {"TOTL",     0x040C8, "Total Octets Transmitted (Low)"},
   {"TOTH",     0x040CC, "Total Octets Transmitted (High)"},
   {"TPR",      0x040D0, "Total Packets Received"},
   {"TPT",      0x040D4, "Total Packets Transmitted"},
   {"PTC64",    0x040D8, "Packets Transmitted [64 Bytes] Count"},
   {"PTC127",   0x040DC, "Packets Transmitted [65-127 Bytes] Count"},
   {"PTC255",   0x040E0, "Packets Transmitted [128-255 Bytes] Count"},
   {"PTC511",   0x040E4, "Packets Transmitted [256-511 Bytes] Count"},
   {"PTC1023",  0x040E8, "Packets Transmitted [512-1023 Bytes] Count"},
   {"PTC1522",  0x040EC, "Packets Transmitted [Greater than 1024 Bytes] Count"},
   {"MPTC",     0x040F0, "Multicast Packets Transmitted Count"},
   {"BPTC",     0x040F4, "Broadcast Packets Transmitted Count"},
   {"TSCTC",    0x040F8, "TCP Segmentation Context Transmitted Count"},
   {"TSCTFC",   0x040FC, "TCP Segmentation Context Transmit Fail Count"},
   {"IAC",      0x04100, "Interrupt Assertion Count"}
  }

stats = {}

function update_stats ()
   for _,reg in ipairs(statistics_regs) do
      name, offset, desc = reg[1], reg[2], reg[3]
      stats[name] = (stats[name] or 0) + regs[offset/4]
   end
end

function reset_stats ()
   stats = {}
end

function print_stats ()
   print("Statistics for PCI device " .. pciaddress .. ":")
   for _,reg in ipairs(statistics_regs) do
      name, desc = reg[1], reg[3]
      if stats[name] > 0 then
         print(("%20s %-10s %s"):format(lib.comma_value(stats[name]), name, desc))
      end
   end
end

-- Self-test diagnostics

function selftest (options)
   options = options or {}
   io.write("intel selftest: pciaddr="..pciaddress)
   for key,value in pairs(options) do
      io.write(" "..key.."="..tostring(value))
   end
   print()
   options.device = getfenv()
   init()
   print_status()
   if not options.noloopback then
      enable_mac_loopback()
   end
   if not options.nolinkup then
      test.waitfor("linkup", linkup, 20, 250000)
   end
   require("port").selftest(options)
   update_stats()
   print_stats()
   -- print_status()
end

-- Test that TCP Segmentation Optimization (TSO) works.
function selftest_tso (options)
   print "selftest: TCP Segmentation Offload (TSO)"
   options = options or {}
   local size = options.size or 4096
   local mss  = options.mss  or 1500
   local txtcp = 0 -- Total number of TCP packets sent
   local txeth = 0 -- Expected number of ethernet packets sent

   C.usleep(100000) -- Wait for old traffic from previous tests to die out
   update_stats()
   local txhardware_start = stats.GPTC

   -- Transmit a packet with TSO and count expected ethernet transmits.
   add_tso_test_buffer(size, mss)
   txeth = txeth + math.ceil(size / mss)
   
   -- Wait a safe time and check hardware count
   C.usleep(100000) -- wait for receive
   update_stats()
   local txhardware = txhardware_start - stats.GPTC

   -- Check results
   print("size", "mss", "txtcp", "txeth", "txhw")
   print(size, mss, txtcp, txeth, txhardware)
   if txeth ~= txhardware then
      print("Expected "..txeth.." packet(s) transmitted but measured "..txhardware)
   end
end

function add_tso_test_buffer (size)
   -- Construct a TCP packet of 'size' total bytes and transmit with TSO.
end

