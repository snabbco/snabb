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
   local offset_buffers  = 0x00000000 -- 14MB packet buffers
   local offset_txdesc   = 0x00e00000 --  1MB TX descriptors
   local offset_rxdesc   = 0x00f00000 --  1MB RX descriptors

   local num_descriptors = 32 * 1024
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
      regs[IMC] = 0                       -- Disable interrupts
      regs[CTRL] = bits({FD=0,SLU=6,RST=26}) -- Global reset
      C.usleep(10); assert( not bitset(regs[CTRL],26) )
      regs[IMC] = 0                       -- Disable interrupts
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
      print("  RADV        = " .. regs[RADV])
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
            // uint32_t rss;
            uint16_t checksum;
            uint16_t id;
            uint32_t mrq;
            uint32_t status;
            uint16_t length;
            uint16_t vlan;
         } __attribute__((packed));

         union rx {
            struct rx_desc data;
            struct rx_desc_wb wb;
         } __attribute__((packed));
   ]]

   local rxnext = 0
   local rxbuffers = {}

   function init_receive ()
      -- Disable RX and program all the registers
      regs[RCTL] = bits({UPE=3, MPE=4, -- Unicast & Multicast promiscuous mode
            LPE=5,        -- Long Packet Enable (over 1522 bytes)
            BSIZE1=17, BSIZE0=16, BSEX=25, -- 4KB buffers
            SECRC=26,      -- Strip Ethernet CRC from packets
            BAM=15         -- Broadcast Accept Mode
         })
      regs[RFCTL] = bits({EXSTEN=15})  -- Extended RX writeback descriptor format
