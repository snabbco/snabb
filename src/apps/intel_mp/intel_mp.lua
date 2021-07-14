-- intel_mp: Device driver app for Intel 1G and 10G network cards
-- It supports
--    - Intel1G i210 and i350 based 1G network cards
--    - Intel82599 82599 based 10G network cards
-- The driver supports multiple processes connecting to the same physical nic.
-- Per process RX / TX queues are available via RSS and VMDQ. Statistics
-- collection processes can read counter registers
--
-- Data sheets (reference documentation):
-- http://www.intel.com/content/dam/www/public/us/en/documents/datasheets/ethernet-controller-i350-datasheet.pdf
-- http://www.intel.com/content/dam/www/public/us/en/documents/datasheets/i210-ethernet-controller-datasheet.pdf
-- http://www.intel.co.uk/content/dam/www/public/us/en/documents/datasheets/82599-10-gbe-controller-datasheet.pdf
-- Note: section and page numbers in the comments below refer to the 82599 and
-- i210 data sheets, except where VMDQ behavior is being described, in which
-- case the 82599 and i350 data sheets are referenced.

module(..., package.seeall)

local ffi         = require("ffi")
local C           = ffi.C
local pci         = require("lib.hardware.pci")
local band, bor, lshift = bit.band, bit.bor, bit.lshift
local lib         = require("core.lib")
local bits        = lib.bits
local tophysical  = core.memory.virtual_to_physical
local register    = require("lib.hardware.register")
local counter     = require("core.counter")
local macaddress  = require("lib.macaddress")
local shm         = require("core.shm")
local alarms      = require("lib.yang.alarms")
local S           = require("syscall")

local CallbackAlarm = alarms.CallbackAlarm
local transmit, receive, empty = link.transmit, link.receive, link.empty

-- It's not clear what address to use for EEMNGCTL_i210 DPDK PMD / linux e1000
-- both use 1010 but the docs say 12030
-- https://sourceforge.net/p/e1000/mailman/message/34457421/
-- http://dpdk.org/browse/dpdk/tree/drivers/net/e1000/base/e1000_regs.h

