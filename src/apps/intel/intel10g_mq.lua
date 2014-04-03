--- multiqueue version of the Intel 82599 driver

module(...,package.seeall)

local ffi      = require "ffi"
local C        = ffi.C
local lib      = require("core.lib")
-- local memory   = require("core.memory")
local packet   = require("core.packet")
local bus      = require("lib.hardware.bus")
local register = require("lib.hardware.register")
                 require("apps.intel.intel_h")
                 require("core.packet_h")

local bits, bitset = lib.bits, lib.bitset

num_descriptors = 32 * 1024

function new (self, pciaddress)
   local dev = { pciaddress = pciaddress, -- PCI device address
                 info = bus.device_info(pciaddress),
                 r = {},           -- Configuration registers
                 s = {},           -- Statistics registers
                 qs = {},          -- queue statistic registers
                 mac_set = lib.new_index_set(127, "MAC address table"),
                 vlan_set = lib.new_index_set(64, "VLAN Filter table"),
                 mirror_set = lib.new_index_set(4, "Mirror pool table"),
              }
   setmetatable(dev, {__index = self})
   return dev:open()
end


function _M:open()
   self.info.set_bus_master(self.pciaddress, true)
   self.base = self.info.map_pci_memory(self.pciaddress, 0)
   register.define(config_registers_desc, self.r, self.base)
   register.define_array(switch_config_registers_desc, self.r, self.base)
   register.define_array(packet_filter_desc, self.r, self.base)
   register.define(statistics_registers_desc, self.s, self.base)
   register.define_array(queue_statistics_registers_desc, self.qs, self.base)
   return self:init()
end


function _M:init()
   return self
--       :init_dma_memory()
      :disable_interrupts()
      :global_reset()
--       :set_mac_loopback()
      :autonegotiate_sfi()
      :wait_eeprom_autoread()
      :wait_dma()
      :set_vmdq_mode()
      :init_statistics()
      :init_receive()
      :init_transmit()
      :wait_link_up()
end


function _M:disable_interrupts ()
   return self              -- TODO
end


function _M:global_reset ()
   self.r.RXPBSIZE[0](0x80000)          -- no DCB: all queues to PB0
   self.r.TXPBSIZE[0](0x28000)
   self.r.TXPBTHRESH[0](0xA0)
   for i = 0, 127 do                    -- clear MTA/PFUTA tables
      self.r.MTA[i](0)
      self.r.PFUTA[i](0)
   end
   self.r.FCRTH[0](0x10000)
   for i = 1, 7 do
      self.r.RXPBSIZE[i](0x00)
      self.r.TXPBSIZE[i](0x00)
      self.r.TXPBTHRESH[i](0x00)
   end
   local reset = bits{LinkReset=3, DeviceReset=26}
   self.r.CTRL(reset)
   ffi.C.usleep(1000)
   self.r.CTRL:wait(reset, 0)
   return self
end


function _M:wait_eeprom_autoread ()
   self.r.EEC:wait(bits{AutoreadDone=9})
   return self
end


function _M:wait_dma ()
   self.r.RDRXCTL:wait(bits{DMAInitDone=3})
   return self
end


function _M:force_SFI()
   self.r.AUTOC:set(bits{FLU=0, LMS10G_SFIa=13, LMS10G_SFIb=14})
   return self
end


function _M:set_mac_loopback()
--    self.r.AUTOC:set(bits{FLU=0, LMS10G_SFIa=13, LMS10G_SFIb=14})
   self.r.HLREG0:set(bits{LPBK=15})
   return self
end


function _M:negotiated_autoc(f)
   lib.waitfor(function()
      local accessible = false
      self.r.SWSM:wait(bits{SMBI=0})        -- TODO: expire at 10ms
      self.r.SWSM:set(bits{SWESMBI=1})
      self.r.SWSM:wait(bits{SWESMBI=1})     -- TODO: expire at 3s
      accessible = bit.band(self.r.SW_FW_SYNC(), 0x8) == 0
      if accessible then
         self.r.SW_FW_SYNC:set(0x8)
      end
      self.r.SWSM:clr(bits{SMBI=0, SWESMBI=1})
      if not accessible then C.usleep(3000000) end
      return accessible
   end)   -- TODO: only twice
   local r = f(self)
   self.r.SWSM:wait(bits{SMBI=0})        -- TODO: expire at 10ms
   self.r.SWSM:set(bits{SWESMBI=1})
   self.r.SWSM:wait(bits{SWESMBI=1})     -- TODO: expire at 3s
   self.r.SW_FW_SYNC:clr(0x8)
   self.r.SWSM:clr(bits{SMBI=0, SWESMBI=1})
   return r
