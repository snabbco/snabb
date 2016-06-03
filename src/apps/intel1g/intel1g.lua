-- intel1g: Device driver app for Intel 1G network cards
-- This is a device driver for Intel i210, i350 families of 1G network cards.
--
-- The driver supports multiple processes connecting to the same physical nic.
-- Per process RX / TX queues are available via RSS. Statistics collection
-- processes can read counter registers
--
-- Data sheets (reference documentation):
-- http://www.intel.com/content/dam/www/public/us/en/documents/datasheets/ethernet-controller-i350-datasheet.pdf
-- http://www.intel.com/content/dam/www/public/us/en/documents/datasheets/i210-ethernet-controller-datasheet.pdf
-- Note: section and page numbers in the comments below refer to the i210 data sheet

module(..., package.seeall)

local ffi = require("ffi")
local C   = ffi.C
local pci = require("lib.hardware.pci")
local band, bor, lshift = bit.band, bit.bor, bit.lshift
local lib  = require("core.lib")
local bits = lib.bits
local tophysical = core.memory.virtual_to_physical
local register = require("lib.hardware.register")

Intel1g = {}
-- It's not clear what address to use for EEMNGCTL_i210 DPDK PMD / linux e1000
-- both use 1010 but the docs say 12030
-- https://sourceforge.net/p/e1000/mailman/message/34457421/
-- http://dpdk.org/browse/dpdk/tree/drivers/net/e1000/base/e1000_regs.h

reg = { }
reg.gbl = {
   array = [[
RETA   0x5c00 +0x04*0..31 RW Redirection Table
RSSRK  0x5C80 +0x04*0..9 RW RSS Random Key
]],
   singleton = [[
CTRL      0x00000 -            RW Device Control
CTRL_EXT  0x00018 -            RW Extended Device Control
EEER      0x00E30 -            RW Energy Efficient Ethernet (EEE) Register
EIMC      0x01528 -            RW Extended Interrupt Mask Clear
MANC      0x05820 -            RW Management Control
MDIC      0x00020 -            RW MDI Control
MDICNFG   0x00E04 -            RW MDI Configuration
MRQC      0x05818 -            RW Multiple Receive Queues Command Register
RCTL      0x00100 -            RW RX Control
STATUS    0x00008 -            RO Device Status
SWSM      0x05b50 -            RW Software Semaphore
SW_FW_SYNC 0x05b5c -           RW Software Firmware Synchronization
TCTL      0x00400 -            RW TX Control
TCTL_EXT  0x00400 -            RW Extended TX Control
]]
}
reg['1000BaseX'] = {
   array = [[
ALLRXDCTL 0xc028 +0x40*0..7 RW Re Descriptor Control Queue
]],
   inherit = "gbl",
   rxq = [[
RDBAL  0xc000 +0x40*0..7 RW Rx Descriptor Base low
RDBAH  0xc004 +0x40*0..7 RW Rx Descriptor Base High
RDLEN  0xc008 +0x40*0..7 RW Rx Descriptor Ring Length
RDH    0xc010 +0x40*0..7 RO Rx Descriptor Head
RDT    0xc018 +0x40*0..7 RW Rx Descriptor Tail
RXDCTL 0xc028 +0x40*0..7 RW Re Descriptor Control Queue
RXCTL  0xc014 +0x40*0..7 RW RX DCA CTRL Register Queue
SRRCTL 0xc00c +0x40*0..7 RW Split and Replication Receive Control
]],
   txq = [[
TDBAL  0xe000 +0x40*0..7 RW Tx Descriptor Base Low
TDBAH  0xe004 +0x40*0..7 RW Tx Descriptor Base High
TDLEN  0xe008 +0x40*0..7 RW Tx Descriptor Ring Length
TDH    0xe010 +0x40*0..7 RO Tx Descriptor Head
TDT    0xe018 +0x40*0..7 RW Tx Descriptor Tail
TXDCTL 0xe028 +0x40*0..7 RW Tx Descriptor Control Queue
TXCTL  0xe014 +0x40*0..7 RW Tx DCA CTRL Register Queue
]]
}
reg.i210 = {
   inherit = "1000BaseX",
   singleton = [[
EEMNGCTL  0x12030 -            RW Manageability EEPROM-Mode Control Register
EEC       0x12010 -            RW EEPROM-Mode Control Register
]]
}
reg.i350 = {
   inherit = "1000BaseX",
   singleton = [[
EEMNGCTL  0x01010 -            RW Manageability EEPROM-Mode Control Register
EEC       0x00010 -            RW EEPROM-Mode Control Register
]]
}