--      regs[RXDCTL] = bits({GRAN=24, WTHRESH0=16})
      regs[RXCSUM] = 0                 -- Disable checksum offload - not needed
      regs[RADV] = math.log(1024,2)    -- 1us max writeback delay
      regs[RDLEN] = num_descriptors * ffi.sizeof("union rx")
      regs[RDBAL] = bit.band(dma_phys + offset_rxdesc, 0xffffffff)
      regs[RDBAH] = 0
      regs[RDH] = 0
      regs[RDT] = 0
      rxnext = 0
      -- Enable RX
      regs[RCTL] = bit.bor(regs[RCTL], bits{EN=1})
   end

   -- Enqueue a receive descriptor to receive a packet.
   function M.add_rxbuf (address, size)
      -- NOTE: RDT points to the next unused descriptor
      local index = regs[RDT]
      rxdesc[index].data.address = address
      rxdesc[index].data.dd = 0
      regs[RDT] = (index + 1) % num_descriptors
      rxbuffers[index] = address
      return true
   end

   function M.rx_full ()
      return regs[RDH] == (regs[RDT] + 1) % num_descriptors
   end

   function M.rx_empty ()
      return regs[RDH] == regs[RDT]
   end

   function M.rx_available ()
      return num_descriptors - M.rx_pending()
   end

   function M.rx_pending ()
      return ring_pending(regs[RDT], regs[RDH])
   end

   function M.rx_load ()
      return rx_pending() / num_descriptors
   end

   -- Return the next available packet as two values: buffer, length.
   -- If no packet is available then return nil.
   function M.receive ()
      if regs[RDH] ~= rxnext then
         local wb = rxdesc[rxnext].wb
         local index = rxnext
         local length = wb.length
         rxnext = (rxnext + 1) % num_descriptors
         return rxbuffers[index], length
      end
   end

   function M.ack ()
   end

   -- Transmit functionality

   ffi.cdef[[
         // TX Extended Data Descriptor written by software.
         struct tx_desc {
            uint64_t address;
            uint64_t options;
         } __attribute__((packed));

         struct tx_context_desc {
            unsigned int tucse:16,
                         tucso:8,
                         tucss:8,
                         ipcse:16,
                         ipcso:8,
                         ipcss:8,
                         mss:16,
                         hdrlen:8,
                         rsv:2,
                         sta:4,
                         tucmd:8,
                         dtype:4,
                         paylen:20;
         } __attribute__((packed));

         union tx {
            struct tx_desc data;
            struct tx_context_desc ctx;
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

   -- Locally cached copy of the Transmit Descriptor Tail (TDT) register.
   -- Updates are kept locally here until flush_tx() is called.
   -- That's because updating the hardware register is relatively expensive.
   local tdt = 0

   -- Flags for transmit descriptors.
   local txdesc_flags = bits({dtype=20, eop=24, ifcs=25, dext=29})

   -- Enqueue a transmit descriptor to send a packet.
   local function add_txbuf (address, size)
      txdesc[tdt].data.address = address
      txdesc[tdt].data.options = bit.bor(size, txdesc_flags)
      tdt = (tdt + 1) % num_descriptors
   end M.add_txbuf = add_txbuf

   local function flush_tx(address, size)
      regs[TDT] = tdt
   end M.flush_tx = flush_tx

   function M.add_txbuf_tso (address, size, mss, ctx)
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

   function M.tx_full  () return M.tx_pending() == num_descriptors - 1 end
   function M.tx_empty () return M.tx_pending() == 0 end

   local function ring_pending(head, tail)
      if head == tail then return 0 end
      if head <  tail then return tail - head
      else                 return num_descriptors + tail - head end
   end M.ring_pending = ring_pending

   local function tx_pending ()
      return ring_pending(regs[TDH], regs[TDT])
   end M.tx_pending = tx_pending

   local function tx_available ()
      return num_descriptors - tx_pending() - 1
   end M.tx_available = tx_available

   local function tx_load ()
      return tx_pending() / num_descriptors
   end M.tx_load = tx_load

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
      {"PRC255",   0x04064, "Packets Received [128 - 255 Bytes] Count"},
      {"PRC511",   0x04068, "Packets Received [256–511 Bytes] Count"},
      {"PRC1023",  0x0406C, "Packets Received [512–1023 Bytes] Count"},
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
      {"PTC127",   0x040DC, "Packets Transmitted [65–127 Bytes] Count"},
      {"PTC255",   0x040E0, "Packets Transmitted [128–255 Bytes] Count"},
      {"PTC511",   0x040E4, "Packets Transmitted [256–511 Bytes] Count"},
      {"PTC1023",  0x040E8, "Packets Transmitted [512–1023 Bytes] Count"},
      {"PTC1522",  0x040EC, "Packets Transmitted [Greater than 1024 Bytes] Count"},
      {"MPTC",     0x040F0, "Multicast Packets Transmitted Count"},
      {"BPTC",     0x040F4, "Broadcast Packets Transmitted Count"},
      {"TSCTC",    0x040F8, "TCP Segmentation Context Transmitted Count"},
      {"TSCTFC",   0x040FC, "TCP Segmentation Context Transmit Fail Count"},
      {"IAC",      0x04100, "Interrupt Assertion Count"}
     }

   M.stats = {}

   function M.update_stats ()
      for _,reg in ipairs(statistics_regs) do
         name, offset, desc = reg[1], reg[2], reg[3]
         M.stats[name] = (M.stats[name] or 0) + regs[offset/4]
      end
   end

   function M.print_stats ()
      print("Statistics for PCI device " .. pciaddress .. ":")
      for _,reg in ipairs(statistics_regs) do
         name, desc = reg[1], reg[3]
         if M.stats[name] > 0 then
            print(("%20s %-10s %s"):format(lib.comma_value(M.stats[name]), name, desc))
         end
      end
   end

   -- Self-test diagnostics

   function M.selftest2 (options)
      options = options or {}
      --      local tx_load,tx_available,add_txbuf = M.tx_load,M.tx_available,M.add_txbuf
      if not options.nolinkup then
         test.waitfor("linkup", M.linkup, 20, 250000)
      end
      if options.loopback then
         M.enable_mac_loopback()
      end
      if not options.skip_transmit then
         local deadline = C.get_time_ns() + 10000000000LL
         repeat
            while tx_load() > 0.75 do C.usleep(10000) end
            for i = 1, tx_available() do
               add_txbuf(dma_phys, math.random(100, 1400))
            end
            flush_tx()
         until C.get_time_ns() > deadline
         M.update_stats()
         M.print_stats()
      end
   end

   -- Test the NIC.
   function M.selftest (options)
      options = options or {}
      local packets = options.packets or 100000
      local verify = options.verify == true
      local verbose = options.verbose == true
      local rxindex = 0
      local software_rx_packets = 0
      local software_rx_bytes = 0
      local start_time_ns = C.get_time_ns()

      local function txbuf(i)
         return dma_start + offset_buffers + 4096*1024 + (i % 1024)*1024
      end
      local function rxbuf(i)
         return dma_start + offset_buffers + (i % 1024)*4096
      end
      local function rxpacket ()
         local packet, length = M.receive()
         if packet then
            software_rx_packets = software_rx_packets + 1
            software_rx_bytes = software_rx_bytes + length + 4 -- stripped CRC
            return true
         end
      end
      -- Transmit and receive loop
      for txindex = 0,packets-1 do
         while not M.rx_full() do
            M.add_rxbuf(rxbuf(rxindex), 4096)
            rxindex = rxindex + 1
         end
         if not M.tx_full() then M.add_txbuf(txbuf(txindex), 996) end
         while rxpacket() do end
      end
      -- Catch up remaining packets
      for catchup = 0,num_descriptors do
         rxpacket()
      end
      M.update_stats()
      M.print_stats()
      print("software RX packets: ", lib.comma_value(software_rx_packets))
      print("software RX bytes:   ", lib.comma_value(software_rx_bytes))
      local elapsed_time = tonumber(C.get_time_ns() - start_time_ns) / 1000000000.0
      print("Elapsed time (secs): ", lib.comma_value(elapsed_time))
      print("Megabits per second: ",
            lib.comma_value(math.floor(software_rx_bytes * 8.0 / 1024 / 1028 / elapsed_time)))
      print("Packets per second:  ",
            lib.comma_value(math.floor(software_rx_packets / elapsed_time)))

      if verbose then
         local ptr = ffi.cast("uint32_t*", ffi.cast("char*", dma_virt) + 8192)
         for x = 1,128 do
            io.write(bit.tohex(ptr[x]).." ")
            if x > 0 and x % 8 == 0 then print() end
         end
      end
   end

   return M
end