end


function _M:set_SFI()
   local autoc = self.r.AUTOC()
   autoc = bit.bor(
      bit.band(autoc, 0xFFFF0C7E),          -- clears FLU, 10g_pma, 1g_pma, restart_AN, LMS
      bit.lshift(0x3, 13)                   -- LMS(15:13) = 011b
   )
   self.r.AUTOC(autoc)                       -- TODO: firmware synchronization
   return self
end

function _M:autonegotiate_sfi()
   return self:negotiated_autoc(function()
      self:set_SFI()
      self.r.AUTOC:set(bits{restart_AN=12})
      self.r.AUTOC2(0x00020000)
      return self
   end)
end


function _M:set_vmdq_mode()
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
      self.r.PFQDE(bit.bor(bit.lshift(1,16), bit.lshift(i,8)))
      self.r.FTQF[i](0x00)                 -- disable L3/4 filter
   end
   for i = 0, 63 do
      self.r.RTTDQSEL(i)
      self.r.RTTDT1C(0x00)
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


function _M:init_statistics ()
   -- Read and then zero each statistic register
   for _,reg in pairs(self.s) do reg:read() reg:reset() end
   return self
end


function _M:init_receive ()
   self.r.RXCTRL:clr(bits{RXEN=0})
   self:set_promiscuous_mode() -- NB: don't need to program MAC address filter
   self.r.RDRXCTL(bits({RSCACKC=25, FCOE_WRFIX=26}, 0x8800))
   self.r.HLREG0(bits{
      TXCRCEN=0, RXCRCSTRP=1, JUMBOEN=2, rsv2=3, TXPADEN=10,
      rsvd3=11, rsvd4=13, MDCSPD=16, RXLNGTHERREN=27,
   })
   self.r.CTRL_EX:set(bits{NS_DIS=16})
   self.r.RXCTRL:set(bits{RXEN=0})
   return self
end


function _M:set_promiscuous_mode ()
   self.r.FCTRL(bits({SBP=0, MPE=8, UPE=9, BAM=10}))
   return self
end


function _M:init_transmit ()
   self.r.HLREG0:set(bits{TXCRCEN=0, RXCRCSTRP=1})
   self.r.DMATXCTL:clr(bits{TE=0})
   return self
end


function _M:wait_link_up()
   self.r.LINKS:wait(bits{Link_up=30})
   return self
end


local M_vf = {}

function _M:new_pool(poolnum)
   local txqn = poolnum*2
   local rxqn = poolnum*2
   local vf = {
      pf = self,
      -- some things are shared with the main device...
      base = self.base,             -- mmap()ed register file
      s = self.s,                   -- Statistics registers
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
      rxbuffers = {},               -- Rx descriptor index -> buffer mapping
      rdh = 0,                      -- Cache of receive head (RDH) register
      rdt = 0,                      -- Cache of receive tail (RDT) register
      rxnext = 0,                   -- Index of next buffer to receive
   }
   setmetatable(vf, {__index = M_vf})
   return vf
end


function M_vf:open(opts)
   register.define(transmit_registers_desc, self.r, self.base, self.txqn)
   register.define(receive_registers_desc, self.r, self.base, self.rxqn)
   self.txpackets = ffi.new("struct packet *[?]", num_descriptors)
   self.rxbuffers = ffi.new("struct buffer *[?]", num_descriptors)
   return self:init(opts)
end


function M_vf:init(opts)
   return self
      :init_dma_memory()
      :init_receive()
      :init_transmit()
      :set_MAC(opts.macaddr)
--       :set_promisc(opts.promisc)
      :set_mirror(opts.mirror)
      :set_VLAN(opts.vlan)
      :set_rx_stats(opts.rxcounter)
      :set_tx_stats(opts.txcounter)
end


