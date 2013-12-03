--- Device driver for the Intel 82599 10-Gigabit Ethernet controller.
--- This is one of the most popular production 10G Ethernet
--- controllers on the market and it is readily available in
--- affordable (~$400) network cards made by Intel and others.
---
--- You will need to familiarize yourself with the excellent [data
--- sheet]() to understand this module.

module(...,package.seeall)

local ffi      = require "ffi"
local C        = ffi.C
local lib      = require("core.lib")
local memory   = require("core.memory")
local packet   = require("core.packet")
local bus      = require("lib.hardware.bus")
local register = require("lib.hardware.register")
                 require("apps.intel.intel_h")
                 require("core.packet_h")

local bits, bitset = lib.bits, lib.bitset

num_descriptors = 32 * 1024
--num_descriptors = 32

--- ### Initialization

function new (pciaddress)
   local dev = { pciaddress = pciaddress, -- PCI device address
                 info = bus.device_info(pciaddress),
                 r = {},           -- Configuration registers
                 s = {},           -- Statistics registers
                 txdesc = 0,     -- Transmit descriptors (pointer)
                 txdesc_phy = 0, -- Transmit descriptors (physical address)
                 txpackets = {},   -- Tx descriptor index -> packet mapping
                 tdh = 0,          -- Cache of transmit head (TDH) register
                 tdt = 0,          -- Cache of transmit tail (TDT) register
                 rxdesc = 0,     -- Receive descriptors (pointer)
                 rxdesc_phy = 0, -- Receive descriptors (physical address)
                 rxbuffers = {},   -- Rx descriptor index -> buffer mapping
                 rdh = 0,          -- Cache of receive head (RDH) register
                 rdt = 0,          -- Cache of receive tail (RDT) register
                 rxnext = 0        -- Index of next buffer to receive
              }
   setmetatable(dev, {__index = getfenv()})
   return dev
end

function open (dev)
   dev.info.set_bus_master(dev.pciaddress, true)
   local base = dev.info.map_pci_memory(dev.pciaddress, 0)
   register.define(config_registers_desc, dev.r, base)
   register.define(statistics_registers_desc, dev.s, base)
   dev.txpackets = ffi.new("struct packet *[?]", num_descriptors)
   dev.rxbuffers = ffi.new("struct buffer *[?]", num_descriptors)
   init(dev)
end

--- See data sheet section 4.6.3 "Initialization Sequence."

function init (dev)
   init_dma_memory(dev)
   disable_interrupts(dev)
   global_reset(dev)
   wait_eeprom_autoread(dev)
   wait_dma(dev)
   init_statistics(dev)
   init_receive(dev)
   init_transmit(dev)
end

function init_dma_memory (dev)
   dev.rxdesc, dev.rxdesc_phy =
      dev.info.dma_alloc(num_descriptors * ffi.sizeof(rxdesc_t))
   dev.txdesc, dev.txdesc_phy =
      dev.info.dma_alloc(num_descriptors * ffi.sizeof(txdesc_t))
   -- Add bounds checking
   dev.rxdesc = lib.bounds_checked(rxdesc_t, dev.rxdesc, 0, num_descriptors)
   dev.txdesc = lib.bounds_checked(txdesc_t, dev.txdesc, 0, num_descriptors)
end

function global_reset (dev)
   local reset = bits{LinkReset=3, DeviceReset=26}
   dev.r.CTRL(reset)
   C.usleep(1000)
   dev.r.CTRL:wait(reset, 0)
end

function disable_interrupts (dev) end --- XXX do this
function wait_eeprom_autoread (dev)
   dev.r.EEC:wait(bits{AutoreadDone=9})
end

function wait_dma (dev)
   dev.r.RDRXCTL:wait(bits{DMAInitDone=3})
end

function init_statistics (dev)
   -- Read and then zero each statistic register
   for _,reg in pairs(dev.s) do reg:read() reg:reset() end
end

function init_receive (dev)
   set_promiscuous_mode(dev) -- NB: don't need to program MAC address filter
   dev.r.HLREG0:clr(bits({RXLNGTHERREN=27}))
   dev.r.RDBAL(dev.rxdesc_phy % 2^32)
   dev.r.RDBAH(dev.rxdesc_phy / 2^32)
   dev.r.RDLEN(num_descriptors * ffi.sizeof("union rx"))
   dev.r.RXDCTL(bits{Enable=25})
   dev.r.RXDCTL:wait(bits{enable=25})
   dev.r.RXCTRL:set(bits{RXEN=0})