function Intel1g:init_phy ()
   -- 4.3.1.4 PHY Reset
   self.r.MANC:wait(bits { BLK_Phy_Rst_On_IDE = 18 }, 0)

   -- 4.6.1  Acquiring Ownership Over a Shared Resource
   self:lock_fw_sem()
   self.r.SW_FW_SYNC:wait(bits { SW_PHY_SM = 1 }, 0)
   self.r.SW_FW_SYNC:set(bits { SW_PHY_SM = 1 })
   self:unlock_fw_sem()

   self.r.CTRL:set(bits { PHYreset = 31 })
   C.usleep(1*100)
   self.r.CTRL:clr(bits { PHYreset = 31 })

   -- 4.6.2 Releasing Ownership Over a Shared Resource
   self:lock_fw_sem()
   self.r.SW_FW_SYNC:clr(bits { SW_PHY_SM = 1 })
   self:unlock_fw_sem()

   self.r.EEMNGCTL:wait(bits { CFG_DONE0 = 18 })

   --[[
   self:lock_fw_sem()
   self.r.SW_FW_SYNC:wait(bits { SW_PHY_SM = 1}, 0)
   self.r.SW_FW_SYNC:set(bits { SW_PHY_SM = 1 })
   self:unlock_fw_sem()

   -- If you where going to configure the PHY to none defaults
   -- this is where you would do it

   self:lock_fw_sem()
   self.r.SW_FW_SYNC:clr(bits { SW_PHY_SM = 1 })
   self:unlock_fw_sem()
   ]]
end
function Intel1g:lock_sw_sem()
   for i=1,50,1 do
      if band(self.r.SWSM(), 0x01) == 1 then
         C.usleep(10000)
      else
         return
      end
   end
   error("Couldn't get lock")
end
function Intel1g:unlock_sw_sem()
   self.r.SWSM:clr(bits { SMBI = 0 })
end
function Intel1g:lock_fw_sem()
   self.r.SWSM:set(bits { SWESMBI = 1 })
   while band(self.r.SWSM(), 0x02) == 0 do
      self.r.SWSM:set(bits { SWESMBI = 1 })
   end
end
function Intel1g:unlock_fw_sem()
   self.r.SWSM:clr(bits { SWESMBI = 1 })
end

function Intel1g:disable_interrupts ()
   self.r.EIMC(0xffffffff)