function M_vf:init_dma_memory ()
   self.rxdesc, self.rxdesc_phy =
      self.pf.info.dma_alloc(num_descriptors * ffi.sizeof(rxdesc_t))
   self.txdesc, self.txdesc_phy =
      self.pf.info.dma_alloc(num_descriptors * ffi.sizeof(txdesc_t))
   -- Add bounds checking
   self.rxdesc = lib.bounds_checked(rxdesc_t, self.rxdesc, 0, num_descriptors)
   self.txdesc = lib.bounds_checked(txdesc_t, self.txdesc, 0, num_descriptors)
   return self
end


function M_vf:init_receive ()
   local poolnum = self.poolnum or 0
   self.pf.r.PSRTYPE[poolnum](0)        -- no splitting, use pool's first queue
   self.r.RSCCTL(0x0)                   -- no RSC
   self.r.RDBAL(self.rxdesc_phy % 2^32)
   self.r.RDBAH(self.rxdesc_phy / 2^32)
   self.r.RDLEN(num_descriptors * ffi.sizeof(rxdesc_t))
   self.pf.r.PFVML2FLT[poolnum]:set(bits{BAM=27, AUPE=24})
   self.r.RXDCTL(bits{Enable=25})
   self.r.RXDCTL:wait(bits{enable=25})
--    self.r.SRRCTL(bits({Drop_En=28, DesctypeLSB=25}, 4))
   self.r.SRRCTL(bits({DesctypeLSB=25}, 4))
   self.r.DCA_RXCTRL:clr(bits{RxCTRL=12})
   self.pf.r.PFVFRE[math.floor(poolnum/32)]:set(bits{VFRE=poolnum%32})
   return self
end


function M_vf:init_transmit ()
   local poolnum = self.poolnum or 0
--    self.r.TXDCTL(12+(4*256))        -- PTHRESH=12, HTHRESH=4
   self.r.TXDCTL:clr(bits{Enable=25})
   self.r.TDBAL(self.txdesc_phy % 2^32)
   self.r.TDBAH(self.txdesc_phy / 2^32)
   self.r.TDLEN(num_descriptors * ffi.sizeof(txdesc_t))
   self.r.TDH(0)
   self.r.TDT(0)
   self.pf.r.PFVMTXSW[math.floor(poolnum/32)]:set(bits{LLE=poolnum%32})
   self.pf.r.PFVFTE[math.floor(poolnum/32)]:set(bits{VFTE=poolnum%32})
   self.pf.r.RTTDQSEL(poolnum)
   self.pf.r.RTTDT1C(0x2000)
   self.pf.r.RTTBCNRC(0x00)         -- no rate limiting
   self.pf.r.DMATXCTL:set(bits{TE=0})
   self.r.TXDCTL:set(bits{Enable=25, SWFLSH=26})
   self.r.TXDCTL:wait(bits{Enable=25})
   return self
end


function M_vf:set_MAC(mac)
   if not mac then return self end
   mac = lib.new_mac(mac)
   return self
      :add_receive_MAC(mac)
      :set_transmit_MAC(mac)
end


function M_vf:add_receive_MAC(mac)
   mac = lib.new_mac(mac)
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


function M_vf:set_transmit_MAC(mac)
   local poolnum = self.poolnum or 0
   self.pf.r.PFVFSPOOF[math.floor(poolnum/8)]:set(bits{MACAS=poolnum%8})
   return self
end


-- function M_vf:set_promisc(want_promisc)
--    if want_promisc then
--       self.pf.r.PFVML2FLT[self.poolnum]:set(bits{
--          AUPE=24, ROMPE=25, ROPE=26, BAM=27, MPE=28})
--
--       local mirror_ndx, is_new = self.pf.mirror_set:add(self.poolnum)
--       self.pf.r.PFMRCTL[mirror_ndx](bit.bor(
--          bits{VPME=0, UPME=1, DPME=2}, bit.lshift(self.poolnum, 8)))
--       self.pf.r.PFMRVM[mirror_ndx](0xFFFFFFFF)
--       self.pf.r.PFMRVM[mirror_ndx+4](0xFFFFFFFF)
--    end
--    return self
-- end