end

function set_promiscuous_mode (dev)
   dev.r.FCTRL(bits({MPE=8, UPE=9, BAM=10}))
end

function init_transmit (dev)
   dev.r.HLREG0:set(bits{TXCRCEN=0})
   dev.r.TDBAL(dev.txdesc_phy % 2^32)
   dev.r.TDBAH(dev.txdesc_phy / 2^32)
   dev.r.TDLEN(num_descriptors * ffi.sizeof("union tx"))
   dev.r.DMATXCTL(bits{TE=0})
   dev.r.TXDCTL:wait(bits{Enable=25})
end

--- ### Transmit

--- See datasheet section 7.1 "Inline Functions -- Transmit Functionality."

txdesc_flags = bits{eop=24,ifcs=25}
function transmit (dev, p)
   assert(p.niovecs == 1, "only supports one-buffer packets")
   local iov = p.iovecs[0]
   assert(iov.offset == 0)
   dev.txdesc[dev.tdt].data.address = iov.buffer.physical + iov.offset
   dev.txdesc[dev.tdt].data.options = bit.bor(iov.length, txdesc_flags)
   dev.txpackets[dev.tdt] = p
   dev.tdt = (dev.tdt + 1) % num_descriptors
   packet.ref(p)
end

function sync_transmit (dev)
   local old_tdh = dev.tdh
   dev.tdh = dev.r.TDH()
   C.full_memory_barrier()
   -- Release processed buffers
   while old_tdh ~= dev.tdh do
      packet.deref(dev.txpackets[old_tdh])
      dev.txpackets[old_tdh] = nil
      old_tdh = (old_tdh + 1) % num_descriptors
   end
   dev.r.TDT(dev.tdt)
end

function can_transmit (dev)
   return (dev.tdt + 1) % num_descriptors ~= dev.tdh
end

--- ### Receive

--- See datasheet section 7.1 "Inline Functions -- Receive Functionality."

function receive (dev)
   assert(dev.rdh ~= dev.rxnext)
   local p = packet.allocate()
   local b = dev.rxbuffers[dev.rxnext]
   local wb = dev.rxdesc[dev.rxnext].wb
   assert(wb.length > 0)
   assert(bit.band(wb.status, 1) == 1) -- Descriptor Done
   packet.add_iovec(p, b, wb.length)
   dev.rxnext = (dev.rxnext + 1) % num_descriptors
   return p
end

function can_receive (dev)
   return bit.band(dev.rxdesc[dev.rxnext].wb.status, 1) == 1
   -- return dev.rxnext ~= dev.rdh
end

function can_add_receive_buffer (dev)
   return (dev.rdt + 1) % num_descriptors ~= dev.rxnext
end

function add_receive_buffer (dev, b)
   assert(can_add_receive_buffer(dev))
   local desc = dev.rxdesc[dev.rdt].data
   desc.address, desc.dd = b.physical, b.size
   dev.rxbuffers[dev.rdt] = b
   dev.rdt = (dev.rdt + 1) % num_descriptors
end

function sync_receive (dev)
   -- XXX I have been surprised to see RDH = num_descriptors,
   --     must check what that means. -luke
   dev.rdh = math.min(dev.r.RDH(), num_descriptors-1)
   assert(dev.rdh < num_descriptors)
   C.full_memory_barrier()
   dev.r.RDT(dev.rdt)
end

txdesc_t = ffi.typeof [[
      union { struct { uint64_t address, options; } data;
              struct { uint64_t a, b; }             context; }
]]

rxdesc_t = ffi.typeof [[
      union { struct { uint64_t address, dd; } __attribute__((packed)) data;
              struct { uint64_t address;
                       uint16_t length,fragcsum;
                       uint8_t  status,error;
                       uint16_t vlan; } __attribute__((packed)) wb;
            }
]]

function wait_linkup (dev)
   lib.waitfor2("linkup", function() return linkup(dev) end, 20, 250000)
end

--- ### Status and diagnostics