end
function Intel1g:init_rx_q ()
   if not self.rxq then return end
   assert((self.rxq >=0) and (self.rxq < self.ringSize),
   "rxqueue must be in 0.." .. self.ringSize-1 .. " for " .. self.model)
   assert((self.ndesc %128) ==0,
   "ndesc must be a multiple of 128 (for Rx only)")	-- see 7.1.4.5

   self.rxpackets = {}
   self.rdh = 0
   self.rdt = 0
   -- setup 4.5.9
   local rxdesc_t = ffi.typeof([[
   struct {
      uint64_t address;
      uint16_t length, cksum;
      uint8_t status, errors;
      uint16_t vlan;
   } __attribute__((packed))
   ]])
   assert(ffi.sizeof(rxdesc_t),
   "sizeof(rxdesc_t)= ".. ffi.sizeof(rxdesc_t) .. ", but must be 16 Byte")
   local rxdesc_ring_t = ffi.typeof("$[$]", rxdesc_t, self.ndesc)
   self.rxdesc = ffi.cast(ffi.typeof("$&", rxdesc_ring_t),
   memory.dma_alloc(ffi.sizeof(rxdesc_ring_t)))
   -- Receive state
   self.r.RDBAL(tophysical(self.rxdesc) % 2^32)
   self.r.RDBAH(tophysical(self.rxdesc) / 2^32)
   self.r.RDLEN(self.ndesc * ffi.sizeof(rxdesc_t))

   for i = 0, self.ndesc-1 do
      local p= packet.allocate()
      self.rxpackets[i]= p
      self.rxdesc[i].address= tophysical(p.data)
      self.rxdesc[i].status= 0
   end
   self.r.SRRCTL(0)
   self.r.SRRCTL:set(bits {
      BSIZEPACKET1 = 1,   -- Set packet buff size to 0b1010 kbytes
      BSIZEPACKET3 = 3,
      Drop_En = 31        -- Drop packets when no descriptors
   })
   self:lock_sw_sem()
   self.r.RXDCTL:set( bits { Enable = 25 })
   self.r.RXDCTL:wait( bits { Enable = 25 })
   self.r.RDT(self.ndesc - 1)

   local tab = {}
   for i=0,self.ringSize-1,1 do
      if band(self.r.ALLRXDCTL[i](), bits { Enable = 25 }) > 0 then
         table.insert(tab, i)
      end
   end
   self:redirection_table(tab)
   self:unlock_sw_sem()
end

function Intel1g:init_tx_q ()                               -- 4.5.10
   if not self.txq then return end
   assert((self.txq >=0) and (self.txq < self.ringSize),
   "txqueue must be in 0.." .. self.ringSize-1 .. " for " .. self.model)
   self.tdh = 0
   self.tdt = 0
   self.txpackets = {}

   -- 7.2.2.3
   local txdesc_t = ffi.typeof("struct { uint64_t address, flags; }")
   local txdesc_ring_t = ffi.typeof("$[$]", txdesc_t, self.ndesc)
   self.txdesc = ffi.cast(ffi.typeof("$&", txdesc_ring_t),
   memory.dma_alloc(ffi.sizeof(txdesc_ring_t)))

   -- Transmit state variables 7.2.2.3.4 / 7.2.2.3.5
   self.txdesc_flags = bits({
      dtyp0=20,
      dtyp1=21,
      eop=24,
      ifcs=25,
      dext=29
   })

   -- Initialize transmit queue
   self.r.TDBAL(tophysical(self.txdesc) % 2^32)
   self.r.TDBAH(tophysical(self.txdesc) / 2^32)
   self.r.TDLEN(self.ndesc * ffi.sizeof(txdesc_t))
   self.r.TXDCTL:set(bits { WTHRESH = 16, ENABLE = 25 })
   self.r.TXDCTL:wait(bits { ENABLE = 25 })
   self.r.TCTL:set(bits { TxEnable = 1 })
   self:disable_interrupts()
end