reg = { }
reg.gbl = {
   array = [[
RETA        0x5c00 +0x04*0..31      RW Redirection Table
RSSRK       0x5C80 +0x04*0..9       RW RSS Random Key
]],
   singleton = [[
BPRC        0x04078 -               RC Broadcast Packets Received Count
BPTC        0x040F4 -               RC Broadcast Packets Transmitted Count
CTRL        0x00000 -               RW Device Control
CTRL_EXT    0x00018 -               RW Extended Device Control
STATUS      0x00008 -               RO Device Status
RCTL        0x00100 -               RW RX Control
CRCERRS     0x04000 -               RC CRC Error Count
GPRC        0x04074 -               RC Good Packets Received Count
GPTC        0x04080 -               RC Good Packets Transmitted Count
GORC64      0x04088 -               RC64 Good Octets Received Count 64-bit
GOTC64      0x04090 -               RC64 Good Octets Transmitted Count 64-bit
MPRC        0x0407C -               RC Multicast Packets Received Count
MPTC        0x040F0 -               RC Multicast Packets Transmitted Count
BPRC        0x04078 -               RC Broadcast Packets Received Count
BPTC        0x040F4 -               RC Broadcast Packets Transmitted
RXCSUM      0x05000 -               RW Receive Checksum Control
]]
}
reg['82599ES'] = {
   array = [[
ALLRXDCTL   0x01028 +0x40*0..63     RW Receive Descriptor Control
ALLRXDCTL   0x0D028 +0x40*64..127   RW Receive Descriptor Control
DAQF        0x0E200 +0x04*0..127    RW Destination Address Queue Filter
FTQF        0x0E600 +0x04*0..127    RW Five Tuple Queue Filter
ETQF        0x05128 +0x04*0..7      RW EType Queue Filter
ETQS        0x0EC00 +0x04*0..7      RW EType Queue Select
MPSAR       0x0A600 +0x04*0..255    RW MAC Pool Select Array
PFUTA       0X0F400 +0x04*0..127    RW PF Unicast Table Array
PFVLVF      0x0F100 +0x04*0..63     RW PF VM VLAN Pool Filter
PFVLVFB     0x0F200 +0x04*0..127    RW PF VM VLAN Pool Filter Bitmap
PFMRCTL     0x0F600 +0x04*0..3      RW PF Mirror Rule Control
PFMRVLAN    0x0F610 +0x04*0..7      RW PF Mirror Rule VLAN
PFMRVM      0x0F630 +0x04*0..7      RW PF Mirror Rule Pool
PFVFRE      0x051E0 +0x04*0..1      RW PF VF Receive Enable
PFVFTE      0x08110 +0x04*0..1      RW PF VF Transmit Enable
PFVMTXSW    0x05180 +0x04*0..1      RW PF VM Tx Switch Loopback Enable
PFVFSPOOF   0x08200 +0x04*0..7      RW PF VF Anti Spoof Control
PFVMVIR     0x08000 +0x04*0..63     RW PF VM VLAN Insert Register
PFVML2FLT   0x0F000 +0x04*0..63     RW PF VM L2 Control Register
QPRC        0x01030 +0x40*0..15     RC Queue Packets Received Count
QPRDC       0x01430 +0x40*0..15     RC Queue Packets Received Drop Count
QBRC64      0x01034 +0x40*0..15     RC64 Queue Bytes Received Count
QPTC        0x08680 +0x04*0..15     RC Queue Packets Transmitted Count
QBTC64      0x08700 +0x08*0..15     RC64 Queue Bytes Transmitted Count Low
SAQF        0x0E000 +0x04*0..127    RW Source Address Queue Filter
SDPQF       0x0E400 +0x04*0..127    RW Source Destination Port Queue Filter
PSRTYPE     0x0EA00 +0x04*0..63     RW Packet Split Receive Type Register
RAH         0x0A204 +0x08*0..127    RW Receive Address High
RAL         0x0A200 +0x08*0..127    RW Receive Address Low
RAL64       0x0A200 +0x08*0..127    RW64 Receive Address Low and High
RQSM        0x02300 +0x04*0..31     RW Receive Queue Statistic Mapping Registers
RTTDT2C     0x04910 +0x04*0..7      RW DCB Transmit Descriptor Plane T2 Config
RTTPT2C     0x0CD20 +0x04*0..7      RW DCB Transmit Packet Plane T2 Config
RTRPT4C     0x02140 +0x04*0..7      RW DCB Receive Packet Plane T4 Config
RXPBSIZE    0x03C00 +0x04*0..7      RW Receive Packet Buffer Size
RQSMR       0x02300 +0x04*0..31     RW Receive Queue Statistic Mapping Registers
TQSM        0x08600 +0x04*0..31     RW Transmit Queue Statistic Mapping Registers
TXPBSIZE    0x0CC00 +0x04*0..7      RW Transmit Packet Buffer Size
TXPBTHRESH  0x04950 +0x04*0..7      RW Tx Packet Buffer Threshold
VFTA        0x0A000 +0x04*0..127    RW VLAN Filter Table Array
QPRDC       0x01430 +0x40*0..15     RC Queue Packets Received Drop Count
FCRTH       0x03260 +0x40*0..7      RW Flow Control Receive Threshold High
]],
   inherit = "gbl",
   rxq = [[
DCA_RXCTRL  0x0100C +0x40*0..63     RW Rx DCA Control Register
DCA_RXCTRL  0x0D00C +0x40*64..127   RW Rx DCA Control Register
SRRCTL      0x01014 +0x40*0..63     RW Split Receive Control Registers
SRRCTL      0x0D014 +0x40*64..127   RW Split Receive Control Registers
RDBAL       0x01000 +0x40*0..63     RW Receive Descriptor Base Address Low
RDBAL       0x0D000 +0x40*64..127   RW Receive Descriptor Base Address Low
RDBAH       0x01004 +0x40*0..63     RW Receive Descriptor Base Address High
RDBAH       0x0D004 +0x40*64..127   RW Receive Descriptor Base Address High
RDLEN       0x01008 +0x40*0..63     RW Receive Descriptor Length
RDLEN       0x0D008 +0x40*64..127   RW Receive Descriptor Length
RDH         0x01010 +0x40*0..63     RO Receive Descriptor Head
RDH         0x0D010 +0x40*64..127   RO Receive Descriptor Head
RDT         0x01018 +0x40*0..63     RW Receive Descriptor Tail
RDT         0x0D018 +0x40*64..127   RW Receive Descriptor Tail
RXDCTL      0x01028 +0x40*0..63     RW Receive Descriptor Control
RXDCTL      0x0D028 +0x40*64..127   RW Receive Descriptor Control
]],
   singleton = [[
AUTOC       0x042A0 -               RW Auto Negotiation Control
AUTOC2      0x042A8 -               RW Auto Negotiation Control 2
DMATXCTL    0x04A80 -               RW DMA Tx Control
DTXMXSZRQ   0x08100 -               RW DMA Tx Map Allow Size Requests
EEC         0x10010 -               RW EEPROM/Flash Control Register
EIMC        0x00888 -               RW Extended Interrupt Mask Clear
ERRBC       0x04008 -               RC Error Byte Count
FCCFG       0x03D00 -               RW Flow Control Configuration
FCOERPDC    0x0241C -               RC Rx Packets Dropped Count
FCTRL       0x05080 -               RW Filter Control
HLREG0      0x04240 -               RW MAC Core Control 0
ILLERRC     0x04004 -               RC Illegal Byte Error Count
LINKS       0x042A4 -               RO Link Status Register
MAXFRS      0x04268 -               RW Max Frame Size
MFLCN       0x04294 -               RW MAC Flow Control Register
MNGPDC      0x040B8 -               RO Management Packets Dropped Count
MRQC        0x0EC80 -               RW Multiple Receive Queues Command Register
MTQC        0x08120 -               RW Multiple Transmit Queues Command Register
PFVTCTL     0x051B0 -               RW PF Virtual Control Register
PFQDE       0x02F04 -               RW PF Queue Drop Enable Register
PFDTXGSWC   0x08220 -               RW PF DMA Tx General Switch Control
RDRXCTL     0x02F00 -               RW Receive DMA Control Register
RTRPCS      0x02430 -               RW DCB Receive Packet plane Control and Status
RTTDCS      0x04900 -               RW DCB Transmit Descriptor Plane Control and Status
RTTPCS      0x0CD00 -               RW DCB Transmit Packet Plane Control and Status
RTRUP2TC    0x03020 -            RW DCB Receive Use rPriority to Traffic Class
RTTUP2TC    0x0C800 -            RW DCB Transmit User Priority to Traffic Class
RTTDQSEL    0x04904 -               RW DCB Transmit Descriptor Plane Queue Select
RTTDT1C     0x04908 -               RW DCB Transmit Descriptor Plane T1 Config
RTTBCNRC    0x04984 -            RW DCB Transmit Rate-Scheduler Config
RFCTL       0x05008 -               RW Receive Filter Control Register
RXCTRL      0x03000 -               RW Receive Control
RXDGPC      0x02F50 -               RC DMA Good Rx Packet Counter
TXDGPC      0x087A0 -               RC DMA Good Tx Packet Counter
RXDSTATCTRL 0x02F40 -               RW Rx DMA Statistic Counter Control
RUC         0x040A4 -               RC Receive Undersize Count
RFC         0x040A8 -               RC Receive Fragment Count
ROC         0x040AC -               RC Receive Oversize Count
RJC         0x040B0 -               RC Receive Jabber Count
SWSM        0x10140 -               RW Software Semaphore
VLNCTRL     0x05088 -               RW VLAN Control Register
ILLERRC     0x04004 -               RC Illegal Byte Error Count
ERRBC       0x04008 -               RC Error Byte Count
GORC64      0x04088 -               RC64 Good Octets Received Count 64-bit
GOTC64      0x04090 -               RC64 Good Octets Transmitted Count 64-bit
RUC         0x040A4 -               RC Receive Undersize Count
RFC         0x040A8 -               RC Receive Fragment Count
ROC         0x040AC -               RC Receive Oversize Count
RJC         0x040B0 -               RC Receive Jabber Count
GORCL       0x04088 -               RC Good Octets Received Count Low
GOTCL       0x04090 -               RC Good Octets Transmitted Count Low
]],
   txq = [[
DCA_TXCTRL  0x0600C +0x40*0..127    RW Tx DCA Control Register
TDBAL       0x06000 +0x40*0..127    RW Transmit Descriptor Base Address Low
TDBAH       0x06004 +0x40*0..127    RW Transmit Descriptor Base Address High
TDLEN       0x06008 +0x40*0..127    RW Transmit Descriptor Length
TDH         0x06010 +0x40*0..127    RW Transmit Descriptor Head
TDT         0x06018 +0x40*0..127    RW Transmit Descriptor Tail
TXDCTL      0x06028 +0x40*0..127    RW Transmit Descriptor Control
TDWBAL      0x06038 +0x40*0..127    RW Tx Descriptor Completion Write Back Address Low
TDWBAH      0x0603C +0x40*0..127    RW Tx Descriptor Completion Write Back Address High
]]
}
reg['1000BaseX'] = {
   array = [[
ALLRXDCTL   0x0c028 +0x40*0..7      RW Re Descriptor Control Queue
RAL64       0x05400 +0x08*0..15     RW64 Receive Address Low
RAL         0x05400 +0x08*0..15     RW Receive Address Low
RAH         0x05404 +0x08*0..15     RW Receive Address High
VFTA        0x05600 +0x04*0..127    RW  VLAN Filter Table Array
]],
   inherit = "gbl",
   rxq = [[
RDBAL       0x0c000 +0x40*0..7      RW Rx Descriptor Base low
RDBAH       0x0c004 +0x40*0..7      RW Rx Descriptor Base High
RDLEN       0x0c008 +0x40*0..7      RW Rx Descriptor Ring Length
RDH         0x0c010 +0x40*0..7      RO Rx Descriptor Head
RDT         0x0c018 +0x40*0..7      RW Rx Descriptor Tail
RXDCTL      0x0c028 +0x40*0..7      RW Re Descriptor Control Queue
RXCTL       0x0c014 +0x40*0..7      RW RX DCA CTRL Register Queue
SRRCTL      0x0c00c +0x40*0..7      RW Split and Replication Receive Control
]],
   singleton = [[
ALGNERRC  0x04004 -                 RC Alignment Error Count
RXERRC    0x0400C -                 RC RX Error Count
RLEC      0x04040 -                 RC Receive Length Error Count
CRCERRS   0x04000 -                 RC CRC Error Count
MPC       0x04010 -                 RC Missed Packets Count
MRQC      0x05818 -                 RW Multiple Receive Queues Command Register
EEER      0x00E30 -                 RW Energy Efficient Ethernet (EEE) Register
EIMC      0x01528 -                 RW Extended Interrupt Mask Clear
SWSM      0x05b50 -                 RW Software Semaphore
MANC      0x05820 -                 RW Management Control
MDIC      0x00020 -                 RW MDI Control
MDICNFG   0x00E04 -                 RW MDI Configuration
RLPML     0x05004 -                 RW Receive Long packet maximal length
RPTHC     0x04104 -                 RC Rx Packets to host count
SW_FW_SYNC 0x05b5c -                RW Software Firmware Synchronization
TCTL      0x00400 -                 RW TX Control
TCTL_EXT  0x00400 -                 RW Extended TX Control
ALGNERRC  0x04004 -                 RC Alignment Error - R/clr
RXERRC    0x0400C -                 RC RX Error - R/clr
MPC       0x04010 -                 RC Missed Packets - R/clr
ECOL      0x04018 -                 RC Excessive Collisions - R/clr
LATECOL   0x0401C -                 RC Late Collisions - R/clr
RLEC      0x04040 -                 RC Receive Length Error - R/clr
GORCL     0x04088 -                 RC Good Octets Received - R/clr
GORCH     0x0408C -                 RC Good Octets Received - R/clr
GOTCL     0x04090 -                 RC Good Octets Transmitted - R/clr
GOTCH     0x04094 -                 RC Good Octets Transmitted - R/clr
RNBC      0x040A0 -                 RC Receive No Buffers Count - R/clr
]],
   txq = [[
TDBAL  0xe000 +0x40*0..7            RW Tx Descriptor Base Low
TDBAH  0xe004 +0x40*0..7            RW Tx Descriptor Base High
TDLEN  0xe008 +0x40*0..7            RW Tx Descriptor Ring Length
TDH    0xe010 +0x40*0..7            RO Tx Descriptor Head
TDT    0xe018 +0x40*0..7            RW Tx Descriptor Tail
TXDCTL 0xe028 +0x40*0..7            RW Tx Descriptor Control Queue
TXCTL  0xe014 +0x40*0..7            RW Tx DCA CTRL Register Queue
]]
}
reg.i210 = {
   array = [[
RQDPC       0x0C030 +0x40*0..4      RCR Receive Queue Drop Packet Count
TQDPC       0x0E030 +0x40*0..4      RCR Transmit Queue Drop Packet Count
PQGPRC      0x10010 +0x100*0..4     RCR Per Queue Good Packets Received Count
PQGPTC      0x10014 +0x100*0..4     RCR Per Queue Good Packets Transmitted Count
PQGORC      0x10018 +0x100*0..4     RCR Per Queue Good Octets Received Count
PQGOTC      0x10034 +0x100*0..4     RCR Per Queue Octets Transmitted Count
PQMPRC      0x10038 +0x100*0..4     RCR Per Queue Multicast Packets Received
]],
   inherit = "1000BaseX",
   singleton = [[
EEMNGCTL  0x12030 -            RW Manageability EEPROM-Mode Control Register
EEC       0x12010 -            RW EEPROM-Mode Control Register
]]
}
reg.i350 = {
   array = [[
VMVIR       0x03700 +0x04*0..7      RW  VM VLAN insert register
PSRTYPE     0x05480 +0x04*0..7      RW  Packet Split Receive Type
VMOLR       0x05AD0 +0x04*0..7      RW  VM Offload register
VLVF        0x05d00 +0x04*0..31     RW  VLAN VM Filter
DVMOLR      0x0C038 +0x04*0..7      RW  DMA VM Offload register
VMRCTL      0x05D80 +0x04*0..7      RW  Virtual Mirror rule control
VMRVLAN     0x05D90 +0x04*0..7      RW  Virtual Mirror rule VLAN
VMRVM       0x05DA0 +0x04*0..7      RW  Virtual Mirror rule VM
RQDPC       0x0C030 +0x40*0..7      RC Receive Queue Drop Packet Count
TQDPC       0x0E030 +0x40*0..7      RCR Transmit Queue Drop Packet Count
PQGPRC      0x10010 +0x100*0..7     RCR Per Queue Good Packets Received Count
PQGPTC      0x10014 +0x100*0..7     RCR Per Queue Good Packets Transmitted Count
PQGORC      0x10018 +0x100*0..7     RCR Per Queue Good Octets Received Count
PQGOTC      0x10034 +0x100*0..7     RCR Per Queue Octets Transmitted Count
PQMPRC      0x10038 +0x100*0..7     RCR Per Queue Multicast Packets Received
]],
   inherit = "1000BaseX",
   singleton = [[
VFRE        0x00C8C -            RW  VF Receive Enable
VFTE        0x00C90 -            RW  VF Transmit Enable
EEMNGCTL    0x01010 -            RW  Manageability EEPROM-Mode Control Register
EEC         0x00010 -            RW  EEPROM-Mode Control Register
QDE         0x02408 -            RW  Queue Drop Enable Register
DTXCTL      0x03590 -            RW  DMA TX Control
RPLPSRTYPE  0x054C0 -            RW  Replicated Packet Split Receive Type
VT_CTL      0x0581C -            RW  VMDq Control Register
TXSWC       0x05ACC -            RW  TX Switch Control
FACTPS	    0x05B30 -            RW  Function Active and Power State to MNG
]]
}