function M_vf:set_mirror(want_mirror)
   if want_mirror then
      -- set MAC promiscuous
      self.pf.r.PFVML2FLT[self.poolnum]:set(bits{
         AUPE=24, ROMPE=25, ROPE=26, BAM=27, MPE=28})

      -- pick one of a limited (4) number of mirroring rules
      local mirror_ndx, is_new = self.pf.mirror_set:add(self.poolnum)
      local mirror_rule = 0ULL

      -- mirror some or all pools
      if want_mirror.pool then
         mirror_rule = bit.bor(bits{VPME=0}, mirror_rule)
         if want_mirror.pool == true then       -- mirror all pools
            self.pf.r.PFMRVM[mirror_ndx](0xFFFFFFFF)
            self.pf.r.PFMRVM[mirror_ndx+4](0xFFFFFFFF)
         elseif type(want_mirror.pool) == 'table' then
            local bm0 = self.pf.r.PFMRVM[mirror_ndx]
            local bm1 = self.pf.r.PFMRVM[mirror_ndx+4]
            for _, pool in ipairs(want_mirror.pool) do
               if pool <= 32 then
                  bm0 = bit.bor(bit.lshift(1, pool), bm0)
               else
                  bm1 = bit.bor(bit.lshift(1, pool-32), bm1)
               end
            end
            self.pf.r.PFMRVM[mirror_ndx](bm0)
            self.pf.r.PFMRVM[mirror_ndx+4](bm1)
         end
      end

      -- mirror hardware port
      if want_mirror.port then
         if want_mirror.port == true or want_mirror.port == 'in' or want_mirror.port == 'inout' then
            mirror_rule = bit.bor(bits{UPME=1}, mirror_rule)
         end
         if want_mirror.port == true or want_mirror.port == 'out' or want_mirror.port == 'inout' then
            mirror_rule = bit.bor(bits{DPME=2}, mirror_rule)
         end
      end

      -- mirror some or all vlans
      if want_mirror.vlan then
         mirror_rule = bit.bor(bits{VLME=3}, mirror_rule)
            -- TODO: set which vlan's want to mirror
      end
      if mirror_rule ~= 0 then
         mirror_rule = bit.bor(mirror_rule, bit.lshift(self.poolnum, 8))
         self.pf.r.PFMRCTL[mirror_ndx]:set(mirror_rule)
      end
   end
   return self
end


function M_vf:set_VLAN(vlan)
   if not vlan then return self end

   assert(vlan>=0 and vlan<4096, "bad VLAN number")
   if not vlan then return self end
   return self
      :add_receive_VLAN(vlan)
      :set_tag_VLAN(vlan)
end



function M_vf:add_receive_VLAN(vlan)
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
   -- TODO
   return self
end


function M_vf:set_rx_stats(counter)
   if not counter then return self end
   assert(counter>=0 and counter<16, "bad Rx counter")
   self.rxstats = counter
   self.pf.qs.RQSMR[math.floor(self.rxqn/4)]:set(bit.lshift(counter,8*(self.rxqn%4)))
   return self
end


function M_vf:set_tx_stats(counter)
   if not counter then return self end
   assert(counter>=0 and counter<16, "bad Tx counter")
   self.txstats = counter
   self.pf.qs.TQSM[math.floor(self.txqn/4)]:set(bit.lshift(counter,8*(self.txqn%4)))
   return self
end


function M_vf:get_rxstats()
   if not self.rxstats then return nil end
   return {
      counter_id = self.rxstats,
      packets = tonumber(self.pf.qs.QPRC[self.rxstats]()),
      dropped = tonumber(self.pf.qs.QPRDC[self.rxstats]()),
      bytes = tonumber(bit.lshift(self.pf.qs.QBRC_H[self.rxstats]()+0LL, 32)
               + self.pf.qs.QBRC_L[self.rxstats]())
   }
end


function M_vf:get_txstats()
   if not self.txstats then return nil end
   return {
      counter_id = self.txstats,
      packets = tonumber(self.pf.qs.QPTC[self.txstats]()),
      bytes = tonumber(bit.lshift(self.pf.qs.QBTC_H[self.txstats]()+0LL, 32)
               + self.pf.qs.QBTC_L[self.txstats]())
   }
end


function M_vf:can_receive ()
   return (self.rdh ~= self.rxnext) and bit.band(self.rxdesc[self.rxnext].wb.xstatus_xerror, 1) == 1
   -- return dev.rxnext ~= dev.rdh
end

--- ### Receive

--- See datasheet section 7.1 "Inline Functions -- Receive Functionality."

