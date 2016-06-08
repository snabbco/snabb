-- intel1g: Device driver app for Intel 1G and 10G network cards
-- It supports
--    - Intel1G i210 and i350 based 1G network cards
--    - Intel82599 82599 based 10G network cards
-- The driver supports multiple processes connecting to the same physical nic.
-- Per process RX / TX queues are available via RSS. Statistics collection
-- processes can read counter registers
--
-- Data sheets (reference documentation):
-- http://www.intel.com/content/dam/www/public/us/en/documents/datasheets/ethernet-controller-i350-datasheet.pdf
-- http://www.intel.com/content/dam/www/public/us/en/documents/datasheets/i210-ethernet-controller-datasheet.pdf
-- http://www.intel.co.uk/content/dam/www/public/us/en/documents/datasheets/82599-10-gbe-controller-datasheet.pdf
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
STATUS    0x00008 -            RO Device Status
]]
}
reg['82599ES'] = {
   array = [[
ALLRXDCTL     0x01028 +0x40*0..63   RW Receive Descriptor Control
ALLRXDCTL     0x0D028 +0x40*64..127 RW Receive Descriptor Control
DAQF      0x0E200 +0x04*0..127  RW Destination Address Queue Filter
FTQF      0x0E600 +0x04*0..127  RW Five Tuple Queue Filter
MPSAR     0x0A600 +0x04*0..255  RW MAC Pool Select Array
PFUTA     0X0F400 +0x04*0..127  RW PF Unicast Table Array
PFVLVF    0x0F100 +0x04*0..63   RW PF VM VLAN Pool Filter
PFVLVFB   0x0F200 +0x04*0..127  RW PF VM VLAN Pool Filter Bitmap
SAQF      0x0E000 +0x04*0..127  RW Source Address Queue Filter
SDPQF     0x0E400 +0x04*0..127  RW Source Destination Port Queue Filter
RAH        0x0A204 +0x08*0..127  RW Receive Address High
RAL        0x0A200 +0x08*0..127  RW Receive Address Low
RTTDT2C   0x04910 +0x04*0..7    RW DCB Transmit Descriptor Plane T2 Config
RTTPT2C   0x0CD20 +0x04*0..7    RW DCB Transmit Packet Plane T2 Config
RTRPT4C   0x02140 +0x04*0..7    RW DCB Receive Packet Plane T4 Config
RXPBSIZE  0x03C00 +0x04*0..7    RW Receive Packet Buffer Size
TXPBSIZE  0x0CC00 +0x04*0..7    RW Transmit Packet Buffer Size
TXPBTHRESH 0x04950 +0x04*0..7   RW Tx Packet Buffer Threshold
VFTA      0x0A000 +0x04*0..127  RW VLAN Filter Table Array
]],
   inherit = "gbl",
   rxq = [[
DCA_RXCTRL 0x0100C +0x40*0..63   RW Rx DCA Control Register
DCA_RXCTRL 0x0D00C +0x40*64..127 RW Rx DCA Control Register
SRRCTL     0x01014 +0x40*0..63   RW Split Receive Control Registers
SRRCTL     0x0D014 +0x40*64..127 RW Split Receive Control Registers
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
]],
   singleton = [[
AUTOC     0x042A0 -            RW Auto Negotiation Control
AUTOC2    0x042A8 -            RW Auto Negotiation Control 2
DMATXCTL  0x04A80 -            RW DMA Tx Control
DTXMXSZRQ 0x08100 -            RW DMA Tx Map Allow Size Requests
EEC       0x10010 -            RW EEPROM/Flash Control Register
EIMC      0x00888 -            RW Extended Interrupt Mask Clear
FCCFG     0x03D00 -            RW Flow Control Configuration
FCTRL     0x05080 -            RW Filter Control
HLREG0    0x04240 -            RW MAC Core Control 0
LINKS     0x042A4 -            RO Link Status Register
MAXFRS    0x04268 -            RW Max Frame Size
MFLCN     0x04294 -            RW MAC Flow Control Register
MRQC      0x0EC80 -            RW Multiple Receive Queues Command Register
MTQC      0x08120 -            RW Multiple Transmit Queues Command Register
PFVTCTL   0x051B0 -             RW PF Virtual Control Register
RDRXCTL   0x02F00 -            RW Receive DMA Control Register
RTRUP2TC  0x03020 -            RW DCB Receive Use rPriority to Traffic Class
RTTUP2TC  0x0C800 -            RW DCB Transmit User Priority to Traffic Class
RTTBCNRC  0x04984 -            RW DCB Transmit Rate-Scheduler Config
RXCSUM    0x05000 -             RW Receive Checksum Control
RXCTRL    0x03000 -            RW Receive Control
SWSM      0x10140 -            RW Software Semaphore
VLNCTRL   0x05088 -             RW VLAN Control Register
]],
   txq = [[
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
   singleton = [[
MRQC      0x05818 -            RW Multiple Receive Queues Command Register
EEER      0x00E30 -            RW Energy Efficient Ethernet (EEE) Register
EIMC      0x01528 -            RW Extended Interrupt Mask Clear
SWSM      0x05b50 -            RW Software Semaphore
MANC      0x05820 -            RW Management Control
MDIC      0x00020 -            RW MDI Control
MDICNFG   0x00E04 -            RW MDI Configuration
RCTL      0x00100 -            RW RX Control
SW_FW_SYNC 0x05b5c -           RW Software Firmware Synchronization
TCTL      0x00400 -            RW TX Control
TCTL_EXT  0x00400 -            RW Extended TX Control
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

local Intel = { }
function Intel:new (arg)
   local conf = config.parse_app_arg(arg)
   local self = setmetatable({
      r = {},
      pciaddress = conf.pciaddr,
      ndesc = conf.ndescriptors or 1024,
      txq = conf.txq,
      rxq = conf.rxq,
      rssseed = conf.rssseed or 314159
   }, {__index = self})
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

function Intel:disable_interrupts ()
   self.r.EIMC(0xffffffff)
end
function Intel:init_rx_q ()
   if not self.rxq then return end
   assert((self.rxq >=0) and (self.rxq < self.ringSize),
   "rxqueue must be in 0.." .. self.ringSize-1 .. " for " .. self.model)
   assert((self.ndesc %128) ==0,
   "ndesc must be a multiple of 128 (for Rx only)")	-- see 7.1.4.5

   self.rxpackets = ffi.new("struct packet *[?]", self.ndesc)
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
      Drop_En = self:offset("SRRCTL", "Drop_En") -- Drop packets when no descriptors
   })
   self:lock_sw_sem()
   self.r.RXDCTL:set( bits { Enable = 25 })
   self.r.RXDCTL:wait( bits { Enable = 25 })
   self.r.RDT(self.ndesc - 1)
   self:unlock_sw_sem()

   self:rss_tab_build()
end
function Intel:init_tx_q ()                               -- 4.5.10
   if not self.txq then return end
   assert((self.txq >=0) and (self.txq < self.ringSize),
   "txqueue must be in 0.." .. self.ringSize-1 .. " for " .. self.model)
   self.tdh = 0
   self.tdt = 0
   self.txpackets = ffi.new("struct packet *[?]", self.ndesc)

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

   if self.r.DMATXCTL then
      self.r.DMATXCTL:set(bits { TE = 0 })
      self.r.TXDCTL:set(bits{SWFLSH=26, hthresh=8} + 32)
   end

   self.r.TXDCTL:set(bits { WTHRESH = 16, ENABLE = 25 })
   self.r.TXDCTL:wait(bits { ENABLE = 25 })

   if self.r.TCTL then -- i210/i350
      self.r.TCTL:set(bits { TxEnable = 1 })
   end
end
function Intel:load_registers(key)
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
function Intel:lock_sw_sem()
   for i=1,50,1 do
      if band(self.r.SWSM(), 0x01) == 1 then
         C.usleep(100000)
      else
         return
      end
   end
   error("Couldn't get lock")
end
function Intel:offset(reg, key)
   return self.offsets[reg][key]
end
function Intel:push ()
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
   --C.full_memory_barrier()
   while cursor ~= self.tdh do
      if self.txpackets[cursor] then
         packet.free(self.txpackets[cursor])
         self.txpackets[cursor] = nil
      end
      cursor = self:ringnext(cursor)
   end
   self.r.TDT(self.tdt)
end

function Intel:pull ()
   if not self.rxq then return end
   local lo = self.output["output"]
   assert(lo, "intel1g: output link required")

   while band(self.rxdesc[self.rdt].status, 0x01) == 1 do
      local p = self.rxpackets[self.rdt]
      p.length = self.rxdesc[self.rdt].length
      link.transmit(lo, p)

      local np = packet.allocate()
      self.rxpackets[self.rdt] = np
      self.rxdesc[self.rdt].address = tophysical(np.data)
      self.rxdesc[self.rdt].status = 0

      self.rdt = band(self.rdt + 1, self.ndesc-1)
   end
   -- This avoids RDT == RDH when every descriptor is available.
   self.r.RDT(band(self.rdt - 1, self.ndesc-1))
end

function Intel:unlock_sw_sem()
   self.r.SWSM:clr(bits { SMBI = 0 })
end

function Intel:ringnext (index)
   return band(index+1, self.ndesc-1)
end
function Intel:rss_enable ()
   -- set default q = 0 on i350,i210 noop on 82599
   self.r.MRQC(0)
   self.r.MRQC:set(bits { RSS = self:offset("MRQC", "RSS") })
   -- Enable all RSS hash on all available input keys
   self.r.MRQC:set(bits {
      TcpIPv4 = 16, IPv4 = 17, IPv6 = 20,
      TcpIPv6 = 21, UdpIPv4 = 22, UdpIPv6 = 23
   })
   self:rss_tab({0})
   self:rss_key()
end
function Intel:rss_key ()
   math.randomseed(self.rssseed)
   for i=0,9,1 do
      self.r.RSSRK[i](math.random(2^32))
   end
end
function Intel:rss_tab (newtab)
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
function Intel:rss_tab_build ()
   -- noop if rss is not enabled
   local b = bits { RSS = self:offset("MRQC", "RSS") }
   if bit.band(self.r.MRQC(), b) ~= b then return end

   self:lock_sw_sem()
   local tab = {}
   for i=0,self.ringSize-1,1 do
      if band(self.r.ALLRXDCTL[i](), bits { Enable = 25 }) > 0 then
         table.insert(tab, i)
      end
   end
   self:rss_tab(tab)
   self:unlock_sw_sem()
end


Intel1g = setmetatable({
   offsets = {
      SRRCTL = {
         Drop_En = 31
      },
      MRQC = {
         RSS = 1
      }
   }
}, {__index = Intel})
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
function Intel1g:lock_fw_sem()
   self.r.SWSM:set(bits { SWESMBI = 1 })
   while band(self.r.SWSM(), 0x02) == 0 do
      self.r.SWSM:set(bits { SWESMBI = 1 })
   end
end
function Intel1g:unlock_fw_sem()
   self.r.SWSM:clr(bits { SWESMBI = 1 })
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
   -- 8.10.20
   self:rss_enable()
   -- enable RSS

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

Intel82599 = setmetatable({
   offsets = {
      SRRCTL = {
         Drop_En = 31
      },
      MRQC = {
         RSS = 0
      }
   }
}, { __index = Intel })
function Intel82599:init ()
   if not self.master then return end
   self:disable_interrupts()

   local reset = bits{ LinkReset=3, DeviceReset=26 }
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

   -- 4.6.7
   self.r.RXCTRL(0)                             -- disable receive
   for i=0,127 do
      self.r.RAL[i](0)
      self.r.RAH[i](0)
      self.r.PFUTA[i](0)
      self.r.VFTA[i](0)
      self.r.PFVLVFB[i](0)
      self.r.SAQF[i](0)
      self.r.DAQF[i](0)
      self.r.SDPQF[i](0)
      self.r.FTQF[i](0)
   end
   for i=0,63 do
      self.r.PFVLVF[i](0)
      self.r.MPSAR[i](0)
   end
   for i=0,255 do
      self.r.MPSAR[i](0)
   end

   self.r.FCTRL:set(bits {
      SBP = 1,
      MPE = 8,
      UPE = 9,
      BAM = 10
   })

   self.r.VLNCTRL(0x8100)                    -- explicity set default
   self.r.RXCSUM(0)                          -- turn off all checksum offload

   self.r.RXPBSIZE[0]:bits(10,19, 0x200)
   self.r.TXPBSIZE[0]:bits(10,19, 0xA0)
   self.r.TXPBTHRESH[0](0xA0)
   for i=1,7 do
      self.r.RXPBSIZE[i]:bits(10,19, 0)
      self.r.TXPBSIZE[i]:bits(10,19, 0)
      self.r.TXPBTHRESH[i](0)
   end

   self.r.MTQC(0)
   self.r.PFVTCTL(0)
   self.r.RTRUP2TC(0)
   self.r.RTTUP2TC(0)
   self.r.DTXMXSZRQ(0xFFF)

   self.r.MFLCN(bits{RFCE=3})
   self.r.FCCFG(bits{TFCE=3})

   for i=0,7 do
      self.r.RTTDT2C[i](0)
      self.r.RTTPT2C[i](0)
      self.r.RTRPT4C[i](0)
   end

   self.r.HLREG0(bits{
      TXCRCEN=0, RXCRCSTRP=1, JUMBOEN=2, rsv2=3,
      TXPADEN=10, rsvd3=11, rsvd4=13, MDCSPD=16
   })
   self.r.MAXFRS(lshift(9216, 16))

   if self.rxq then
      self.r.RDRXCTL(0)
      self.r.RDRXCTL(bits { CRCStrip = 1 })
      self.r.RXCTRL:set(bits{ RXEN=0 })
      self.r.DCA_RXCTRL:clr(bits{RxCTRL=12})
   end

   self:unlock_sw_sem()
   if self.rxq then
      self:rss_enable()
   end
end