Intel = {
   config = {
      pciaddr = {required=true},
      ring_buffer_size = {default=2048},
      vmdq = {default=false},
      vmdq_queuing_mode = {default="rss-64-2"},
      macaddr = {},
      poolnum = {},
      vlan = {},
      mirror = {},
      rxcounter = {},
      txcounter = {},
      rate_limit = {default=0},
      priority = {default=1.0},
      txq = {default=0},
      rxq = {default=0},
      mtu = {default=9014},
      linkup_wait = {default=120},
      linkup_wait_recheck = {default=0.1},
      wait_for_link = {default=false},
      master_stats = {default=true},
      run_stats = {default=false},
      mac_loopback = {default=false}
   },
}
Intel1g = setmetatable({}, {__index = Intel })
Intel82599 = setmetatable({}, {__index = Intel})
byPciID = {
  [0x1521] = { registers = "i350", driver = Intel1g, max_q = 8 },
  [0x1533] = { registers = "i210", driver = Intel1g, max_q = 4 },
  [0x157b] = { registers = "i210", driver = Intel1g, max_q = 4 },
  [0x10fb] = { registers = "82599ES", driver = Intel82599, max_q = 16 }
}

-- The `driver' variable is used as a reference to the driver class in
-- order to interchangeably use NIC drivers.
driver = Intel

-- C type for VMDq enabled state
vmdq_enabled_t = ffi.typeof("struct { uint8_t enabled; }")
-- C type for shared memory indicating which pools are used
local vmdq_pools_t = ffi.typeof("struct { uint8_t pools[64]; }")
-- C type for VMDq queuing mode
-- mode = 0 for 32 pools/4 queues, 1 for 64 pools/2 queues
local vmdq_queuing_mode_t = ffi.typeof("struct { uint8_t mode; }")

local function shared_counter(srcdir, targetdir)
   local mod = { type = "counter" }
   local function dirsplit(name)
      return name:match("^(.*)/([^/]+)$")
   end
   local function source(name)
      if name:match('/') then
         local head, tail = dirsplit(name)
         return head..'/'..srcdir..'/'..tail
      else
         return srcdir..'/'..name
      end
   end
   local function target(name)
      if name:match('/') then
         local head, tail = dirsplit(name)
         return targetdir..'/'..tail
      else
         return targetdir..'/'..name
      end
   end
   function mod.create(name)
      shm.alias(source(name), target(name))
      local status, c
      local function read_shared_counter ()
         if not c then status, c = pcall(counter.open, target(name)) end
         if not status then return 0ULL end
         return counter.read(c)
      end
      return read_shared_counter
   end
   function mod.delete(name)
      S.unlink(shm.resolve(source(name)))
   end
   return mod
end

function Intel:new (conf)
   local self = {
      r = {},
      pciaddress = conf.pciaddr,
      path = pci.path(conf.pciaddr),
      ndesc = conf.ring_buffer_size,
      txq = conf.txq,
      rxq = conf.rxq,
      mtu = conf.mtu,
      linkup_wait = conf.linkup_wait,
      linkup_wait_recheck = conf.linkup_wait_recheck,
      wait_for_link = conf.wait_for_link and not conf.mac_loopback,
      vmdq = conf.vmdq,
      poolnum = conf.poolnum,
      macaddr = conf.macaddr,
      vlan = conf.vlan,
      want_mirror = conf.mirror,
      rxcounter = conf.rxcounter,
      txcounter = conf.txcounter,
      rate_limit = conf.rate_limit,
      priority = conf.priority,
      -- a path used for shm operations on NIC-global state
      -- canonicalize to ensure the reference is the same from all
      -- processes
      shm_root = "/intel-mp/" .. pci.canonical(conf.pciaddr) .. "/",
      -- only used for main process, affects max pool number
      vmdq_queuing_mode = conf.vmdq_queuing_mode,
      -- Enable Tx->Rx MAC Loopback for diagnostics/testing?
      mac_loopback = conf.mac_loopback
   }

   local vendor = lib.firstline(self.path .. "/vendor")
   local device = lib.firstline(self.path .. "/device")
   local byid = byPciID[tonumber(device)]
   assert(vendor == '0x8086', "unsupported nic")
   assert(byid, "unsupported intel nic")
   self = setmetatable(self, { __index = byid.driver})

   self.max_q = byid.max_q

   -- Setup device access
   self.fd = pci.open_pci_resource_unlocked(self.pciaddress, 0)
   self.master = self.fd:flock("ex, nb")
   if self.master then
      -- Master unbinds device, enables PCI bus master, and *then* memory maps
      -- the device, loads registers, initializes it before sharing the lock.
      pci.unbind_device_from_linux(self.pciaddress)
      pci.set_bus_master(self.pciaddress, true)
      self.base = pci.map_pci_memory(self.fd)
      self:load_registers(byid.registers)
      self:init()
      self:init_vmdq()
      self.fd:flock("sh")
   else
      -- Other processes wait for the shared lock before memory mapping the and
      -- loading registers.
      self.fd:flock("sh")
      self.base = pci.map_pci_memory(self.fd)
      self:load_registers(byid.registers)
   end

   self:check_vmdq()
   -- this needs to happen before register loading for rxq/txq
   -- because it determines the queue numbers
   self:select_pool()
   self:load_queue_registers(byid.registers)
   self:init_tx_q()
   self:init_rx_q()
   self:set_MAC()
   self:set_VLAN()
   self:set_mirror()
   self:set_rxstats()
   self:set_txstats()
   self:set_tx_rate()

   -- Figure out if we are supposed to collect device statistics
   self.run_stats = conf.run_stats or (self.master and conf.master_stats)
   if self.run_stats then
      local frame = {
         -- Keep a copy of the mtu here to have all
         -- data available in a single shm frame
         mtu       = {counter, self.mtu},
         type      = {counter, 0x1000}, -- ethernetCsmacd
         macaddr   = {counter, self.r.RAL64[0]:bits(0,48)},
         speed     = {counter},
         status    = {counter, 2}, -- Link down
         promisc   = {counter},
         rxbytes   = {counter},
         rxpackets = {counter},
         rxmcast   = {counter},
         rxbcast   = {counter},
         rxdrop    = {counter},
         rxerrors  = {counter},
         rxdmapackets = {counter},
         txbytes   = {counter},
         txpackets = {counter},
         txmcast   = {counter},
         txbcast   = {counter},
         txdrop    = {counter},
         txerrors  = {counter},
      }
      self:init_queue_stats(frame)
      self.stats = shm.create_frame(self.shm_root.."stats", frame)
      self.sync_timer = lib.throttle(0.01)
   end

   -- Expose per-device statistics from master
   local shared_counter = shared_counter(
      'pci/'..self.pciaddress, self.shm_root..'stats')
   self.shm = {
      dtime     = {counter, C.get_unix_time()},
      -- Keep a copy of the mtu here to have all
      -- data available in a single shm frame
      mtu       = {counter, self.mtu},
      type      = {counter, 0x1000}, -- ethernetCsmacd
      macaddr   = {counter, self.r.RAL64[0]:bits(0,48)},
      speed     = {shared_counter},
      status    = {shared_counter},
      promisc   = {shared_counter}
   }
   if self.rxq then
      self.shm.rxcounter = {counter, self.rxcounter}
      self.shm.rxbytes   = {shared_counter}
      self.shm.rxpackets = {shared_counter}
      self.shm.rxmcast   = {shared_counter}
      self.shm.rxbcast   = {shared_counter}
      self.shm.rxdrop    = {shared_counter}
      self.shm.rxerrors  = {shared_counter}
      self.shm.rxdmapackets = {shared_counter}
      if self.rxcounter then
         for _,k in pairs { 'drops', 'packets', 'bytes' } do
            local name = "q" .. self.rxcounter .. "_rx" .. k
            self.shm[name] = {shared_counter}
         end
      end
   end
   if self.txq then
      self.shm.txcounter = {counter, self.txcounter}
      self.shm.txbytes   = {shared_counter}
      self.shm.txpackets = {shared_counter}
      self.shm.txmcast   = {shared_counter}
      self.shm.txbcast   = {shared_counter}
      self.shm.txdrop    = {shared_counter}
      self.shm.txerrors  = {shared_counter}
      if self.txcounter then
         for _,k in pairs { 'packets', 'bytes' } do
            local name = "q" .. self.txcounter .. "_tx" .. k
            self.shm[name] = {shared_counter}
         end
      end
   end

   alarms.add_to_inventory(
      {alarm_type_id='ingress-bandwith'},
      {resource=tostring(S.getpid()), has_clear=true,
       description='Ingress bandwith exceeds N Gbps'})
   local ingress_bandwith = alarms.declare_alarm(
      {resource=tostring(S.getpid()),alarm_type_id='ingress-bandwith'},
      {perceived_severity='major',
       alarm_text='Ingress bandwith exceeds 1e9 bytes/s which can cause packet drops.'})
   self.ingress_bandwith_alarm = CallbackAlarm.new(ingress_bandwith,
      1, 1e9, function() return self:rxbytes() end)

   alarms.add_to_inventory(
      {alarm_type_id='ingress-packet-rate'},
      {resource=tostring(S.getpid()), has_clear=true,
       description='Ingress packet-rate exceeds N Gbps'})
   local ingress_packet_rate = alarms.declare_alarm(
      {resource=tostring(S.getpid()),alarm_type_id='ingress-packet-rate'},
      {perceived_severity='major',
       alarm_text='Ingress packet-rate exceeds 2MPPS which can cause packet drops.'})
   self.ingress_packet_rate_alarm = CallbackAlarm.new(ingress_packet_rate,
      1, 2e6, function() return self:rxpackets() end)

   return self
end

function Intel:disable_interrupts ()
   self.r.EIMC(0xffffffff)
end

function Intel:wait_linkup (timeout)
   if timeout == nil then timeout = self.linkup_wait end
   if self:link_status() then return true end
   for i=1,math.max(math.floor(timeout/self.linkup_wait_recheck), 1) do
      C.usleep(math.floor(self.linkup_wait_recheck * 1e6))
      if self:link_status() then return true end
   end
   return false
end

-- Initialze SHM control structures tracking VMDq configuration.
function Intel:init_vmdq ()
   assert(self.master, "must be master")

   -- set shm to indicate whether the NIC is in VMDq mode
   local vmdq_shm = shm.create(self.shm_root .. "vmdq_enabled",
                               vmdq_enabled_t)
   vmdq_shm.enabled = self.vmdq
   shm.unmap(vmdq_shm)
   if self.vmdq then
      -- create shared memory for tracking VMDq pools
      local vmdq_shm = shm.create(self.shm_root .. "vmdq_pools",
                                  vmdq_pools_t)
      -- explicitly initialize to 0 since we can't rely on cleanup
      for i=0, 63 do vmdq_shm.pools[i] = 0 end
      shm.unmap(vmdq_shm)
      -- set VMDq pooling method for all instances on this NIC
      local mode_shm = shm.create(self.shm_root .. "vmdq_queuing_mode",
                                  vmdq_queuing_mode_t)
      if self.vmdq_queuing_mode == "rss-32-4" then
         mode_shm.mode = 0
      elseif self.vmdq_queuing_mode == "rss-64-2" then
         mode_shm.mode = 1
      else
         error("Invalid VMDq queuing mode")
      end
      shm.unmap(mode_shm)
   end
end

-- Implements various status checks related to VMDq configuration.
-- Also checks that the main process used the same VMDq setting if
-- this is a worker process
function Intel:check_vmdq ()
   local vmdq_shm = shm.open(self.shm_root .. "vmdq_enabled", vmdq_enabled_t)

   if not self.vmdq then
      assert(not self.macaddr, "VMDq must be set to use MAC address")
      assert(not self.mirror, "VMDq must be set to specify mirroring rules")

      if not self.master then
         assert(vmdq_shm.enabled == 0,
                "VMDq was set by the main process for this NIC")
      end
   else
      assert(self.macaddr, "MAC address must be set in VMDq mode")

      if not self.master then
         assert(vmdq_shm.enabled == 1,
                "VMDq not set by the main process for this NIC")
      end
   end
end

-- In VMDq mode, selects an available pool if one isn't provided by the user.
--
-- This method runs before rxq/txq registers are loaded, because the rxq/txq registers
-- depend on the pool number prior to loading.
function Intel:select_pool()
   if not self.vmdq then return end

   self:lock_sw_sem()

   if self.registers == "i350" then
      self.max_pool = 8
   elseif self.registers == "82599ES" then
      -- max queue number is different in VMDq mode
      self.max_q = 128
      -- check the queuing mode in shm, adjust max pools based on that
      local mode_shm = shm.open(self.shm_root .. "vmdq_queuing_mode",
                                vmdq_queuing_mode_t)
      if mode_shm.mode == 0 then
         self.max_pool = 32
      else
         self.max_pool = 64
      end
      shm.unmap(mode_shm)
   else
      error(self.registers .. " does not support VMDq")
   end

   -- We use some shared memory to track which pool numbers are claimed
   local pool_shm = shm.open(self.shm_root .. "vmdq_pools", vmdq_pools_t)

   -- if the poolnum was set manually in the config, just use that
   if not self.poolnum then
      local available_pool

      for poolnum = 0, self.max_pool-1 do
         if pool_shm.pools[poolnum] == 0 then
            available_pool = poolnum
            break
         end
      end

      assert(available_pool, "No free VMDq pools are available")
      self.poolnum = available_pool
   else
      assert(self.poolnum < self.max_pool,
             string.format("Pool overflow: supports up to %d VMDq pools",
                           self.max_pool))
   end

   pool_shm.pools[self.poolnum] = 1
   shm.unmap(pool_shm)

   self:unlock_sw_sem()

   -- Once we know the pool number, figure out txq and rxq numbers. This
   -- needs to be done prior to loading registers.
   --
   -- for VMDq, make rxq/txq relative to the pool number
   local max_rxq_or_txq = self.max_q / self.max_pool
   assert(self.rxq >= 0 and self.rxq < max_rxq_or_txq,
          "rxqueue must be in 0.." .. max_rxq_or_txq-1)
   self.rxq = self.rxq + max_rxq_or_txq * self.poolnum
   assert(self.txq >= 0 and self.txq < max_rxq_or_txq,
          "txqueue must be in 0.." .. max_rxq_or_txq-1)
   self.txq = self.txq + max_rxq_or_txq * self.poolnum
end

-- used to disable the pool number for this instance on stop()
function Intel:unset_pool ()
  self:lock_sw_sem()

  local pool_shm = shm.open(self.shm_root .. "vmdq_pools", vmdq_pools_t)
  pool_shm.pools[self.poolnum] = 0
  shm.unmap(pool_shm)

  self:unlock_sw_sem()
end

rxdesc_t = ffi.typeof([[
struct {
   uint64_t address;
   uint16_t length, cksum;
   uint8_t status, errors;
   uint16_t vlan;
} __attribute__((packed))
]])

function Intel:init_rx_q ()
   if not self.rxq then return end
   assert((self.rxq >=0) and (self.rxq < self.max_q),
   "rxqueue must be in 0.." .. self.max_q-1)
   assert((self.ndesc %128) ==0,
   "ndesc must be a multiple of 128 (for Rx only)")	-- see 7.1.4.5

   self.rxqueue = ffi.new("struct packet *[?]", self.ndesc)
   self.rdh = 0
   self.rdt = 0
   -- setup 4.5.9
   local rxdesc_ring_t = ffi.typeof("$[$]", rxdesc_t, self.ndesc)
   self.rxdesc = ffi.cast(ffi.typeof("$&", rxdesc_ring_t),
   memory.dma_alloc(ffi.sizeof(rxdesc_ring_t)))

   if self.vmdq then
      self:set_vmdq_rx_pool()
   end

   -- Receive state
   self.r.RDBAL(tophysical(self.rxdesc) % 2^32)
   self.r.RDBAH(tophysical(self.rxdesc) / 2^32)
   self.r.RDLEN(self.ndesc * ffi.sizeof(rxdesc_t))

   for i = 0, self.ndesc-1 do
      local p= packet.allocate()
      self.rxqueue[i]= p
      self.rxdesc[i].address= tophysical(p.data)
      self.rxdesc[i].status= 0
   end
   self.r.SRRCTL(0)
   self.r.SRRCTL:set(bits {
      -- Set packet buff size to 0b10000 kbytes (max)
      BSIZEPACKET4 = 4,
      -- Drop packets when no descriptors
      Drop_En = self:offset("SRRCTL", "Drop_En")
   })
   self:lock_sw_sem()

   -- enable VLAN tag stripping in VMDq mode
   if self.vmdq then
      self:enable_strip_vlan()
   end

   self.r.RXDCTL:set( bits { Enable = 25 })
   self.r.RXDCTL:wait( bits { Enable = 25 })
   C.full_memory_barrier()
   self.r.RDT(self.ndesc - 1)

   self:rss_tab_build()
   self:update_rx_filters()
   if self.vmdq then
      self:enable_vmdq_rx_pool()
   end
   self:unlock_sw_sem()
end

txdesc_t = ffi.typeof("struct { uint64_t address, flags; }")
function Intel:init_tx_q ()                               -- 4.5.10
   if not self.txq then return end
   assert((self.txq >=0) and (self.txq < self.max_q),
   "txqueue must be in 0.." .. self.max_q-1)
   self.tdh = 0
   self.tdt = 0
   self.txqueue = ffi.new("struct packet *[?]", self.ndesc)

   -- 7.2.2.3
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

   -- for VMDq need some additional pool configs
   if self.vmdq then
      self:set_vmdq_tx_pool()
   end

   if self.r.DMATXCTL then
      self.r.DMATXCTL:set(bits { TE = 0 })
      self.r.TXDCTL:set(bits{SWFLSH=26, hthresh=8} + 32)
   end

   self.r.TXDCTL:set(bits { WTHRESH = 16, ENABLE = 25 })
   self.r.TXDCTL:wait(bits { ENABLE = 25 })

   if self.driver == "Intel1g" then
      self.r.TCTL:set(bits { TxEnable = 1 })
   end
end
function Intel:load_registers(key)
   local v = reg[key]
   if v.inherit then self:load_registers(v.inherit) end
   if v.singleton then register.define(v.singleton, self.r, self.base) end
   if v.array then register.define_array(v.array, self.r, self.base) end
   self.registers = key
end
function Intel:load_queue_registers(key)
  local v = reg[key]
  if v.inherit then self:load_queue_registers(v.inherit) end
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
   local li = self.input.input
   if li == nil then return end

   self.ingress_packet_rate_alarm:check()
   self.ingress_bandwith_alarm:check()

   while not empty(li) and self:can_transmit() do
      local p = receive(li)
      -- NB: the comment below is taken from intel_mp.lua, which disables
      -- this check for the same reason.
      --   We must not send packets that are bigger than the MTU.  This
      --   check is currently disabled to satisfy some selftests until
      --   agreement on this strategy is reached.
      --if p.length > self.mtu then
      --   packet.free(p)
      --   counter.add(self.shm.txdrop)
      --end
      self:transmit(p)
   end
   -- Reclaim transmit contexts
   local cursor = self.tdh
   self.tdh = self.r.TDH()	-- possible race condition, 7.2.2.4, check DD
   --C.full_memory_barrier()
   while cursor ~= self.tdh do
      if self.txqueue[cursor] ~= nil then -- Non-null pointer?
         packet.free(self.txqueue[cursor])
         self.txqueue[cursor] = nil
      end
      cursor = self:ringnext(cursor)
   end
   self.r.TDT(self.tdt)

   -- same code as in pull, but we only call it in case the rxq
   -- is disabled for this app
   if self.rxq and self.output.output then return end

   -- Sync device statistics.
   if self.run_stats and self.sync_timer() then self:sync_stats() end
end

function Intel:pull ()
   if not self.rxq then return end
   local lo = self.output.output
   if lo == nil then return end

   local pkts = 0
   while band(self.rxdesc[self.rdt].status, 0x01) == 1 and pkts < engine.pull_npackets do
      local p = self.rxqueue[self.rdt]
      p.length = self.rxdesc[self.rdt].length
      transmit(lo, p)

      local np = packet.allocate()
      self.rxqueue[self.rdt] = np
      self.rxdesc[self.rdt].address = tophysical(np.data)
      self.rxdesc[self.rdt].status = 0

      self.rdt = band(self.rdt + 1, self.ndesc-1)
      pkts = pkts + 1
   end
   -- This avoids RDT == RDH when every descriptor is available.
   self.r.RDT(band(self.rdt - 1, self.ndesc-1))

   -- Sync device statistics.
   if self.run_stats and self.sync_timer() then self:sync_stats() end
end

function Intel:unlock_sw_sem()
   self.r.SWSM:clr(bits { SMBI = 0 })
end

function Intel:ringnext (index)
   return band(index+1, self.ndesc-1)
end

function Intel:can_transmit ()
   return self:ringnext(self.tdt) ~= self.tdh
end

function Intel:transmit (p)
   self.txdesc[self.tdt].address = tophysical(p.data)
   self.txdesc[self.tdt].flags =
      bor(p.length, self.txdesc_flags, lshift(p.length+0ULL, 46))
   self.txqueue[self.tdt] = p
   self.tdt = self:ringnext(self.tdt)
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
   for i=0,9,1 do
      self.r.RSSRK[i](math.random(2^32))
   end
end

-- Set RSS redirection table, which has 64 * 2 entries which contain
-- RSS indices, the lower 4 bits (or fewer) of which are used to
-- select an RSS queue.
--
-- Also returns the current state of the redirection table
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
   local tab = {}
   for i=0,self.max_q-1,1 do
      if band(self.r.ALLRXDCTL[i](), bits { Enable = 25 }) > 0 then
         table.insert(tab, i)
      end
   end
   self:rss_tab(tab)
end
function Intel:stop ()
   if self.rxq then
      -- 4.5.9
      -- PBRWAC.PBE is mentioned in i350 only, not implemented here.
      self.r.RXDCTL:clr(bits { ENABLE = 25 })
      self.r.RXDCTL:wait(bits { ENABLE = 25 }, 0)
      -- removing the queue from rss first would be better but this
      -- is easier :(, we are going to throw the packets away anyway
      self:lock_sw_sem()
      self:rss_tab_build()
      self:unlock_sw_sem()
      C.usleep(100)
      -- TODO
      -- zero rxd.status, set rdt = rdh - 1
      -- poll for RXMEMWRAP to loop twice or buffer to empty
      self.r.RDT(0)
      self.r.RDH(0)
      self.r.RDBAL(0)
      self.r.RDBAH(0)
      for i = 0, self.ndesc-1 do
         if self.rxqueue[i] then
            packet.free(self.rxqueue[i])
            self.rxqueue[i] = nil
         end
      end
   end
   if self.txq then
      --TODO
      --TXDCTL[n].SWFLSH and wait
      --wait until tdh == tdt
      --wait on rxd[tdh].status = dd
      self:discard_unsent_packets()
      self.r.TXDCTL(0)
      self.r.TXDCTL:wait(bits { ENABLE = 25 }, 0)
   end
   if self.vmdq then
      self:unset_MAC()
      self:unset_VLAN()
      self:unset_mirror()
      self:unset_pool()
   end
   self:unset_tx_rate()
   if self.fd:flock("nb, ex") then
      -- delete shm state for this NIC
      shm.unlink(self.shm_root)
      self.r.CTRL:clr( bits { SETLINKUP = 6 } )
      --self.r.CTRL_EXT:clear( bits { DriverLoaded = 28 })
      pci.set_bus_master(self.pciaddress, false)
      pci.close_pci_resource(self.fd, self.base)
   end
   if self.run_stats then
      shm.delete_frame(self.stats)
   end
end

function Intel:discard_unsent_packets ()
   local old_tdt = self.tdt
   self.tdt = self.r.TDT()
   self.tdh = self.r.TDH()
   self.r.TDT(self.tdh)
   while old_tdt ~= self.tdh do
      old_tdt = band(old_tdt - 1, self.ndesc - 1)
      packet.free(self.txqueue[old_tdt])
      self.txdesc[old_tdt].address = -1
      self.txdesc[old_tdt].flags = 0
   end
   self.tdt = self.tdh
end

function Intel:sync_stats ()
   local set, stats = counter.set, self.stats
   set(stats.speed, self:link_speed())
   set(stats.status, self:link_status() and 1 or 2)
   set(stats.promisc, self:promisc() and 1 or 2)
   set(stats.rxbytes, self:rxbytes())
   set(stats.rxpackets, self:rxpackets())
   set(stats.rxmcast, self:rxmcast())
   set(stats.rxbcast, self:rxbcast())
   set(stats.rxdrop, self:rxdrop())
   set(stats.rxerrors, self:rxerrors())
   set(stats.txbytes, self:txbytes())
   set(stats.txpackets, self:txpackets())
   set(stats.txmcast, self:txmcast())
   set(stats.txbcast, self:txbcast())
   set(stats.txdrop, self:txdrop())
   set(stats.txerrors, self:txerrors())
   set(stats.rxdmapackets, self:rxdmapackets())
   for idx = 1, #self.queue_stats, 2 do
      local name, register = self.queue_stats[idx], self.queue_stats[idx+1]
      set(stats[name], register())
   end
end

-- set MAC address (4.6.10.1.4)
function Intel:set_MAC ()
   if not self.macaddr then return end
   local mac = macaddress:new(self.macaddr)
   self:add_receive_MAC(mac)
   self:set_transmit_MAC(mac)
end

function Intel:add_receive_MAC (mac)
   local mac_index

   -- scan to see if the MAC is already recorded or find the
   -- first free MAC index
   --
   -- the lock protects the critical section so that driver apps on
   -- separate processes do not use conflicting registers
   self:lock_sw_sem()
   for idx=1, self.max_mac_addr do
      local valid = self.r.RAH[idx]:bits(31, 1)

      if valid == 0 then
         mac_index = idx
         self.r.RAL[mac_index](mac:subbits(0,32))
         self.r.RAH[mac_index](bits({AV=31},mac:subbits(32,48)))
         break
      else
         if self.r.RAL[idx]() == mac:subbits(0, 32) and
            self.r.RAH[idx]:bits(0, 15) == mac:subbits(32, 48) then
            mac_index = idx
            break
         end
      end
   end
   self:unlock_sw_sem()

   assert(mac_index, "Max number of MAC addresses reached")

   -- associate MAC with the app's VMDq pool
   self:enable_MAC_for_pool(mac_index)
end

-- set VLAN for the driver instance
function Intel:set_VLAN ()
   local vlan = self.vlan
   if not vlan then return end
   assert(vlan>=0 and vlan<4096, "bad VLAN number")
   self:add_receive_VLAN(vlan)
   self:set_tag_VLAN(vlan)
end

function Intel:rxpackets () return self.r.GPRC()                 end
function Intel:txpackets () return self.r.GPTC()                 end
function Intel:rxmcast   () return self.r.MPRC() + self.r.BPRC() end
function Intel:rxbcast   () return self.r.BPRC()                 end
function Intel:txmcast   () return self.r.MPTC() + self.r.BPTC() end
function Intel:txbcast   () return self.r.BPTC()                 end

Intel1g.driver = "Intel1g"
Intel1g.offsets = {
    SRRCTL = {
       Drop_En = 31
    },
    MRQC = {
       RSS = 1
    }
}
Intel1g.max_mac_addr = 15
Intel1g.max_vlan = 32
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

   -- Determine PCI function to physical port mapping
   local lan_id = self.r.STATUS:bits(2,2)
   self.r.EEMNGCTL:wait(bits { CFG_DONE = 18 + lan_id })

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
   assert(self.master, "must be master")

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

   self:rss_enable()

   if self.vmdq then
      self:vmdq_enable()
   end

   self.r.RXCSUM(0)                          -- turn off all checksum offload
   self.r.RCTL:clr(bits { RXEN = 1 })
   self.r.RCTL(bits {
      UPE = 3,       -- Unicast Promiscuous
      MPE = 4,       -- Mutlicast Promiscuous
      LPE = 5,       -- Long Packet Reception / Jumbos
      BAM = 15,      -- Broadcast Accept Mode
      SECRC = 26,    -- Strip ethernet CRC
   })

   self.r.CTRL:set(bits { SETLINKUP = 6 })
   self.r.CTRL_EXT:clr( bits { LinkMode0 = 22, LinkMode1 = 23} )
   self.r.CTRL_EXT:clr( bits { PowerDown = 20 } )
   self.r.CTRL_EXT:set( bits { AutoSpeedDetect = 12, DriverLoaded = 28 })
   self.r.RLPML(self.mtu + 4) -- mtu + crc

   -- Tx->Rx MAC Loopback?
   if self.mac_loopback then
      error("NYI: mac_loopback mode")
   end

   self:unlock_sw_sem()
   if self.wait_for_link then self:wait_linkup() end
end

function Intel1g:link_status ()
   local mask = lshift(1, 1)
   return bit.band(self.r.STATUS(), mask) == mask
end
function Intel1g:link_speed ()
   return ({10000,100000,1000000,1000000})[1+bit.band(bit.rshift(self.r.STATUS(), 6),3)]
end
function Intel1g:promisc ()
   return band(self.r.RCTL(), lshift(1, 3)) ~= 0ULL
end
function Intel1g:rxbytes   () return self.r.GORCH()*2^32 + self.r.GORCL() end
function Intel1g:rxdrop    () return self.r.MPC() + self.r.RNBC()         end
function Intel1g:rxerrors  ()
   return self.r.CRCERRS() + self.r.RLEC()
      + self.r.RXERRC() + self.r.ALGNERRC()
end
function Intel1g:txbytes   () return self.r.GOTCH()*2^32 + self.r.GOTCL() end
function Intel1g:txdrop    () return self.r.ECOL()                        end
function Intel1g:txerrors  () return self.r.LATECOL()                     end
function Intel1g:rxdmapackets ()
   return self.r.RPTHC()
end

function Intel1g:init_queue_stats (frame)
   local perqregs = {
      rxdrops = "RQDPC",
      txdrops = "TQDPC",
      rxpackets = "PQGPRC",
      txpackets = "PQGPTC",
      rxbytes = "PQGORC",
      txbytes = "PQGOTC",
      rxmcast = "PQMPRC"
   }
   self.queue_stats = {}
   for i=0,self.max_q-1 do
      for k,v in pairs(perqregs) do
         local name = "q" .. i .. "_" .. k
         table.insert(self.queue_stats, name)
         table.insert(self.queue_stats, self.r[v][i])
         frame[name] = {counter}
      end
   end
end

function Intel1g:get_rxstats ()
   assert(self.rxq, "cannot retrieve rxstats without rxq")
   local rxc = self.rxq
   return {
      counter_id = rxc,
      packets = self.shm["q"..rxc.."_rxpackets"](),
      dropped = self.shm["q"..rxc.."_rxdrops"](),
      bytes = self.shm["q"..rxc.."_rxbytes"]()
   }
end

function Intel1g:get_txstats ()
   assert(self.txq, "cannot retrieve rxstats without txq")
   local txc = self.txq
   return {
      counter_id = txc,
      packets = self.shm["q"..txc.."_txpackets"](),
      bytes = self.shm["q"..txc.."_txbytes"]()
   }
end

-- noop because 1g NICs have per-queue counters that aren't
-- configurable
function Intel1g:set_rxstats () return end
function Intel1g:set_txstats () return end

-- enable VMDq mode, see 4.6.11.1
function Intel1g:vmdq_enable ()
   -- enable legacy control flow, VLAN mode
   self.r.CTRL:set(bits { RFCE=27, TFCE=28, VME=30 })

   -- 4.6.11.1.1 Global Filtering and Offload Capabilities
   assert(self.registers == "i350", "VMDq not supported by "..self.registers)
   -- 011b = Multiple receive queues as defined by VMDq based on packet
   -- destination MAC address (RAH.POOLSEL) and Ether-type queuing decision
   -- filters. NB: ignore self.vmdq_queuing_mode, i350 only supports 8 pools
   -- with one queue each.
   self.r.MRQC:bits(0, 3, 0x3)
   -- No packet splitting
   self.r.RPLPSRTYPE(0)
   -- VT_CTL.Dis_Def_pool: disable default pool, drop unmatched packets.
   -- VT_CTL.Rpl_En: replicate broadcast/multicast packets to all queues.
   self.r.VT_CTL:set(bits { Dis_Def_Pool=29, Rpl_En=30 }) 
   -- Enable loopback
   self.r.TXSWC:set(band(bits { Loopback_en=31 }, bit.rshift(23, 0xFF))) -- LLE
   -- clear VMVIR, VFTE for all pools, set them later
   for pool = 0, 7 do
      self.r.VFTE:clr(bits{VFTE=pool})
      self.r.VMVIR[pool](0)
   end
   -- enable vlan filter (8.10.1)
   self.r.RCTL:set(bits { VFE=18 })

   -- Set QDE bit for all queues
   for queue = 0, 7 do
      self.r.QDE:set(bits { QDE=queue })
   end
end

-- VMDq pool state (4.6.11.1.3)
function Intel1g:set_vmdq_rx_pool ()
   -- long packets enabled, multicast promiscuous, broadcast accept, accept
   -- untagged pkts
   self.r.VMOLR[self.poolnum]:set(bits { LPE=16, MPE=28, BAM=27, AUPE=24 })
   -- packet splitting none
   self.r.PSRTYPE[self.poolnum](0)
end

-- enable packet reception for this pool/VF (4.6.9.2)
function Intel1g:enable_vmdq_rx_pool ()
   self.r.VFRE:set(bits { VFRE=self.poolnum })
end

function Intel1g:update_rx_filters ()
   self.r.RCTL:set(bits { RXEN = 1 })
end

function Intel1g:set_vmdq_tx_pool ()
   self.r.VFTE:set(bits{VFTE=self.poolnum})
end

function Intel1g:set_mirror ()
   if not self.want_mirror then return end

   -- pick one of a limited (4) number of mirroring rules
   local mirror_ndx
   for idx=0, 3 do
      -- check if no mirroring enable bits (3:0) are set
      -- (i.e., this rule is unused and available)
      if self.r.VMRCTL[idx]:bits(0, 4) == 0 then
         mirror_ndx = idx
         break
      -- there's already a rule for this pool, overwrite
      elseif self.r.VMRCTL[idx]:bits(8, 3) == self.poolnum then
         mirror_ndx = idx
         break
      end
   end

   assert(mirror_ndx, "Max number of mirroring rules reached")

   local mirror_rule = 0

   -- mirror some or all pools
   if self.want_mirror.pool then
      mirror_rule = bits { VPME=0 }
      if self.want_mirror.pool == true then -- mirror all pools
         self.r.VMRVM[mirror_ndx](0xFF)
      elseif type(self.want_mirror.pool) == 'table' then
         local vm = 0
         for _, pool in ipairs(self.want_mirror.pool) do
            vm = bor(bits { VM=pool }, vm)
         end
         self.r.VMRVM[mirror_ndx](vm)
      end
   end

   -- mirror hardware port
   if self.want_mirror.port then
      if self.want_mirror.port == true or
            self.want_mirror.port == 'in' or
            self.want_mirror.port == 'inout' then
         mirror_rule = bor(bits{UPME=1}, mirror_rule)
      end
      if self.want_mirror.port == true or
            self.want_mirror.port == 'out' or
            self.want_mirror.port == 'inout' then
         mirror_rule = bor(bits{DPME=2}, mirror_rule)
      end
   end

   -- TODO: implement VLAN mirroring

   if mirror_rule ~= 0 then
      mirror_rule = bor(mirror_rule, lshift(self.poolnum, 8))
      self.r.VMRCTL[mirror_ndx]:set(mirror_rule)
   end
end

function Intel1g:unset_mirror ()
   for rule_i = 0, 3 do
      -- check if any mirror rule points here
      local rule_dest = self.r.VMRCTL[rule_i]:bits(8, 3)
      local bits = self.r.VMRCTL[rule_i]:bits(0, 4)
      if bits ~= 0 and rule_dest == self.poolnum then
         self.r.VMRCTL[rule_i](0x0)     -- clear rule
         self.r.VMRVLAN[rule_i](0x0)    -- clear VLANs mirrored
         self.r.VMRVM[rule_i](0x0)      -- clear pools mirrored
      end
   end
end

function Intel1g:enable_MAC_for_pool(mac_index)
   self.r.RAH[mac_index]:set(bits { Ena = 18 + self.poolnum })
end

function Intel1g:set_transmit_MAC (mac)
   local poolnum = self.poolnum or 0
   self.r.TXSWC:set(bits{MACAS=poolnum})
end

function Intel1g:unset_MAC ()
   local msk = bits { Ena = 18 + self.poolnum }
   for mac_index = 0, self.max_mac_addr do
      self.r.RAH[mac_index]:clr(msk)
   end
end

function Intel1g:add_receive_VLAN (vlan)
   local vlan_index, first_empty

   -- works the same as add_receive_MAC
   self:lock_sw_sem()
   for idx=0, self.max_vlan-1 do
      local valid = self.r.VLVF[idx]:bits(31, 1)

      if valid == 0 then
         if not first_empty then
            first_empty = idx
         end
      elseif self.r.VLVF[idx]:bits(0, 11) == vlan then
         vlan_index = idx
         break
      end
   end
   self:unlock_sw_sem()

   if not vlan_index and first_empty then
      vlan_index = first_empty
      self.r.VLVF[vlan_index](bits({Vl_En=31},vlan))
      self.r.VFTA[math.floor(vlan/32)]:set(bits{Ena=vlan%32})
   end

   assert(vlan_index, "Max number of VLAN IDs reached")

   self.r.VLVF[vlan_index]:set(bits { POOLSEL=12+self.poolnum })
end

function Intel1g:set_tag_VLAN (vlan)
   local poolnum = self.poolnum or 0
   self.r.TXSWC:set(bits{VLANAS=poolnum+8})
   self.r.VMVIR[poolnum](bits({VLANA=30}, vlan))
end

function Intel1g:unset_VLAN ()
   self.r.TXSWC:clr(bits{VLANAS=self.poolnum+8})

   for vlan_index = 0, self.max_vlan-1 do
      self.r.VMVIR[self.poolnum]:clr(bits( { VLANA=30 }))
      if self.r.VLVF[vlan_index]:bits(12+self.poolnum, 1) ~= 0 then
         -- found a vlan this pool belongs to
         self.r.VLVF[vlan_index]:clr(bits { POOLSEL=12+self.poolnum })
         if self.r.VLVF[vlan_index]:bits(12,self.max_pool) == 0 then
            -- it was the last pool of the vlan
            local vlan = tonumber(band(self.r.VLVF[vlan_index](), 0xFFF))
            self.r.VLVF[vlan_index]:clr(bits { Vl_En=31 })
            self.r.VFTA[math.floor(vlan/32)]:clr(bits{ Ena=vlan%32 })
         end
      end
   end
end

function Intel1g:enable_strip_vlan ()
   self.r.DVMOLR[self.poolnum]:set(bits { STRVLAN = 30 })
end

function Intel1g:set_tx_rate () return end
function Intel1g:unset_tx_rate () return end

Intel82599.driver = "Intel82599"
Intel82599.offsets = {
   SRRCTL = {
      Drop_En = 28
   },
   MRQC = {
       RSS = 0
   }
}
Intel82599.max_mac_addr = 127
Intel82599.max_vlan = 64

function Intel82599:link_status ()
   local mask = lshift(1, 30)
   return bit.band(self.r.LINKS(), mask) == mask
end
function Intel82599:link_speed ()
   local links = self.r.LINKS()
   local speed1, speed2 = lib.bitset(links, 29), lib.bitset(links, 28)
   return (speed1 and speed2 and 10000000000)    --  10 GbE
      or  (speed1 and not speed2 and 1000000000) --   1 GbE
      or  1000000                                -- 100 Mb/s
end
function Intel82599:promisc ()
   return band(self.r.FCTRL(), lshift(1, 9)) ~= 0ULL
end
function Intel82599:rxbytes  () return self.r.GORC64()   end
function Intel82599:rxdrop   ()
   local rxdrop = self.r.MNGPDC() + self.r.FCOERPDC()
   for i=0,15 do rxdrop = rxdrop + self.r.QPRDC[i]() end
   return rxdrop
end
function Intel82599:rxerrors ()
   return self.r.CRCERRS() + self.r.ILLERRC() + self.r.ERRBC() +
      self.r.RUC() + self.r.RFC() + self.r.ROC() + self.r.RJC()
end
function Intel82599:txbytes   () return self.r.GOTC64() end
function Intel82599:txdrop    () return 0               end
function Intel82599:txerrors  () return 0               end
function Intel82599:rxdmapackets ()
   return self.r.RXDGPC()
end

function Intel82599:init_queue_stats (frame)
   local perqregs = {
      rxdrops = "QPRDC",
      rxpackets = "QPRC",
      rxbytes = "QBRC64",
      txbytes = "QBTC64",
      txpackets = "QPTC",
   }
   self.queue_stats = {}
   for i=0,15 do
      for k,v in pairs(perqregs) do
         local v = perqregs[k]
         local name = "q" .. i .. "_" .. k
         table.insert(self.queue_stats, name)
         table.insert(self.queue_stats, self.r[v][i])
         frame[name] = {counter}
      end
   end
end

function Intel82599:init ()
   assert(self.master, "must be master")

   -- The 82599 devices sometimes just don't come up, especially when
   -- there is traffic already on the link.  If 2s have passed and the
   -- link is still not up, loop and retry.
   local reset_timeout = math.max(self.linkup_wait_recheck, 2)
   local reset_count = math.max(math.floor(self.linkup_wait / reset_timeout), 1)
   for i=1,reset_count do
      self:disable_interrupts()
      local reset = bits{ LinkReset=3, DeviceReset=26 }
      self.r.CTRL(reset)
      C.usleep(1000)
      self.r.CTRL:wait(reset, 0)
      self.r.EEC:wait(bits{AutoreadDone=9})           -- 3.
      self.r.RDRXCTL:wait(bits{DMAInitDone=3})        -- 4.

      -- 4.6.4.2
      -- 3.7.4.2
      self.r.AUTOC:set(bits { LMS0 = 13, LMS1 = 14 })
      self.r.AUTOC2(0)
      self.r.AUTOC2:set(bits { tenG_PMA_PMD_Serial = 17 })
      self.r.AUTOC:set(bits{restart_AN=12})

      if not self.wait_for_link then break end
      if self:wait_linkup(reset_timeout) then break end
   end

   -- 4.6.7
   self.r.RXCTRL(0)                             -- disable receive
   self.r.RXDSTATCTRL(0x10) -- map all queues to RXDGPC
   for i=1,127 do -- preserve device MAC
      self.r.RAL[i](0)
      self.r.RAH[i](0)
   end
   for i=0,127 do
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
      MPE = 8,
      UPE = 9,
      BAM = 10
   })

   self.r.VLNCTRL(0x8100)                    -- explicity set default
   self.r.RXCSUM(0)                          -- turn off all checksum offload

   self.r.RXPBSIZE[0]:bits(10,10, 0x200)
   self.r.TXPBSIZE[0]:bits(10,10, 0xA0)
   self.r.TXPBTHRESH[0](0xA0)
   for i=1,7 do
      self.r.RXPBSIZE[i]:bits(10,10, 0)
      self.r.TXPBSIZE[i]:bits(10,10, 0)
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
      self.r.ETQF[i](0)
      self.r.ETQS[i](0)
   end

   self.r.HLREG0(bits{
      TXCRCEN=0, RXCRCSTRP=1, JUMBOEN=2, rsv2=3,
      TXPADEN=10, rsvd3=11, rsvd4=13, MDCSPD=16
   })
   self.r.MAXFRS(lshift(self.mtu + 4, 16)) -- mtu + crc

   self.r.RDRXCTL(bits { CRCStrip = 1 })
   self.r.CTRL_EXT:set(bits {NS_DIS = 1})

   self:rss_enable()

   if self.vmdq then
      self:vmdq_enable()
   end

   -- Diagnostics—Intel 82599 10 GbE Controller
   -- 14.1 Link Loopback Operations
   -- Tx->Rx MAC Loopback?
   if self.mac_loopback then
      self.r.AUTOC(bits { FLU = 0, LMS0 = 13, Restart_AN = 12  })
      self.r.HLREG0:set(bits { LPBK = 15 })
   end

   self:unlock_sw_sem()
end

-- enable VMDq mode, see 4.6.10.1
-- follows the configuration flow in 4.6.11.3.3
-- (should only be called on the master instance)
function Intel82599:vmdq_enable ()
   -- must be set prior to setting MTQC (7.2.1.2.1)
   self.r.RTTDCS:set(bits { ARBDIS=6 })

   if self.vmdq_queuing_mode == "rss-32-4" then
      -- 1010 -> 32 pools, 4 RSS queues each
      self.r.MRQC:bits(0, 4, 0xA)
      -- Num_TC_OR_Q=10b -> 32 pools (4.6.11.3.3 and 8.2.3.9.15)
      self.r.MTQC(bits { VT_Ena=1, Num_TC_OR_Q=3 })
   else
      -- 1011 -> 64 pools, 2 RSS queues each
      self.r.MRQC:bits(0, 4, 0xB)
      -- Num_TC_OR_Q=01b -> 64 pools
      self.r.MTQC(bits { VT_Ena=1, Num_TC_OR_Q=2 })
   end

   -- TODO: not sure this is needed, but it's in intel10g
   -- disable RSC (7.11)
   self.r.RFCTL:set(bits { RSC_Dis=5 })

   -- enable virtualization, replication enabled, disable default pool
   self.r.PFVTCTL(bits { VT_Ena=0, Rpl_En=30, DisDefPool=29 })

   -- enable VMDq Tx to Rx loopback
   self.r.PFDTXGSWC:set(bits { LBE=0 })

   -- needs to be set for loopback (7.10.3.4)
   self.r.FCRTH[0](0x10000)

   -- enable vlan filter (4.6.7, 7.1.1.2)
   self.r.VLNCTRL:set(bits { VFE=30 })

   -- RTRUP2TC/RTTUP2TC cleared above in init

   -- DMA TX TCP max allowed size requests (set to 1MB)
   self.r.DTXMXSZRQ(0xFFF)

   -- disable PFC, enable legacy control flow
   self.r.MFLCN(bits { RFCE=3 })
   self.r.FCCFG(bits { TFCE=3 })

   -- RTTDT2C, RTTPT2C, RTRPT4C cleared above in init()

   -- QDE bit = 0 for all queues
   for i = 0, 127 do
      self.r.PFQDE(bor(lshift(1,16), lshift(i,8)))
   end

   -- clear RTTDT1C, PFVLVF for all pools, set them later
   for i = 0, 63 do
      self.r.RTTDQSEL(i)
      self.r.RTTDT1C(0x00)
   end

   -- disable TC arbitrations, enable packet buffer free space monitor
   self.r.RTTDCS:clr(bits { TDPAC=0, TDRM=4, BPBFSM=23 })
   self.r.RTTDCS:set(bits { VMPAC=1, BDPM=22 })
   self.r.RTTPCS:clr(bits { TPPAC=5, TPRM=8 })
   -- set RTTPCS.ARBD
   self.r.RTTPCS:bits(22, 10, 0x244)
   self.r.RTRPCS:clr(bits { RAC=2, RRM=1 })

   -- must be cleared after MTQC configuration (7.2.1.2.1)
   self.r.RTTDCS:clr(bits { ARBDIS=6 })
end

-- VMDq pool state (4.6.10.1.4)
function Intel82599:set_vmdq_rx_pool ()
   -- packet splitting none, enable 4 or 2 RSS queues per pool
   if self.max_pool == 32 then
      self.r.PSRTYPE[self.poolnum](bits { RQPL=30 })
   else
      self.r.PSRTYPE[self.poolnum](bits { RQPL=29 })
   end
   -- multicast promiscuous, broadcast accept, accept untagged pkts
   self.r.PFVML2FLT[self.poolnum]:set(bits { MPE=28, BAM=27, AUPE=24 })
end

-- enable packet reception for this pool/VF (4.6.10.1.4)
function Intel82599:enable_vmdq_rx_pool ()
   self.r.PFVFRE[math.floor(self.poolnum/32)]:set(bits{VFRE=self.poolnum%32})
end

function Intel82599:update_rx_filters ()
   self.r.RXCTRL:set(bits{ RXEN=0 })
   self.r.DCA_RXCTRL:clr(bits{RxCTRL=12})
end

function Intel82599:set_vmdq_tx_pool ()
   self.r.RTTDQSEL(self.poolnum)
   -- set baseline value for credit refill for tx bandwidth algorithm
   self.r.RTTDT1C(0x80)
   -- enables packet Tx for this VF's pool
   self.r.PFVFTE[math.floor(self.poolnum/32)]:set(bits{VFTE=self.poolnum%32})
   -- enable TX loopback
   self.r.PFVMTXSW[math.floor(self.poolnum/32)]:set(bits{LLE=self.poolnum%32})
end

function Intel82599:set_mirror ()
   if not self.want_mirror then return end

   -- set MAC promiscuous
   self.r.PFVML2FLT[self.poolnum]:set(bits{
      AUPE=24, ROMPE=25, ROPE=26, BAM=27, MPE=28})

   -- pick one of a limited (4) number of mirroring rules
   local mirror_ndx
   for idx=0, 3 do
      -- check if no mirroring enable bits (3:0) are set
      -- (i.e., this rule is unused and available)
      if self.r.PFMRCTL[idx]:bits(0, 4) == 0 then
         mirror_ndx = idx
         break
      -- there's already a rule for this pool, overwrite
      elseif self.r.PFMRCTL[idx]:bits(8, 5) == self.poolnum then
         mirror_ndx = idx
         break
      end
   end

   assert(mirror_ndx, "Max number of mirroring rules reached")

   local mirror_rule = 0ULL

   -- mirror some or all pools
   if self.want_mirror.pool then
      mirror_rule = bor(bits{VPME=0}, mirror_rule)
      if self.want_mirror.pool == true then -- mirror all pools
         self.r.PFMRVM[mirror_ndx](0xFFFFFFFF)
         self.r.PFMRVM[mirror_ndx+4](0xFFFFFFFF)
      elseif type(self.want_mirror.pool) == 'table' then
         local bm0 = self.r.PFMRVM[mirror_ndx]()
         local bm1 = self.r.PFMRVM[mirror_ndx+4]()
         for _, pool in ipairs(self.want_mirror.pool) do
            if pool <= 64 then
               bm0 = bor(lshift(1, pool), bm0)
            else
               bm1 = bor(lshift(1, pool-64), bm1)
            end
         end
         self.r.PFMRVM[mirror_ndx](bm0)
         self.r.PFMRVM[mirror_ndx+4](bm1)
      end
   end

   -- mirror hardware port
   if self.want_mirror.port then
      if self.want_mirror.port == true or
            self.want_mirror.port == 'in' or
            self.want_mirror.port == 'inout' then
         mirror_rule = bor(bits{UPME=1}, mirror_rule)
      end
      if self.want_mirror.port == true or
            self.want_mirror.port == 'out' or
            self.want_mirror.port == 'inout' then
         mirror_rule = bor(bits{DPME=2}, mirror_rule)
      end
   end

   -- TODO: implement VLAN mirroring

   if mirror_rule ~= 0 then
      mirror_rule = bor(mirror_rule, lshift(self.poolnum, 8))
      self.r.PFMRCTL[mirror_ndx]:set(mirror_rule)
   end
end

function Intel82599:unset_mirror ()
   for rule_i = 0, 3 do
      -- check if any mirror rule points here
      local rule_dest = band(bit.rshift(self.r.PFMRCTL[rule_i](), 8), 63)
      local bits = band(self.r.PFMRCTL[rule_i](), 0x07)
      if bits ~= 0 and rule_dest == self.poolnum then
         self.r.PFMRCTL[rule_i](0x0)     -- clear rule
         self.r.PFMRVLAN[rule_i](0x0)    -- clear VLANs mirrored
         self.r.PFMRVLAN[rule_i+4](0x0)
         self.r.PFMRVM[rule_i](0x0)      -- clear pools mirrored
         self.r.PFMRVM[rule_i+4](0x0)
      end
   end
end

function Intel82599:enable_MAC_for_pool (mac_index)
   self.r.MPSAR[2*mac_index + math.floor(self.poolnum/32)]
      :set(bits{Ena=self.poolnum%32})
end

function Intel82599:set_transmit_MAC (mac)
   local poolnum = self.poolnum or 0
   self.r.PFVFSPOOF[math.floor(poolnum/8)]:set(bits{MACAS=poolnum%8})
end

function Intel82599:unset_MAC ()
   local msk = bits { Ena=self.poolnum%32 }
   for mac_index = 0, self.max_mac_addr do
      self.r.MPSAR[2*mac_index + math.floor(self.poolnum/32)]:clr(msk)
   end
end

function Intel82599:add_receive_VLAN (vlan)
   local vlan_index, first_empty

   -- works the same as add_receive_MAC
   self:lock_sw_sem()
   for idx=0, self.max_vlan-1 do
      local valid = self.r.PFVLVF[idx]:bits(31, 1)

      if valid == 0 then
         if not first_empty then
            first_empty = idx
         end
      elseif self.r.PFVLVF[idx]:bits(0, 11) == vlan then
         vlan_index = idx
         break
      end
   end
   self:unlock_sw_sem()

   if not vlan_index and first_empty then
      vlan_index = first_empty
      self.r.VFTA[math.floor(vlan/32)]:set(bits{Ena=vlan%32})
      self.r.PFVLVF[vlan_index](bits({Vl_En=31},vlan))
   end

   assert(vlan_index, "Max number of VLAN IDs reached")

   self.r.PFVLVFB[2*vlan_index + math.floor(self.poolnum/32)]
      :set(bits{PoolEna=self.poolnum%32})
end

function Intel82599:set_tag_VLAN (vlan)
   local poolnum = self.poolnum or 0
   self.r.PFVFSPOOF[math.floor(poolnum/8)]:set(bits{VLANAS=poolnum%8+8})
   -- set Port VLAN ID & VLANA to always add VLAN tag
   self.r.PFVMVIR[poolnum](bits({VLANA=30}, vlan))
end

function Intel82599:unset_VLAN ()
   local r = self.r
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
         end
      end
   end
end

function Intel82599:enable_strip_vlan ()
   self.r.RXDCTL:set(bits { VME = 30 })
end

function Intel82599:set_tx_rate ()
   if not self.txq then return end
   self.r.RTTDQSEL(self.poolnum or self.txq)
   if self.rate_limit >= 10 then
      -- line rate = 10,000 Mb/s
      local factor = 10000 / tonumber(self.rate_limit)
      -- 10.14 bits
      factor = bit.band(math.floor(factor*2^14+0.5), 2^24-1)
      self.r.RTTBCNRC(bits({RS_ENA=31}, factor))
   else
      self.r.RTTBCNRC(0x00)
   end
   self.r.RTTDT1C(bit.band(math.floor(self.priority * 0x80), 0x3FF))
end

function Intel82599:unset_tx_rate ()
   self.rate_limit = 0
   self.priority = 0
   self:set_tx_rate()
end

-- return rxstats for the counter assigned to this queue
-- the data has to be read from the shm frame since the main instance
-- is in control of the counter registers (and clears them on read)
function Intel82599:get_rxstats ()
   assert(self.rxcounter and self.rxq, "cannot retrieve rxstats")
   local rxc = self.rxcounter
   return {
      counter_id = rxc,
      packets = self.shm["q"..rxc.."_rxpackets"](),
      dropped = self.shm["q"..rxc.."_rxdrops"](),
      bytes = self.shm["q"..rxc.."_rxbytes"]()
   }
end

function Intel82599:get_txstats ()
   assert(self.txcounter and self.txq, "cannot retrieve txstats")
   local txc = self.txcounter
   return {
      counter_id = txc,
      packets = self.shm["q"..txc.."_txpackets"](),
      bytes = self.shm["q"..txc.."_txbytes"]()
   }
end

-- enable the given counter for this app's rx queue
function Intel82599:set_rxstats ()
   if not self.rxcounter or not self.rxq then return end
   local counter = self.rxcounter
   assert(counter>=0 and counter<16, "bad Rx counter")
   self.r.RQSMR[math.floor(self.rxq/4)]:set(lshift(counter,8*(self.rxq%4)))
end

-- enable the given counter for this app's tx queue
function Intel82599:set_txstats ()
   if not self.txcounter or not self.txq then return end
   local counter = self.txcounter
   assert(counter>=0 and counter<16, "bad Tx counter")
   self.r.TQSM[math.floor(self.txq/4)]:set(lshift(counter,8*(self.txq%4)))
end

function Intel:debug (args)
   local args = args or {}
   local pfx = args.prefix or "DEBUG_"
   local prnt = args.print or true
   local r = { rss = "", rxds = 0 }
   r.LINK_STATUS = self:link_status()
   r.rdt = self.rdt
   if self.output.output then
      r.txpackets = counter.read(self.output.output.stats.txpackets)
   end
   if self.input.input then
      r.rxpackets = counter.read(self.input.input.stats.rxpackets)
   end
   r.rdtstatus = band(self.rxdesc[self.rdt].status, 1) == 1
   self:lock_sw_sem()
   for k,_ in pairs(self:rss_tab()) do
      r.rss = r.rss .. k .. " "
   end
   self:unlock_sw_sem()

   r.rxds = 0
   for i=0,self.ndesc-1 do
      if band(self.rxdesc[i].status, 1) == 1 then
         r.rxds = r.rxds + 1
      end
   end
   r.rdbal = tophysical(self.rxdesc) % 2^32
   r.rdbah = tophysical(self.rxdesc) / 2^32
   r.rdlen = self.ndesc * 16
   r.ndesc = self.ndesc

   r.master = self.master

   for _,k in pairs({"RDH", "RDT", "RDBAL", "RDBAH", "RDLEN"}) do
      r[k] = tonumber(self.r[k]())
   end

   local master_regs = {}
   if self.driver == "Intel82599" then
      r.rxdctrl =
         band(self.r.RXDCTL(), bits{enabled = 25}) == bits{enabled = 25}
      master_regs = {"RXCTRL"}
   elseif self.driver == "Intel1g" then
      r.rxen = band(self.r.RCTL(), bits{ RXEN = 1 }) == bits{ RXEN = 1 }
   end
   if self.run_stats then
      for k,v in pairs(self.stats) do
         r[k] = counter.read(v)
      end
   end
   if r.master then
      for _,k in pairs(master_regs) do
         r[k] = tonumber(self.r[k]())
      end
   end

   if prnt then
     local keys = {}
     for k,_ in pairs(r) do
       table.insert(keys, k)
     end
     table.sort(keys)
     for _,k in ipairs(keys) do
        print(pfx..k, r[k])
     end
   end
   return r
end