function Intel1g:redirection_table (newtab)
   local current = {}
   local pos = 0

   for i=0,31,1 do
      for j=0,3,1 do
         current[self.r.RETA[i]:byte(j)] = 1
         if newtab ~= nil then
            local new = newtab[pos%#newtab+1]
            self.r.RETA[i]:byte(j, new)
         end
         pos = pos + 1
      end
   end
   return current
end

function Intel1g:new (arg)
   local conf = config.parse_app_arg(arg)
   local self = setmetatable({
      r = {},
      pciaddress = conf.pciaddr,
      ndesc = conf.ndescriptors or 256,
      txq = conf.txq,
      rxq = conf.rxq,
      rssseed = conf.rssseed or 314159
   }, {__index = Intel1g})
   local deviceInfo = pci.device_info(self.pciaddress)
   assert(deviceInfo.vendor == '0x8086', "unsupported nic")
   local models = {}
   models["0x1521"] = "i350"
   models["0x1533"] = "i210"
   models["0x157b"] = "i210"
   models["0x10fb"] = "82599ES"
   local ringSize = {}
   ringSize["i350"] = 8
   ringSize["i210"] = 4
   ringSize["82599ES"] = 128

   self.model    = models[deviceInfo.device]
   assert(self.model, "Unsupported Intel NIC")
   self.ringSize = ringSize[self.model]

   -- Setup device access
   self.base, self.fd = pci.map_pci_memory_unlocked(self.pciaddress, 0)
   self.master = self.fd:flock("ex, nb")

   self:load_registers(self.model)

   self:init()
   self.fd:flock("sh")
   self:init_tx_q()
   self:init_rx_q()
   return self
end

function Intel1g:load_registers(key)
   local v = reg[key]
   if v.inherit then self:load_registers(v.inherit) end
   if v.singleton then register.define(v.singleton, self.r, self.base) end
   if v.array then register.define_array(v.array, self.r, self.base) end
   if v.txq and self.txq then
      register.define(v.txq, self.r, self.base, self.txq)
   end
   if v.rxq and self.rxq then
      register.define(v.rxq, self.r, self.base, self.rxq)
   end
end

function Intel1g:init ()
   if not self.master then return end
   pci.unbind_device_from_linux(self.pciaddress)
   pci.set_bus_master(self.pciaddress, true)

   -- 4.5.3  Initialization Sequence
   self:disable_interrupts()
   -- 4.3.1 Software Reset (RST)
   self.r.CTRL(bits { RST = 26 })
   C.usleep(4*1000)
   self.r.EEC:wait(bits { Auto_RD = 9 })
   self.r.STATUS:wait(bits { PF_RST_DONE = 21 })
   self:disable_interrupts()                        -- 4.5.4

   -- use Internal PHY                             -- 8.2.5
   self.r.MDICNFG(0)
   self:init_phy()

   -- 7.1.2.10 Receive-Side Scaling (RSS)
   -- 8.10.22 Redirection Table
   -- RSS redirection table is undefined on reset, 0 it
   self:redirection_table({0})
   -- 8.10.20
   -- enable RSS
   self.r.MRQC:set(bits { RSS = 1 })
   -- set the RSS default queue to 0
   self.r.MRQC:clr(bits { Def_Q0 = 3, Def_Q1 = 4, Def_Q2 = 5})
   -- Enable all RSS hash on all available input keys
   self.r.MRQC:set(bits {
      RSS0 = 16, RSS1 = 17, RSS2 = 18, RSS3 = 19, RSS4 = 20,
      RSS5 = 21, RSS6 = 22, RSS7 = 23, RSS8 = 24
   })
   -- 8.10.21
   math.randomseed(self.rssseed)
   for i=0,9,1 do
      self.r.RSSRK[i](math.random(2^32))
   end
   -- 8.10.1
   self.r.RCTL:clr(bits { rxEnable = 1 })
   self.r.RCTL(bits {
      RXEN = 1,      -- enable receive
      SBP = 2,       -- Store Bad Packet
      UPE = 3,       -- Unicast Promiscuous
      MPE = 4,       -- Mutlicast Promiscuous
      LPE = 5,       -- Long Packet Reception / Jumbos
      BAM = 15,      -- Broadcast Accept Mode
      SECRC = 26,    -- Strip ethernet CRC
   })

   self.r.CTRL:set(bits { SETLINKUP = 6 })
   -- 8.2.3
   self.r.CTRL_EXT:clr( bits { LinkMode0 = 22, LinkMode1 = 23} )
   self.r.CTRL_EXT:clr( bits { PowerDown = 20 } )
   self.r.CTRL_EXT:set( bits { AutoSpeedDetect = 12, DriverLoaded = 28 })
   self:unlock_sw_sem()
end

function Intel1g:pull ()
   if not self.rxq then return end
   local lo = self.output["output"]
   assert(lo, "intel1g: output link required")

   while band(self.rxdesc[self.rdt].status, 0x01) == 1 do
      local desc = self.rxdesc[self.rdt]
      local p = self.rxpackets[self.rdt]
      p.length = desc.length
      local np = packet.allocate()
      self.rxpackets[self.rdt] = np
      self.rxdesc[self.rdt].address = tophysical(np.data)
      self.rxdesc[self.rdt].status = 0
      link.transmit(lo, p)

      self.rdt = self:ringnext(self.rdt)
   end
   -- This avoids RDT == RDH when every descriptor is available.
   self.r.RDT(band(self.rdt - 1, self.ndesc-1))
end
function Intel1g:ringnext (index)
   return band(index+1, self.ndesc-1)
end
function Intel1g:push ()
   if not self.txq then return end
   local li = self.input["input"]
   assert(li, "intel1g:push: no input link")

   while not link.empty(li) and self:ringnext(self.tdt) ~= self.tdh do
      local p = link.receive(li)
      self.txdesc[self.tdt].address = tophysical(p.data)
      self.txdesc[self.tdt].flags = bor(p.length, self.txdesc_flags, lshift(p.length+0ULL, 46))
      self.txpackets[self.tdt] = p
      self.tdt = self:ringnext(self.tdt)
   end
   -- Reclaim transmit contexts
   local cursor = self.tdh
   self.tdh = self.r.TDH()	-- possible race condition, 7.2.2.4, check DD
   while cursor ~= self.tdh do
      if self.txpackets[cursor] then
         packet.free(self.txpackets[cursor])
         self.txpackets[cursor] = nil
      end
      cursor = self:ringnext(cursor)
   end
   self.r.TDT(self.tdt)
end

function Intel1g:stop ()
   if self.rxq then
      -- 4.5.9
      -- PBRWAC.PBE is mentioned in i350 only, not implemented here.
      self.r.RXDCTL:clr(bits { ENABLE = 25 })
      self.r.RXDCTL:wait(bits { ENABLE = 25 }, 0)
      for i = 0, self.ndesc-1 do
         if self.rxpackets[i] then
            packet.free(self.rxpackets[i])
            self.rxpackets[i] = nil
         end
      end
   end
   if self.txq then
      self.r.TXDCTL(0)
      self.r.TXDCTL:wait(bits { ENABLE = 25 }, 0)
      for i = 0, self.ndesc-1 do
         if self.txpackets[i] then
            packet.free(self.txpackets[i])
            self.txpackets[i] = nil
         end
      end
   end
   if self.fd:flock("nb, ex") then
      self.r.CTRL:clr( bits { SETLINKUP = 6 } )
      self.r.CTRL_EXT:clear( bits { DriverLoaded = 28 })
      pci.set_bus_master(self.pciaddress, false)
      pci.close_pci_resource(self.fd, self.base)
   end
end
function Intel1g:stats ()
   local stats_registers = [[
   CRCERRS   0x04000 - RC CRC Error Count
   MPC       0x04010 - RC Missed Packet Count
   RNBC      0x040A0 - RC Receive No Buffers Count
   GPTC      0x04080 - RC Good Packets Transmitted Count
   GPRC      0x04074 - RC Good Packets Received Count
   GORC      0x04088 - RC64 Good Octets Received Count
   ]]
   local r = {}
   register.define(stats_registers, r, self.base)
   local ret = {}
   for i,v in pairs(r) do
      ret[i] = v()
   end
   return ret
end

Intel82599 = {
}
function Intel82599:init()
   self:disable_interrupts()

   local reset = bits{LinkReset=3, DeviceReset=26}
   self.r.CTRL(reset)
   C.usleep(1000)
   --self.r.CTRL:wait(reset, 0)
   self.r.EEC:wait(bits{AutoreadDone=9})           -- 3.
   self.r.RDRXCTL:wait(bits{DMAInitDone=3})        -- 4.

   -- 4.6.4.2
   -- 3.7.4.2
   self.r.AUTOC:set(bits { LMS0 = 13, LMS1 = 14 })
   self.r.AUTOC2(0)
   self.r.AUTOC2:set(bits { tenG_PMA_PMD_Serial = 17 })
   self.r.AUTOC:set(bits{restart_AN=12})
   print(self.r.LINKS())
end
