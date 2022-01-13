-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

--- Device driver for the Intel 82599 10-Gigabit Ethernet controller.
--- This is one of the most popular production 10G Ethernet
--- controllers on the market and it is readily available in
--- affordable (~$400) network cards made by Intel and others.
---
--- You will need to familiarize yourself with the excellent [data
--- sheet](http://www.intel.com/content/dam/www/public/us/en/documents/datasheets/82599-10-gbe-controller-datasheet.pdf)
--- to understand this module.

module(...,package.seeall)

local ffi      = require "ffi"
local C        = ffi.C
local lib      = require("core.lib")
local pci      = require("lib.hardware.pci")
local register = require("lib.hardware.register")
local index_set = require("lib.index_set")
local macaddress = require("lib.macaddress")
local timer = require("core.timer")

local bits, bitset = lib.bits, lib.bitset
local band, bor, lshift = bit.band, bit.bor, bit.lshift

local num_descriptors = 1024
function ring_buffer_size (arg)
   if not arg then return num_descriptors end
   local ring_size = assert(tonumber(arg), "bad ring size: " .. arg)
   if ring_size > 32*1024 then
      error("ring size too large for hardware: " .. ring_size)
   end
   if math.log(ring_size)/math.log(2) % 1 ~= 0 then
      error("ring size is not a power of two: " .. arg)
   end
   num_descriptors = assert(tonumber(arg))
end

-- Defaults for configurable items
local default = {
   -- The MTU configured through the MAXFRS.MFS register includes the
   -- Ethernet header and CRC. It is limited to 65535 bytes.  We use
   -- the convention that the configurable MTU includes the Ethernet
   -- header but not the CRC.  This is "natural" in the sense that the
   -- unit of data handed to the driver contains a complete Ethernet
   -- packet.
   --
   -- For untagged packets, the Ethernet overhead is 14 bytes.  If
   -- 802.1q tagging is used, the Ethernet overhead is increased by 4
   -- bytes per tag.  This overhead must be included in the MTU if
   -- tags are handled by the software.  However, the NIC always
   -- accepts packets of size MAXFRS.MFS+4 and MAXFRS.MFS+8 if single-
   -- or double tagged packets are received (see section 8.2.3.22.13).
   -- In this case, we will actually accept packets which exceed the
   -- MTU.
   --
   -- XXX If hardware support for VLAN tag adding or stripping is
   -- enabled, one should probably not include the tags in the MTU.
   --
   -- The default MTU allows for an IP packet of a total size of 9000
   -- bytes without VLAN tagging.
   mtu = 9014,
}

local function pass (...) return ... end


--- ### SF: single function: non-virtualized device
local M_sf = {}; M_sf.__index = M_sf

function new_sf (conf)
   local dev = { pciaddress = conf.pciaddr, -- PCI device address
                 mtu = (conf.mtu or default.mtu),
                 fd = false,       -- File descriptor for PCI memory
                 r = {},           -- Configuration registers
                 s = {},           -- Statistics registers
                 qs = {},          -- queue statistic registers
                 txdesc = 0,     -- Transmit descriptors (pointer)
                 txdesc_phy = 0, -- Transmit descriptors (physical address)
                 txpackets = {},   -- Tx descriptor index -> packet mapping
                 tdh = 0,          -- Cache of transmit head (TDH) register
                 tdt = 0,          -- Cache of transmit tail (TDT) register
                 rxdesc = 0,     -- Receive descriptors (pointer)
                 rxdesc_phy = 0, -- Receive descriptors (physical address)
                 rxpackets = {},   -- Rx descriptor index -> packet mapping
                 rdh = 0,          -- Cache of receive head (RDH) register
                 rdt = 0,          -- Cache of receive tail (RDT) register
                 rxnext = 0,       -- Index of next buffer to receive
              }
   return setmetatable(dev, M_sf)
end

function M_sf:open ()
   self.fd = pci.open_pci_resource_locked(self.pciaddress, 0)
   pci.unbind_device_from_linux(self.pciaddress)
   pci.set_bus_master(self.pciaddress, true)
   self.base = pci.map_pci_memory(self.fd)
   register.define(config_registers_desc, self.r, self.base)
   register.define(transmit_registers_desc, self.r, self.base)
   register.define(receive_registers_desc, self.r, self.base)
   register.define_array(packet_filter_desc, self.r, self.base)
   register.define(statistics_registers_desc, self.s, self.base)
   register.define_array(queue_statistics_registers_desc, self.qs, self.base)
   self.txpackets = ffi.new("struct packet *[?]", num_descriptors)
   self.rxpackets = ffi.new("struct packet *[?]", num_descriptors)
   return self:init()
end

function M_sf:close()
   pci.set_bus_master(self.pciaddress, false)
   if self.free_receive_buffers then
      self:free_receive_buffers()
   end
   if self.discard_unsent_packets then
      self:discard_unsent_packets()
      C.usleep(1000)
   end
   if self.fd then
      pci.close_pci_resource(self.fd, self.base)
      self.fd = false
   end
   self:free_dma_memory()
end

--- See data sheet section 4.6.3 "Initialization Sequence."

function M_sf:init ()
   self:init_dma_memory()

   self.redos = 0
   local mask = bits{Link_up=30}
   for i = 1, 100 do
      self
         :disable_interrupts()
         :global_reset()
      if i%5 == 0 then self:autonegotiate_sfi() end
      self
         :wait_eeprom_autoread()
         :wait_dma()
         :init_statistics()
         :init_receive()
         :init_transmit()
         :init_txdesc_prefetch()
         :wait_enable()
         :wait_linkup()

      if band(self.r.LINKS(), mask) == mask then
         self.redos = i
         return self
      end
   end
   io.write ('never got link up: ', self.pciaddress, '\n')
   os.exit(2)
   return self
end


do
   local _rx_pool = {}
   local _tx_pool = {}

   local function get_ring(ct, pool)
      local spot, v = next(pool)
      if spot and v then
         pool[spot] = nil
         return v.ptr, v.phy
      end
      local ptr, phy =
         memory.dma_alloc(num_descriptors * ffi.sizeof(ct))
      -- Initialize unused DMA memory with -1. This is so that
      -- accidental premature use of DMA memory will cause a DMA error
      -- (write to illegal address) instead of overwriting physical
      -- memory near address 0.
      ffi.fill(ptr, 0xff, num_descriptors * ffi.sizeof(ct))
      -- ptr = lib.bounds_checked(ct, ptr, 0, num_descriptors)
      ptr = ffi.cast(ffi.typeof("$*", ct), ptr)
      return ptr, phy
   end

   function M_sf:init_dma_memory ()
      self.rxdesc, self.rxdesc_phy = get_ring(rxdesc_t, _rx_pool)
      self.txdesc, self.txdesc_phy = get_ring(txdesc_t, _tx_pool)
      return self
   end

   function M_sf:free_dma_memory()
      _rx_pool[#_rx_pool+1] = {ptr = self.rxdesc, phy = self.rxdesc_phy}
      _tx_pool[#_tx_pool+1] = {ptr = self.txdesc, phy = self.txdesc_phy}
      return self
   end
end

function M_sf:rxdrop () return self.qs.QPRDC[0]() end

function M_sf:global_reset ()
   local reset = bits{LinkReset=3, DeviceReset=26}
   self.r.CTRL(reset)
   C.usleep(1000)
   self.r.CTRL:wait(reset, 0)
   return self
end

function M_sf:disable_interrupts () return self end --- XXX do this
function M_sf:wait_eeprom_autoread ()
   self.r.EEC:wait(bits{AutoreadDone=9})
   return self
end

function M_sf:wait_dma ()
   self.r.RDRXCTL:wait(bits{DMAInitDone=3})
   return self
end

function M_sf:init_statistics ()
   -- Read and then zero each statistic register
   for _,reg in pairs(self.s) do reg:read() reg:reset() end
   -- Make sure RX Queue #0 is mapped to the stats register #0.  In
   -- the default configuration, all 128 RX queues are mapped to this
   -- stats register.  In non-virtualized mode, only queue #0 is
   -- actually used.
   self.qs.RQSMR[0]:set(0)
   return self
end

function M_sf:init_receive ()
   self.r.RXCTRL:clr(bits{RXEN=0})
   self:set_promiscuous_mode() -- NB: don't need to program MAC address filter
   self.r.HLREG0(bits{
      TXCRCEN=0, RXCRCSTRP=1, rsv2=3, TXPADEN=10,
      rsvd3=11, rsvd4=13, MDCSPD=16
   })
   if self.mtu > 1514 then
      self.r.HLREG0:set(bits{ JUMBOEN=2 })
      -- MAXFRS is set to a hard-wired default of 1518 if JUMBOEN is
      -- not set.  The MTU does *not* include the 4-byte CRC, but
      -- MAXFRS does.
      self.r.MAXFRS(lshift(self.mtu+4, 16))
   end
   self:set_receive_descriptors()
   self.r.RXCTRL:set(bits{RXEN=0})
   if self.r.DCA_RXCTRL then -- Register may be undefined in subclass (PF)
      -- Datasheet 4.6.7 says to clear this bit.
      -- Have observed payload corruption when this is not done.
      self.r.DCA_RXCTRL:clr(bits{RxCTRL=12})
   end
   return self
end

function M_sf:set_rx_buffersize(rx_buffersize)
   rx_buffersize = math.min(16, math.floor((rx_buffersize or 16384) / 1024))  -- size in KB, max 16KB
   assert (rx_buffersize > 0, "rx_buffersize must be more than 1024")
   assert(rx_buffersize*1024 >= self.mtu, "rx_buffersize is too small for the MTU")
   self.rx_buffersize = rx_buffersize * 1024
   self.r.SRRCTL(bits({DesctypeLSB=25}, rx_buffersize))
   self.r.SRRCTL:set(bits({Drop_En=28})) -- Enable RX queue drop counter
   return self
end

function M_sf:set_receive_descriptors ()
   self:set_rx_buffersize(16384)        -- start at max

   self.r.RDBAL(self.rxdesc_phy % 2^32)
   self.r.RDBAH(self.rxdesc_phy / 2^32)
   self.r.RDLEN(num_descriptors * ffi.sizeof(rxdesc_t))
   return self
end

function M_sf:wait_enable ()
   self.r.RXDCTL(bits{Enable=25})
   self.r.RXDCTL:wait(bits{enable=25})
   self.r.TXDCTL:wait(bits{Enable=25})
   return self
end

function M_sf:set_promiscuous_mode ()
   self.r.FCTRL(bits({MPE=8, UPE=9, BAM=10}))
   return self
end

function M_sf:init_transmit ()
   self.r.HLREG0:set(bits{TXCRCEN=0})
   self:set_transmit_descriptors()
   self.r.DMATXCTL:set(bits{TE=0})
   return self
end

function M_sf:init_txdesc_prefetch ()
   self.r.TXDCTL:set(bits{SWFLSH=26, hthresh=8} + 32)
   return self
end

function M_sf:set_transmit_descriptors ()
   self.r.TDBAL(self.txdesc_phy % 2^32)
   self.r.TDBAH(self.txdesc_phy / 2^32)
   self.r.TDLEN(num_descriptors * ffi.sizeof(txdesc_t))
   return self
end


--- ### Transmit

--- See datasheet section 7.1 "Inline Functions -- Transmit Functionality."

local txdesc_flags = bits{ifcs=25, dext=29, dtyp0=20, dtyp1=21, eop=24}

function M_sf:transmit (p)
   self.txdesc[self.tdt].address = memory.virtual_to_physical(p.data)
   self.txdesc[self.tdt].options = bor(p.length, txdesc_flags, lshift(p.length+0ULL, 46))
   self.txpackets[self.tdt] = p
   self.tdt = band(self.tdt + 1, num_descriptors - 1)
end

function M_sf:sync_transmit ()
   local old_tdh = self.tdh
   self.tdh = self.r.TDH()
   C.full_memory_barrier()
   -- Release processed buffers
   if old_tdh ~= self.tdh then
      while old_tdh ~= self.tdh do
         packet.free(self.txpackets[old_tdh])
         self.txpackets[old_tdh] = nil
         old_tdh = band(old_tdh + 1, num_descriptors - 1)
      end
   end
   self.r.TDT(self.tdt)
end

function M_sf:can_transmit ()
   return band(self.tdt + 1, num_descriptors - 1) ~= self.tdh
end

function M_sf:discard_unsent_packets()
   local old_tdt = self.tdt
   self.tdt = self.r.TDT()
   self.tdh = self.r.TDH()
   self.r.TDT(self.tdh)
   while old_tdt ~= self.tdh do
      old_tdt = band(old_tdt - 1, num_descriptors - 1)
      packet.free(self.txpackets[old_tdt])
      self.txdesc[old_tdt].address = -1
      self.txdesc[old_tdt].options = 0
   end
   self.tdt = self.tdh
end

--- See datasheet section 7.1 "Inline Functions -- Receive Functionality."

function M_sf:receive ()
   assert(self:can_receive())
   local wb = self.rxdesc[self.rxnext].wb
   local p = self.rxpackets[self.rxnext]
   p.length = wb.pkt_len
   self.rxpackets[self.rxnext] = nil
   self.rxnext = band(self.rxnext + 1, num_descriptors - 1)
   return p
end

function M_sf:can_receive ()
   return self.rxnext ~= self.rdh and band(self.rxdesc[self.rxnext].wb.xstatus_xerror, 1) == 1
end

function M_sf:can_add_receive_buffer ()
   return band(self.rdt + 1, num_descriptors - 1) ~= self.rxnext
end

function M_sf:add_receive_buffer (p)
   assert(self:can_add_receive_buffer())
   local desc = self.rxdesc[self.rdt].data
   desc.address, desc.dd = memory.virtual_to_physical(p.data), 0
   self.rxpackets[self.rdt] = p
   self.rdt = band(self.rdt + 1, num_descriptors - 1)
end

function M_sf:free_receive_buffers ()
   while self.rdt ~= self.rdh do
      self.rdt = band(self.rdt - 1, num_descriptors - 1)
      local desc = self.rxdesc[self.rdt].data
      desc.address, desc.dd = -1, 0
      packet.free(self.rxpackets[self.rdt])
      self.rxpackets[self.rdt] = nil
   end
end

function M_sf:sync_receive ()
   -- XXX I have been surprised to see RDH = num_descriptors,
   --     must check what that means. -luke
   self.rdh = math.min(self.r.RDH(), num_descriptors-1)
   assert(self.rdh < num_descriptors)
   C.full_memory_barrier()
   self.r.RDT(self.rdt)
end

function M_sf:wait_linkup ()
   self.waitlu_ms = 0
   local mask = bits{Link_up=30}
   for count = 1, 1000 do
      if band(self.r.LINKS(), mask) == mask then
         self.waitlu_ms = count
         return self
      end
      C.usleep(1000)
   end
   self.waitlu_ms = 1000
   return self
end

--- ### Status and diagnostics


-- negotiate access to software/firmware shared resource
-- section 10.5.4
function negotiated_autoc (dev, f)
   local function waitfor (test, attempts, interval)
      interval = interval or 100
      for count = 1,attempts do
         if test() then return true end
         C.usleep(interval)
         io.flush()
      end
      return false
   end
   local function tb (reg, mask, val)
      return function() return bit.band(reg(), mask) == (val or mask) end
   end

   local gotresource = waitfor(function()
      local accessible = false
      local softOK = waitfor (tb(dev.r.SWSM, bits{SMBI=0},0), 30100)
      dev.r.SWSM:set(bits{SWESMBI=1})
      local firmOK = waitfor (tb(dev.r.SWSM, bits{SWESMBI=1}), 30000)
      accessible = bit.band(dev.r.SW_FW_SYNC(), 0x108) == 0
      if not firmOK then
         dev.r.SW_FW_SYNC:clr(0x03E0)   -- clear all firmware bits
         accessible = true
      end
      if not softOK then
         dev.r.SW_FW_SYNC:clr(0x1F)     -- clear all software bits
         accessible = true
      end
      if accessible then
         dev.r.SW_FW_SYNC:set(0x8)
      end
      dev.r.SWSM:clr(bits{SMBI=0, SWESMBI=1})
      if not accessible then C.usleep(100) end
      return accessible
   end, 10000)   -- TODO: only twice
   if not gotresource then error("Can't acquire shared resource") end

   local r = f(dev)

   waitfor (tb(dev.r.SWSM, bits{SMBI=0},0), 30100)
   dev.r.SWSM:set(bits{SWESMBI=1})
   waitfor (tb(dev.r.SWSM, bits{SWESMBI=1}), 30000)
   dev.r.SW_FW_SYNC:clr(0x108)
   dev.r.SWSM:clr(bits{SMBI=0, SWESMBI=1})
   return r
end


function set_SFI (dev, lms)
   lms = lms or bit.lshift(0x3, 13)         -- 10G SFI
   local autoc = dev.r.AUTOC()
   if bit.band(autoc, bit.lshift(0x7, 13)) == lms then
      dev.r.AUTOC(bits({restart_AN=12}, bit.bxor(autoc, 0x8000)))      -- flip LMS[2] (15)
      lib.waitfor(function ()
         return bit.band(dev.r.ANLP1(), 0xF0000) ~= 0
      end)
   end

   dev.r.AUTOC(bit.bor(bit.band(autoc, 0xFFFF1FFF), lms))
   return dev
end

function M_sf:autonegotiate_sfi ()
   return negotiated_autoc(self, function()
      set_SFI(self)
      self.r.AUTOC:set(bits{restart_AN=12})
      self.r.AUTOC2(0x00020000)
      return self
   end)
end


--- ### PF: the physiscal device in a virtualized setup
local M_pf = {}; M_pf.__index = M_pf

function new_pf (conf)
   local dev = { pciaddress = conf.pciaddr, -- PCI device address
                 mtu = (conf.mtu or default.mtu),
                 r = {},           -- Configuration registers
                 s = {},           -- Statistics registers
                 qs = {},          -- queue statistic registers
                 mac_set = index_set:new(127, "MAC address table"),
                 vlan_set = index_set:new(64, "VLAN Filter table"),
                 mirror_set = index_set:new(4, "Mirror pool table"),
              }
   return setmetatable(dev, M_pf)
end

function M_pf:open ()
   self.fd = pci.open_pci_resource_locked(self.pciaddress, 0)
   pci.unbind_device_from_linux(self.pciaddress)
   pci.set_bus_master(self.pciaddress, true)
   self.base = pci.map_pci_memory(self.fd)
   register.define(config_registers_desc, self.r, self.base)
   register.define_array(switch_config_registers_desc, self.r, self.base)
   register.define_array(packet_filter_desc, self.r, self.base)
   register.define(statistics_registers_desc, self.s, self.base)
   register.define_array(queue_statistics_registers_desc, self.qs, self.base)
   return self:init()
end

function M_pf:close()
   pci.set_bus_master(self.pciaddress, false)
   if self.fd then
      pci.close_pci_resource(self.fd, self.base)
      self.fd = false
   end
end

function M_pf:init ()
   self.redos = 0
   local mask = bits{Link_up=30}
   for i = 1, 100 do
      self
         :disable_interrupts()
         :global_reset()
      if i%5 == 0 then self:autonegotiate_sfi() end
      self
         :wait_eeprom_autoread()
         :wait_dma()
         :set_vmdq_mode()
         :init_statistics()
         :init_receive()
         :init_transmit()
         :wait_linkup()
      if band(self.r.LINKS(), mask) == mask then
         return self
      end
      self.redos = i
   end
   io.write ('never got link up: ', self.pciaddress, '\n')
   os.exit(2)
   return self
end

M_pf.global_reset = M_sf.global_reset
M_pf.disable_interrupts = M_sf.disable_interrupts
M_pf.set_receive_descriptors = pass
M_pf.set_transmit_descriptors = pass
M_pf.autonegotiate_sfi = M_sf.autonegotiate_sfi
M_pf.wait_eeprom_autoread = M_sf.wait_eeprom_autoread
M_pf.wait_dma = M_sf.wait_dma
M_pf.init_statistics = M_sf.init_statistics
M_pf.set_promiscuous_mode = M_sf.set_promiscuous_mode
M_pf.init_receive = M_sf.init_receive
M_pf.init_transmit = M_sf.init_transmit
M_pf.wait_linkup = M_sf.wait_linkup

function M_pf:set_vmdq_mode ()
   self.r.RTTDCS(bits{VMPAC=1,ARBDIS=6,BDPM=22})       -- clear TDPAC,TDRM=4, BPBFSM
   self.r.RFCTL:set(bits{RSC_Dis=5})             -- no RSC
   self.r.MRQC(0x08)     -- 1000b -> 64 pools, x2queues, no RSS, no IOV
   self.r.MTQC(bits{VT_Ena=1, Num_TC_OR_Q=2})    -- 128 Tx Queues, 64 VMs (4.6.11.3.3)
   self.r.PFVTCTL(bits{VT_Ena=0, Rpl_En=30, DisDefPool=29})     -- enable virtualization, replication enabled
   self.r.PFDTXGSWC:set(bits{LBE=0})             -- enable Tx to Rx loopback
   self.r.RXPBSIZE[0](0x80000)             -- no DCB: all queues to PB0 (0x200<<10)
   self.r.TXPBSIZE[0](0x28000)             -- (0xA0<<10)
   self.r.TXPBTHRESH[0](0xA0)
   self.r.FCRTH[0](0x10000)
   self.r.RXDSTATCTRL(0x10)                 -- Rx DMA Statistic for all queues
   self.r.VLNCTRL:set(bits{VFE=30})         -- Vlan filter enable
   for i = 1, 7 do
      self.r.RXPBSIZE[i](0x00)
      self.r.TXPBSIZE[i](0x00)
      self.r.TXPBTHRESH[i](0x00)
   end
   for i = 0, 7 do
      self.r.RTTDT2C[i](0x00)
      self.r.RTTPT2C[i](0x00)
      self.r.ETQF[i](0x00)                 -- disable ethertype filter
      self.r.ETQS[0](0x00)
   end
   -- clear PFQDE.QDE (queue drop enable) for each queue
   for i = 0, 127 do
      self.r.PFQDE(bor(lshift(1,16), lshift(i,8)))
      self.r.FTQF[i](0x00)                 -- disable L3/4 filter
      self.r.RAH[i](0)
      self.r.RAL[i](0)
      self.r.VFTA[i](0)
      self.r.PFVLVFB[i](0)
   end
   for i = 0, 63 do
      self.r.RTTDQSEL(i)
      self.r.RTTDT1C(0x00)
      self.r.PFVLVF[i](0)
   end
   for i = 0, 31 do
      self.r.RETA[i](0x00)                 -- clear redirection table
   end

   self.r.RTRUP2TC(0x00)                   -- Rx UPnMAP = 0
   self.r.RTTUP2TC(0x00)                   -- Tx UPnMAP = 0
      -- move to vf initialization
--    set_pool_transmit_weight(dev, 0, 0x1000)     -- pool 0 must be initialized, set at range midpoint
   self.r.DTXMXSZRQ(0xFFF)
   self.r.MFLCN(bits{RFCE=3})            -- optional? enable legacy flow control
   self.r.FCCFG(bits{TFCE=3})
   self.r.RTTDCS:clr(bits{ARBDIS=6})
   return self
end

--- ### VF: virtualized device
local M_vf = {}; M_vf.__index = M_vf

-- it's the PF who creates a VF
function M_pf:new_vf (poolnum)
   assert(poolnum < 64, "Pool overflow: Intel 82599 can only have up to 64 virtualized devices.")
   local txqn = poolnum*2
   local rxqn = poolnum*2
   local vf = {
      pf = self,
      -- some things are shared with the main device...
      base = self.base,             -- mmap()ed register file
      s = self.s,                   -- Statistics registers
      mtu = self.mtu,
      -- and others are our own
      r = {},                       -- Configuration registers
      poolnum = poolnum,
      txqn = txqn,                  -- Transmit queue number
      txdesc = 0,                   -- Transmit descriptors (pointer)
      txdesc_phy = 0,               -- Transmit descriptors (io address)
      txpackets = {},               -- Tx descriptor index -> packet mapping
      tdh = 0,                      -- Cache of transmit head (TDH) register
      tdt = 0,                      -- Cache of transmit tail (TDT) register
      rxqn = rxqn,                   -- receive queue number
      rxdesc = 0,                   -- Receive descriptors (pointer)
      rxdesc_phy = 0,               -- Receive descriptors (physical address)
      rxpackets = {},               -- Rx descriptor index -> packet mapping
      rdh = 0,                      -- Cache of receive head (RDH) register
      rdt = 0,                      -- Cache of receive tail (RDT) register
      rxnext = 0,                   -- Index of next buffer to receive
   }
   return setmetatable(vf, M_vf)
end

function M_vf:open (opts)
   register.define(transmit_registers_desc, self.r, self.base, self.txqn)
   register.define(receive_registers_desc, self.r, self.base, self.rxqn)
   self.txpackets = ffi.new("struct packet *[?]", num_descriptors)
   self.rxpackets = ffi.new("struct packet *[?]", num_descriptors)
   return self:init(opts)
end

function M_vf:close()
   local poolnum = self.poolnum or 0
   local pf = self.pf

   if self.free_receive_buffers then
      self:free_receive_buffers()
   end
   if self.discard_unsent_packets then
      self:discard_unsent_packets()
      C.usleep(1000)
   end

   -- unset_tx_rate
   self:set_tx_rate(0, 0)
   self
      :unset_mirror()
      :unset_VLAN()
   -- unset MAC
   do
      local msk = bits{Ena=self.poolnum%32}
      for mac_index = 0, 127 do
         pf.r.MPSAR[2*mac_index + math.floor(poolnum/32)]:clr(msk)
      end
   end

   self:disable_transmit()
      :disable_receive()
      :free_dma_memory()

   return self
end

function M_vf:reconfig(opts)
   local poolnum = self.poolnum or 0
   local pf = self.pf

   self
      :unset_mirror()
      :unset_VLAN()
      :unset_MAC()
   do
      local msk = bits{Ena=self.poolnum%32}
      for mac_index = 0, 127 do
         pf.r.MPSAR[2*mac_index + math.floor(poolnum/32)]:clr(msk)
      end
   end

   return self
      :set_MAC(opts.macaddr)
      :set_mirror(opts.mirror)
      :set_VLAN(opts.vlan)
      :set_rx_stats(opts.rxcounter)
      :set_tx_stats(opts.txcounter)
      :set_tx_rate(opts.rate_limit, opts.priority)
      :enable_receive()
      :enable_transmit()
end

function M_vf:init (opts)
   return self
      :init_dma_memory()
      :init_receive()
      :init_transmit()
      :set_MAC(opts.macaddr)
      :set_mirror(opts.mirror)
      :set_VLAN(opts.vlan)
      :set_rx_stats(opts.rxcounter)
      :set_tx_stats(opts.txcounter)
      :set_tx_rate(opts.rate_limit, opts.priority)
      :enable_receive()
      :enable_transmit()
end

M_vf.init_dma_memory = M_sf.init_dma_memory
M_vf.free_dma_memory = M_sf.free_dma_memory
M_vf.set_receive_descriptors = M_sf.set_receive_descriptors
M_vf.set_transmit_descriptors = M_sf.set_transmit_descriptors
M_vf.can_transmit = M_sf.can_transmit
M_vf.transmit = M_sf.transmit
M_vf.sync_transmit = M_sf.sync_transmit
M_vf.discard_unsent_packets = M_sf.discard_unsent_packets
M_vf.can_receive = M_sf.can_receive
M_vf.receive = M_sf.receive
M_vf.can_add_receive_buffer = M_sf.can_add_receive_buffer
M_vf.set_rx_buffersize = M_sf.set_rx_buffersize
M_vf.add_receive_buffer = M_sf.add_receive_buffer
M_vf.free_receive_buffers = M_sf.free_receive_buffers
M_vf.sync_receive = M_sf.sync_receive

function M_vf:init_receive ()
   local poolnum = self.poolnum or 0
   self.pf.r.PSRTYPE[poolnum](0)        -- no splitting, use pool's first queue
   self.r.RSCCTL(0x0)                   -- no RSC
   self:set_receive_descriptors()
   self.pf.r.PFVML2FLT[poolnum]:set(bits{MPE=28, BAM=27, AUPE=24})
   return self
end

function M_vf:enable_receive()
   self.r.RXDCTL(bits{Enable=25, VME=30})
   self.r.RXDCTL:wait(bits{enable=25})
   self.r.DCA_RXCTRL:clr(bits{RxCTRL=12})
   self.pf.r.PFVFRE[math.floor(self.poolnum/32)]:set(bits{VFRE=self.poolnum%32})
   return self
end

function M_vf:disable_receive(reenable)
   self.r.RXDCTL:clr(bits{Enable=25})
   self.r.RXDCTL:wait(bits{Enable=25}, 0)
   C.usleep(100)
   -- TODO free packet buffers
   self.pf.r.PFVFRE[math.floor(self.poolnum/32)]:clr(bits{VFRE=self.poolnum%32})

   if reenable then
      self.r.RXDCTL(bits{Enable=25, VME=30})
   --    self.r.RXDCTL:wait(bits{enable=25})
   end
   return self
end

function M_vf:init_transmit ()
   local poolnum = self.poolnum or 0
   self.r.TXDCTL:clr(bits{Enable=25})
   self:set_transmit_descriptors()
   self.pf.r.PFVMTXSW[math.floor(poolnum/32)]:clr(bits{LLE=poolnum%32})
   self.pf.r.PFVFTE[math.floor(poolnum/32)]:set(bits{VFTE=poolnum%32})
   self.pf.r.RTTDQSEL(poolnum)
   self.pf.r.RTTDT1C(0x80)
   self.pf.r.RTTBCNRC(0x00)         -- no rate limiting
   return self
end

function M_vf:enable_transmit()
   self.pf.r.DMATXCTL:set(bits{TE=0})
   self.r.TXDCTL:set(bits({Enable=25, SWFLSH=26, hthresh=8}) + 32)
   self.r.TXDCTL:wait(bits{Enable=25})
   return self
end

function M_vf:disable_transmit(reenable)
   -- TODO: wait TDH==TDT
   -- TODO: wait all is written back: DD bit or Head_WB
   self.r.TXDCTL:clr(bits{Enable=25})
   self.r.TXDCTL:set(bits{SWFLSH=26})
   self.r.TXDCTL:wait(bits{Enable=25}, 0)
   self.pf.r.PFVFTE[math.floor(self.poolnum/32)]:clr(bits{VFTE=self.poolnum%32})

   if reenable then
      self.r.TXDCTL:set(bits({Enable=25, SWFLSH=26, hthresh=8}) + 32)
   --    self.r.TXDCTL:wait(bits{Enable=25})
   end
   return self
end

function M_vf:set_MAC (mac)
   if not mac then return self end
   mac = macaddress:new(mac)
   return self
      :add_receive_MAC(mac)
      :set_transmit_MAC(mac)
end

function M_vf:unset_MAC()
end

function M_vf:add_receive_MAC (mac)
   mac = macaddress:new(mac)
   local pf = self.pf
   local mac_index, is_new = pf.mac_set:add(tostring(mac))
   if is_new then
      pf.r.RAL[mac_index](mac:subbits(0,32))
      pf.r.RAH[mac_index](bits({AV=31},mac:subbits(32,48)))
   end
   pf.r.MPSAR[2*mac_index + math.floor(self.poolnum/32)]
      :set(bits{Ena=self.poolnum%32})

   return self
end

function M_vf:set_transmit_MAC (mac)
   local poolnum = self.poolnum or 0
   self.pf.r.PFVFSPOOF[math.floor(poolnum/8)]:set(bits{MACAS=poolnum%8})
   return self
end

function M_vf:set_mirror (want_mirror)
   if want_mirror then
      -- set MAC promiscuous
      self.pf.r.PFVML2FLT[self.poolnum]:set(bits{
         AUPE=24, ROMPE=25, ROPE=26, BAM=27, MPE=28})

      -- pick one of a limited (4) number of mirroring rules
      local mirror_ndx, is_new = self.pf.mirror_set:add(self.poolnum)
      local mirror_rule = 0ULL

      -- mirror some or all pools
      if want_mirror.pool then
         mirror_rule = bor(bits{VPME=0}, mirror_rule)
         if want_mirror.pool == true then       -- mirror all pools
            self.pf.r.PFMRVM[mirror_ndx](0xFFFFFFFF)
            self.pf.r.PFMRVM[mirror_ndx+4](0xFFFFFFFF)
         elseif type(want_mirror.pool) == 'table' then
            local bm0 = self.pf.r.PFMRVM[mirror_ndx]
            local bm1 = self.pf.r.PFMRVM[mirror_ndx+4]
            for _, pool in ipairs(want_mirror.pool) do
               if pool <= 32 then
                  bm0 = bor(lshift(1, pool), bm0)
               else
                  bm1 = bor(lshift(1, pool-32), bm1)
               end
            end
            self.pf.r.PFMRVM[mirror_ndx](bm0)
            self.pf.r.PFMRVM[mirror_ndx+4](bm1)
         end
      end

      -- mirror hardware port
      if want_mirror.port then
         if want_mirror.port == true or want_mirror.port == 'in' or want_mirror.port == 'inout' then
            mirror_rule = bor(bits{UPME=1}, mirror_rule)
         end
         if want_mirror.port == true or want_mirror.port == 'out' or want_mirror.port == 'inout' then
            mirror_rule = bor(bits{DPME=2}, mirror_rule)
         end
      end

      -- mirror some or all vlans
      if want_mirror.vlan then
         mirror_rule = bor(bits{VLME=3}, mirror_rule)
            -- TODO: set which vlan's want to mirror
      end
      if mirror_rule ~= 0 then
         mirror_rule = bor(mirror_rule, lshift(self.poolnum, 8))
         self.pf.r.PFMRCTL[mirror_ndx]:set(mirror_rule)
      end
   end
   return self
end

function M_vf:unset_mirror()
   for rule_i = 0, 3 do
      -- check if any mirror rule points here
      local rule_dest = band(bit.rshift(self.pf.r.PFMRCTL[rule_i](), 8), 63)
      local bits = band(self.pf.r.PFMRCTL[rule_i](), 0x07)
      if bits ~= 0 and rule_dest == self.poolnum then
         self.pf.r.PFMRCTL[rule_i](0x0)     -- clear rule
         self.pf.r.PFMRVLAN[rule_i](0x0)    -- clear VLANs mirrored
         self.pf.r.PFMRVLAN[rule_i+4](0x0)
         self.pf.r.PFMRVM[rule_i](0x0)      -- clear pools mirrored
         self.pf.r.PFMRVM[rule_i+4](0x0)
      end
   end
   self.pf.mirror_set:pop(self.poolnum)
   return self
end

function M_vf:set_VLAN (vlan)
   if not vlan then return self end
   assert(vlan>=0 and vlan<4096, "bad VLAN number")
   return self
      :add_receive_VLAN(vlan)
      :set_tag_VLAN(vlan)
end

function M_vf:add_receive_VLAN (vlan)
   assert(vlan>=0 and vlan<4096, "bad VLAN number")
   local pf = self.pf
   local vlan_index, is_new = pf.vlan_set:add(vlan)
   if is_new then
      pf.r.VFTA[math.floor(vlan/32)]:set(bits{Ena=vlan%32})
      pf.r.PFVLVF[vlan_index](bits({Vl_En=31},vlan))
   end
   pf.r.PFVLVFB[2*vlan_index + math.floor(self.poolnum/32)]
      :set(bits{PoolEna=self.poolnum%32})
   return self
end
function M_vf:set_tag_VLAN(vlan)
   local poolnum = self.poolnum or 0
   self.pf.r.PFVFSPOOF[math.floor(poolnum/8)]:set(bits{VLANAS=poolnum%8+8})
   self.pf.r.PFVMVIR[poolnum](bits({VLANA=30}, vlan))  -- always add VLAN tag
   return self
end


function M_vf:unset_VLAN()
   local r = self.pf.r
   local offs, mask = math.floor(self.poolnum/32), bits{PoolEna=self.poolnum%32}

   for vln_ndx = 0, 63 do
      if band(r.PFVLVFB[2*vln_ndx+offs](), mask) ~= 0 then
         -- found a vlan this pool belongs to
         r.PFVLVFB[2*vln_ndx+offs]:clr(mask)
         if r.PFVLVFB[2*vln_ndx+offs]() == 0 then
            -- it was the last pool of the vlan
            local vlan = tonumber(band(r.PFVLVF[vln_ndx](), 0xFFF))
            r.PFVLVF[vln_ndx](0x0)
            r.VFTA[math.floor(vlan/32)]:clr(bits{Ena=vlan%32})
            self.pf.vlan_set:pop(vlan)
         end
      end
   end
   return self
end

function M_vf:set_rx_stats (counter)
   if not counter then return self end
   assert(counter>=0 and counter<16, "bad Rx counter")
   self.rxstats = counter
   self.pf.qs.RQSMR[math.floor(self.rxqn/4)]:set(lshift(counter,8*(self.rxqn%4)))
   return self
end

function M_vf:set_tx_stats (counter)
   if not counter then return self end
   assert(counter>=0 and counter<16, "bad Tx counter")
   self.txstats = counter
   self.pf.qs.TQSM[math.floor(self.txqn/4)]:set(lshift(counter,8*(self.txqn%4)))
   return self
end

function M_vf:get_rxstats ()
   return {
      counter_id = self.rxstats,
      packets = tonumber(self.pf.qs.QPRC[self.rxstats]()),
      dropped = tonumber(self.pf.qs.QPRDC[self.rxstats]()),
      bytes = tonumber(lshift(self.pf.qs.QBRC_H[self.rxstats]()+0LL, 32)
               + self.pf.qs.QBRC_L[self.rxstats]())
   }
end

function M_vf:get_txstats ()
   return {
      counter_id = self.txstats,
      packets = tonumber(self.pf.qs.QPTC[self.txstats]()),
      bytes = tonumber(lshift(self.pf.qs.QBTC_H[self.txstats]()+0LL, 32)
               + self.pf.qs.QBTC_L[self.txstats]())
   }
end

function M_vf:set_tx_rate (limit, priority)
   self.pf.r.RTTDQSEL(self.poolnum)
   if limit >= 10 then
      local factor = 10000 / tonumber(limit)       -- line rate = 10,000 Mb/s
      factor = bit.band(math.floor(factor*2^14+0.5), 2^24-1) -- 10.14 bits
      self.pf.r.RTTBCNRC(bits({RS_ENA=31}, factor))
   else
      self.pf.r.RTTBCNRC(0x00)
   end
   self.pf.r.RTTDT1C(bit.band(math.floor(priority * 0x80), 0x3FF))
   return self
end

function M_vf:rxdrop () return self.pf.qs.QPRDC[self.rxstats]() end

rxdesc_t = ffi.typeof [[
   union {
      struct {
         uint64_t address;
         uint64_t dd;
      } __attribute__((packed)) data;
      struct {
         uint16_t rsstype_packet_type;
         uint16_t rsccnt_hdrlen_sph;
         uint32_t xargs;
         uint32_t xstatus_xerror;
         uint16_t pkt_len;
         uint16_t vlan;
      } __attribute__((packed)) wb;
   }
]]

txdesc_t = ffi.typeof [[
   struct {
      uint64_t address, options;
   }
]]

--- ### Configuration register description.

config_registers_desc = [[
ANLP1     0x042B0 -            RO Auto Negotiation Link Partner
ANLP2     0x042B4 -            RO Auto Negotiation Link Partner 2
AUTOC     0x042A0 -            RW Auto Negotiation Control
AUTOC2    0x042A8 -            RW Auto Negotiation Control 2
CTRL      0x00000 -            RW Device Control
CTRL_EX   0x00018 -            RW Extended Device Control
DCA_ID    0x11070 -            RW DCA Requester ID Information
DCA_CTRL  0x11074 -            RW DCA Control Register
DMATXCTL  0x04A80 -            RW DMA Tx Control
DTXMXSZRQ 0x08100 -            RW DMA Tx Map Allow Size Requests
DTXTCPFLGL 0x04A88 -           RW DMA Tx TCP Flags Control Low
DTXTCPFLGH 0x04A88 -           RW DMA Tx TCP Flags Control High
EEC       0x10010 -            RW EEPROM/Flash Control
FCTRL     0x05080 -            RW Filter Control
FCCFG     0x03D00 -            RW Flow Control Configuration
HLREG0    0x04240 -            RW MAC Core Control 0
LINKS     0x042A4 -            RO Link Status Register
LINKS2    0x04324 -            RO Second status link register
MANC      0x05820 -            RW Management Control Register
MAXFRS    0x04268 -            RW Max Frame Size
MNGTXMAP  0x0CD10 -            RW Mangeability Tranxmit TC Mapping
MFLCN     0x04294 -            RW MAC Flow Control Register
MTQC      0x08120 -            RW Multiple Transmit Queues Command Register
MRQC      0x0EC80 -            RW Multiple Receive Queues Command Register
PFQDE     0x02F04 -            RW PF Queue Drop Enable Register
PFVTCTL   0x051B0 -             RW PF Virtual Control Register
RDRXCTL   0x02F00 -            RW Receive DMA Control
RTRUP2TC  0x03020 -            RW DCB Receive Use rPriority to Traffic Class
RTTBCNRC  0x04984 -            RW DCB Transmit Rate-Scheduler Config
RTTDCS    0x04900 -            RW DCB Transmit Descriptor Plane Control
RTTDQSEL  0x04904 -            RW DCB Transmit Descriptor Plane Queue Select
RTTDT1C   0x04908 -            RW DCB Transmit Descriptor Plane T1 Config
RTTUP2TC  0x0C800 -            RW DCB Transmit User Priority to Traffic Class
RXCTRL    0x03000 -            RW Receive Control
RXDSTATCTRL 0x02F40 -          RW Rx DMA Statistic Counter Control
SECRXCTRL 0x08D00 -            RW Security RX Control
SECRXSTAT 0x08D04 -            RO Security Rx Status
SECTXCTRL 0x08800 -            RW Security Tx Control
SECTXSTAT 0x08804 -            RO Security Tx Status
STATUS    0x00008 -            RO Device Status
SWSM      0x10140 -            RW Software Semaphore Register
SW_FW_SYNC 0x10160 -           RW Software–Firmware Synchronization
]]

switch_config_registers_desc = [[
PFMRCTL   0x0F600 +0x04*0..3    RW PF Mirror Rule Control
PFMRVLAN  0x0F610 +0x04*0..7    RW PF mirror Rule VLAN
PFMRVM    0x0F630 +0x04*0..7    RW PF Mirror Rule Pool
PFVFRE    0x051E0 +0x04*0..1    RW PF VF Receive Enable
PFVFTE    0x08110 +0x04*0..1    RW PF VF Transmit Enable
PFVMTXSW  0x05180 +0x04*0..1    RW PF VM Tx Switch Loopback Enable
PFVMVIR   0x08000 +0x04*0..63   RW PF VM VLAN Insert Register
PFVFSPOOF 0x08200 +0x04*0..7    RW PF VF Anti Spoof control
PFDTXGSWC 0x08220 -             RW PFDMA Tx General Switch Control
RTTDT2C   0x04910 +0x04*0..7    RW DCB Transmit Descriptor Plane T2 Config
RTTPT2C   0x0CD20 +0x04*0..7    RW DCB Transmit Packet Plane T2 Config
RXPBSIZE  0x03C00 +0x04*0..7    RW Receive Packet Buffer Size
TXPBSIZE  0x0CC00 +0x04*0..7    RW Transmit Packet Buffer Size
TXPBTHRESH 0x04950 +0x04*0..7   RW Tx Packet Buffer Threshold
]]

receive_registers_desc = [[
DCA_RXCTRL 0x0100C +0x40*0..63   RW Rx DCA Control Register
DCA_RXCTRL 0x0D00C +0x40*64..127 RW Rx DCA Control Register
RDBAL      0x01000 +0x40*0..63   RW Receive Descriptor Base Address Low
RDBAL      0x0D000 +0x40*64..127 RW Receive Descriptor Base Address Low
RDBAH      0x01004 +0x40*0..63   RW Receive Descriptor Base Address High
RDBAH      0x0D004 +0x40*64..127 RW Receive Descriptor Base Address High
RDLEN      0x01008 +0x40*0..63   RW Receive Descriptor Length
RDLEN      0x0D008 +0x40*64..127 RW Receive Descriptor Length
RDH        0x01010 +0x40*0..63   RO Receive Descriptor Head
RDH        0x0D010 +0x40*64..127 RO Receive Descriptor Head
RDT        0x01018 +0x40*0..63   RW Receive Descriptor Tail
RDT        0x0D018 +0x40*64..127 RW Receive Descriptor Tail
RXDCTL     0x01028 +0x40*0..63   RW Receive Descriptor Control
RXDCTL     0x0D028 +0x40*64..127 RW Receive Descriptor Control
SRRCTL     0x01014 +0x40*0..63   RW Split Receive Control Registers
SRRCTL     0x0D014 +0x40*64..127 RW Split Receive Control Registers
RSCCTL     0x0102C +0x40*0..63   RW RSC Control
RSCCTL     0x0D02C +0x40*64..127 RW RSC Control
]]

transmit_registers_desc = [[
DCA_TXCTRL 0x0600C +0x40*0..127 RW Tx DCA Control Register
TDBAL      0x06000 +0x40*0..127 RW Transmit Descriptor Base Address Low
TDBAH      0x06004 +0x40*0..127 RW Transmit Descriptor Base Address High
TDH        0x06010 +0x40*0..127 RW Transmit Descriptor Head
TDT        0x06018 +0x40*0..127 RW Transmit Descriptor Tail
TDLEN      0x06008 +0x40*0..127 RW Transmit Descriptor Length
TDWBAL     0x06038 +0x40*0..127 RW Tx Desc Completion Write Back Address Low
TDWBAH     0x0603C +0x40*0..127 RW Tx Desc Completion Write Back Address High
TXDCTL     0x06028 +0x40*0..127 RW Transmit Descriptor Control
]]

packet_filter_desc = [[
FCTRL     0x05080 -             RW Filter Control Register
FCRTL     0x03220 +0x04*0..7    RW Flow Control Receive Threshold Low
FCRTH     0x03260 +0x04*0..7    RW Flow Control Receive Threshold High
VLNCTRL   0x05088 -             RW VLAN Control Register
MCSTCTRL  0x05090 -             RW Multicast Control Register
PSRTYPE   0x0EA00 +0x04*0..63   RW Packet Split Receive Type Register
RXCSUM    0x05000 -             RW Receive Checksum Control
RFCTL     0x05008 -             RW Receive Filter Control Register
PFVFRE    0x051E0 +0x04*0..1    RW PF VF Receive Enable
PFVFTE    0x08110 +0x04*0..1    RW PF VF Transmit Enable
MTA       0x05200 +0x04*0..127  RW Multicast Table Array
RAL       0x0A200 +0x08*0..127  RW Receive Address Low
RAH       0x0A204 +0x08*0..127  RW Receive Address High
MPSAR     0x0A600 +0x04*0..255  RW MAC Pool Select Array
VFTA      0x0A000 +0x04*0..127  RW VLAN Filter Table Array
RQTC      0x0EC70 -             RW RSS Queues Per Traffic Class Register
RSSRK     0x0EB80 +0x04*0..9    RW RSS Random Key Register
RETA      0x0EB00 +0x04*0..31   RW Redirection Rable
SAQF      0x0E000 +0x04*0..127  RW Source Address Queue Filter
DAQF      0x0E200 +0x04*0..127  RW Destination Address Queue Filter
SDPQF     0x0E400 +0x04*0..127  RW Source Destination Port Queue Filter
FTQF      0x0E600 +0x04*0..127  RW Five Tuple Queue Filter
SYNQF     0x0EC30 -             RW SYN Packet Queue Filter
ETQF      0x05128 +0x04*0..7    RW EType Queue Filter
ETQS      0x0EC00 +0x04*0..7    RW EType Queue Select
PFVML2FLT 0x0F000 +0x04*0..63   RW PF VM L2 Control Register
PFVLVF    0x0F100 +0x04*0..63   RW PF VM VLAN Pool Filter
PFVLVFB   0x0F200 +0x04*0..127  RW PF VM VLAN Pool Filter Bitmap
PFUTA     0X0F400 +0x04*0..127  RW PF Unicast Table Array
]]
--- ### Statistics register description.

statistics_registers_desc = [[
CRCERRS       0x04000 -           RC CRC Error Count
ILLERRC       0x04004 -           RC Illegal Byte Error Count
ERRBC         0x04008 -           RC Error Byte Count
MLFC          0x04034 -           RC MAC Local Fault Count
MRFC          0x04038 -           RC MAC Remote Fault Count
RLEC          0x04040 -           RC Receive Length Error Count
SSVPC         0x08780 -           RC Switch Security Violation Packet Count
LXONRXCNT     0x041A4 -           RC Link XON Received Count
LXOFFRXCNT    0x041A8 -           RC Link XOFF Received Count
PXONRXCNT     0x04140 +4*0..7     RC Priority XON Received Count
PXOFFRXCNT    0x04160 +4*0..7     RC Priority XOFF Received Count
PRC64         0x0405C -           RC Packets Received [64 Bytes] Count
PRC127        0x04060 -           RC Packets Received [65-127 Bytes] Count
PRC255        0x04064 -           RC Packets Received [128-255 Bytes] Count
PRC511        0x04068 -           RC Packets Received [256-511 Bytes] Count
PRC1023       0x0406C -           RC Packets Received [512-1023 Bytes] Count
PRC1522       0x04070 -           RC Packets Received [1024 to Max Bytes] Count
BPRC          0x04078 -           RC Broadcast Packets Received Count
MPRC          0x0407C -           RC Multicast Packets Received Count
GPRC          0x04074 -           RC Good Packets Received Count
GORC64        0x04088 -           RC64 Good Octets Received Count 64-bit
GORCL         0x04088 -           RC Good Octets Received Count Low
GORCH         0x0408C -           RC Good Octets Received Count High
RXNFGPC       0x041B0 -           RC Good Rx Non-Filtered Packet Counter
RXNFGBCL      0x041B4 -           RC Good Rx Non-Filter Byte Counter Low
RXNFGBCH      0x041B8 -           RC Good Rx Non-Filter Byte Counter High
RXDGPC        0x02F50 -           RC DMA Good Rx Packet Counter
RXDGBCL       0x02F54 -           RC DMA Good Rx Byte Counter Low
RXDGBCH       0x02F58 -           RC DMA Good Rx Byte Counter High
RXDDPC        0x02F5C -           RC DMA Duplicated Good Rx Packet Counter
RXDDBCL       0x02F60 -           RC DMA Duplicated Good Rx Byte Counter Low
RXDDBCH       0x02F64 -           RC DMA Duplicated Good Rx Byte Counter High
RXLPBKPC      0x02F68 -           RC DMA Good Rx LPBK Packet Counter
RXLPBKBCL     0x02F6C -           RC DMA Good Rx LPBK Byte Counter Low
RXLPBKBCH     0x02F70 -           RC DMA Good Rx LPBK Byte Counter High
RXDLPBKPC     0x02F74 -           RC DMA Duplicated Good Rx LPBK Packet Counter
RXDLPBKBCL    0x02F78 -           RC DMA Duplicated Good Rx LPBK Byte Counter Low
RXDLPBKBCH    0x02F7C -           RC DMA Duplicated Good Rx LPBK Byte Counter High
GPTC          0x04080 -           RC Good Packets Transmitted Count
GOTC64        0x04090 -           RC64 Good Octets Transmitted Count 64-bit
GOTCL         0x04090 -           RC Good Octets Transmitted Count Low
GOTCH         0x04094 -           RC Good Octets Transmitted Count High
TXDGPC        0x087A0 -           RC DMA Good Tx Packet Counter
TXDGBCL       0x087A4 -           RC DMA Good Tx Byte Counter Low
TXDGBCH       0x087A8 -           RC DMA Good Tx Byte Counter High
RUC           0x040A4 -           RC Receive Undersize Count
RFC           0x040A8 -           RC Receive Fragment Count
ROC           0x040AC -           RC Receive Oversize Count
RJC           0x040B0 -           RC Receive Jabber Count
MNGPRC        0x040B4 -           RC Management Packets Received Count
MNGPDC        0x040B8 -           RC Management Packets Dropped Count
TORL          0x040C0 -           RC Total Octets Received
TORH          0x040C4 -           RC Total Octets Received
TPR           0x040D0 -           RC Total Packets Received
TPT           0x040D4 -           RC Total Packets Transmitted
PTC64         0x040D8 -           RC Packets Transmitted [64 Bytes] Count
PTC127        0x040DC -           RC Packets Transmitted [65-127 Bytes] Count
PTC255        0x040E0 -           RC Packets Transmitted [128-255 Bytes] Count
PTC511        0x040E4 -           RC Packets Transmitted [256-511 Bytes] Count
PTC1023       0x040E8 -           RC Packets Transmitted [512-1023 Bytes] Count
PTC1522       0x040EC -           RC Packets Transmitted [Greater than 1024 Bytes] Count
MPTC          0x040F0 -           RC Multicast Packets Transmitted Count
BPTC          0x040F4 -           RC Broadcast Packets Transmitted Count
MSPDC         0x04010 -           RC MAC short Packet Discard Count
XEC           0x04120 -           RC XSUM Error Count
FCCRC         0x05118 -           RC FC CRC Error Count
FCOERPDC      0x0241C -           RC FCoE Rx Packets Dropped Count
FCLAST        0x02424 -           RC FC Last Error Count
FCOEPRC       0x02428 -           RC FCoE Packets Received Count
FCOEDWRC      0x0242C -           RC FCOE DWord Received Count
FCOEPTC       0x08784 -           RC FCoE Packets Transmitted Count
FCOEDWTC      0x08788 -           RC FCoE DWord Transmitted Count
]]

queue_statistics_registers_desc = [[
RQSMR         0x02300 +0x4*0..31  RW Receive Queue Statistic Mapping Registers
TQSM          0x08600 +0x4*0..31  RW Transmit Queue Statistic Mapping Registers
QPRC          0x01030 +0x40*0..15 RC Queue Packets Received Count
QPRDC         0x01430 +0x40*0..15 RC Queue Packets Received Drop Count
QBRC_L        0x01034 +0x40*0..15 RC Queue Bytes Received Count Low
QBRC_H        0x01038 +0x40*0..15 RC Queue Bytes Received Count High
QPTC          0x08680 +0x4*0..15  RC Queue Packets Transmitted Count
QBTC_L        0x08700 +0x8*0..15  RC Queue Bytes Transmitted Count Low
QBTC_H        0x08704 +0x8*0..15  RC Queue Bytes Transmitted Count High
]]