function linkup (dev)
   return bitset(dev.r.LINKS(), 30)
end

function get_configuration_state (dev)
   return { AUTOC = dev.r.AUTOC(), HLREG0 = dev.r.HLREG0() }
end

function restore_configuration_state (dev, saved_state)
   dev.r.AUTOC(saved_state.AUTOC)
   dev.r.HLREG0(saved_state.HLREG0)
end

function enable_mac_loopback (dev)
   dev.r.AUTOC:set(bits({ForceLinkUp=0, LMS10G=13}))
   dev.r.HLREG0:set(bits({Loop=15}))
end

function open_for_loopback_test (dev)
   open(dev)
   enable_mac_loopback(dev)
   wait_linkup(dev)
end

--- ### Configuration register description.

config_registers_desc = [[
AUTOC     0x042A0 -            RW Auto Negotiation Control
CTRL      0x00000 -            RW Device Control
DMATXCTL  0x04A80 -            RW DMA Tx Control
EEC       0x10010 -            RW EEPROM/Flash Control
FCTRL     0x05080 -            RW Filter Control
HLREG0    0x04240 -            RW MAC Core Control 0
LINKS     0x042A4 -            RO Link Status Register
RDBAL     0x01000 +0x40*0..63  RW Receive Descriptor Base Address Low
RDBAH     0x01004 +0x40*0..63  RW Receive Descriptor Base Address High
RDLEN     0x01008 +0x40*0..63  RW Receive Descriptor Length
RDH       0x01010 +0x40*0..63  RO Receive Descriptor Head
RDT       0x01018 +0x40*0..63  RW Receive Descriptor Tail
RXDCTL    0x01028 +0x40*0..63  RW Receive Descriptor Control
RDRXCTL   0x02F00 -            RW Receive DMA Control
RTTDCS    0x04900 -            RW DCB Transmit Descriptor Plane Control
RXCTRL    0x03000 -            RW Receive Control
SECRX_DIS 0x08D00 -            RW Security RX Control
STATUS    0x00008 -            RO Device Status
TDBAL     0x06000 +0x40*0..127 RW Transmit Descriptor Base Address Low
TDBAH     0x06004 +0x40*0..127 RW Transmit Descriptor Base Address High
TDH       0x06010 +0x40*0..127 RW Transmit Descriptor Head
TDT       0x06018 +0x40*0..127 RW Transmit Descriptor Tail
TDLEN     0x06008 +0x40*0..127 RW Transmit Descriptor Length
TDWBAL    0x06038 +0x40*0..127 RW Tx Desc Completion Write Back Address Low
TDWBAH    0x0603C +0x40*0..127 RW Tx Desc Completion Write Back Address High
TXDCTL    0x06028 +0x40*0..127 RW Transmit Descriptor Control
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
RQSMR         0x02300 +0x4*0..31  RC Receive Queue Statistic Mapping Registers
RXDSTATCTRL   0x02F40 -           RC Rx DMA Statistic Counter Control
TQSM          0x08600 +0x4*0..31  RC Transmit Queue Statistic Mapping Registers
QPRC          0x01030 +0x40*0..15 RC Queue Packets Received Count
QPRDC         0x01430 +0x40*0..15 RC Queue Packets Received Drop Count
QBRC_L        0x01034 +0x40*0..15 RC Queue Bytes Received Count Low
QBRC_H        0x01038 +0x40*0..15 RC Queue Bytes Received Count High
QPTC          0x08680 +0x4*0..15  RC Queue Packets Transmitted Count
QBTC_L        0x08700 +0x8*0..15  RC Queue Bytes Transmitted Count Low
QBTC_H        0x08704 +0x8*0..15  RC Queue Bytes Transmitted Count High
FCCRC         0x05118 -           RC FC CRC Error Count
FCOERPDC      0x0241C -           RC FCoE Rx Packets Dropped Count
FCLAST        0x02424 -           RC FC Last Error Count
FCOEPRC       0x02428 -           RC FCoE Packets Received Count
FCOEDWRC      0x0242C -           RC FCOE DWord Received Count
FCOEPTC       0x08784 -           RC FCoE Packets Transmitted Count
FCOEDWTC      0x08788 -           RC FCoE DWord Transmitted Count
]]