function M_vf:receive ()
   assert(self.rdh ~= self.rxnext)
   local p = packet.allocate()
   local b = self.rxbuffers[self.rxnext]
   local wb = self.rxdesc[self.rxnext].wb
   assert(wb.pkt_len> 0)
   assert(bit.band(wb.xstatus_xerror, 1) == 1) -- Descriptor Done
   packet.add_iovec(p, b, wb.pkt_len)
   self.rxnext = (self.rxnext + 1) % num_descriptors
   return p
end


function M_vf:can_add_receive_buffer ()
   return (self.rdt + 1) % num_descriptors ~= self.rxnext
end


function M_vf:can_transmit()
   return (self.tdt + 1) % num_descriptors ~= self.tdh
end


function M_vf:add_receive_buffer (b)
   assert(self:can_add_receive_buffer())
   local desc = self.rxdesc[self.rdt].data
   desc.address, desc.header_address = b.physical, b.physical  --, b.size
   self.rxbuffers[self.rdt] = b
   self.rdt = (self.rdt + 1) % num_descriptors
end


function M_vf:sync_receive ()
   -- XXX I have been surprised to see RDH = num_descriptors,
   --     must check what that means. -luke
   self.rdh = math.min(self.r.RDH(), num_descriptors-1)
   assert(self.rdh < num_descriptors)
   C.full_memory_barrier()
   self.r.RDT(self.rdt)
end


local txdesc_flags = bits{eop=24,ifcs=25, dext=29, dtyp0=20, dtyp1=21}
function M_vf:transmit (p)
   assert(p.niovecs == 1, "only supports one-buffer packets")
   local iov = p.iovecs[0]
   assert(iov.offset == 0)
   self.txdesc[self.tdt].address = iov.buffer.physical + iov.offset
   self.txdesc[self.tdt].options = bit.bor(iov.length, txdesc_flags, bit.lshift(iov.length+0ULL, 46))
   self.txpackets[self.tdt] = p
   self.tdt = (self.tdt + 1) % num_descriptors
   return packet.ref(p)
end


function M_vf:sync_transmit ()
   local old_tdh = self.tdh
   self.tdh = self.r.TDH()
   C.full_memory_barrier()
   -- Release processed buffers
   while old_tdh ~= self.tdh do
      packet.deref(self.txpackets[old_tdh])
      self.txpackets[old_tdh] = nil
      old_tdh = (old_tdh + 1) % num_descriptors
   end
   self.r.TDT(self.tdt)
end


rxdesc_t = ffi.typeof [[
   union {
      struct {
         uint64_t address;
         uint64_t header_address;
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
MNGTXMAP  0x0CD10 -            RW Mangeability Tranxmit TC Mapping
MFLCN     0x04294 -            RW MAC Flow Control Register
PFQDE     0x02F04 -            RW PF Queue Drop Enable Register
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
PFVFSPOOF 0x08200 +0x04*0..7    RW PF VF Anti Spoof control
PFDTXGSWC 0x08220 -             RW PFDMA Tx General Switch Control
RTTDT2C   0x04910 +0x04*0..7    RW DCB Transmit Descriptor Plane T2 Config
RTTPT2C   0x0CD20 +0x04*0..7    RW DCB Transmit Packet Plane T2 Config
RXPBSIZE  0X03C00 +0x04*0..7    RW Receive Packet Buffer Size
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
PFVTCTL   0x051B0 -             RW PF Virtual Control Register
PFVFRE    0x051E0 +0x04*0..1    RW PF VF Receive Enable
PFVFTE    0x08110 +0x04*0..1    RW PF VF Transmit Enable
MTA       0x05200 +0x04*0..127  RW Multicast Table Array
RAL       0x0A200 +0x08*0..127  RW Receive Address Low
RAH       0x0A204 +0x08*0..127  RW Receive Address High
MPSAR     0x0A600 +0x04*0..127  RW MAC Pool Select Array
VFTA      0x0A000 +0x04*0..127  RW VLAN Filter Table Array
MTQC      0x08120 -             RW Multiple Transmit Queues Command Register
MRQC      0x0EC80 -             RW Multiple Receive Queues Command Register
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


function selftest()
   local pf1 = new('0000:05:00.0')
   local vf1 = pf1:new_pool(0):open{}
   p ('ok')
end
