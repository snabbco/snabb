--- Device driver for the Intel 82599 10-Gigabit Ethernet controller.
--- This is one of the most popular production 10G Ethernet
--- controllers on the market and it is readily available in
--- affordable (~$400) network cards made by Intel and others.
---
--- You will need to familiarize yourself with the excellent [data
--- sheet]() to understand this module.

-- This module is loaded once per PCI device. See `pci.lua` for details.
local moduleinstance,pciaddress = ...

if pciaddress == nil then
   print("WARNING: intel10g loaded as normal module; should be device-specific.")
end

module(moduleinstance,package.seeall)

local ffi = require "ffi"
local C = ffi.C
local lib = require("lib")
local pci = require("pci")
local register = require("register")
local memory = require("memory")
local test = require("test")
require("intel_h")
local bits, bitset = lib.bits, lib.bitset

num_descriptors = 32 * 1024
rxdesc, rxdesc_phy, txdesc, txdesc_phy = nil

r = {} -- Configuration registers
s = {} -- Statistics registers

--- ### Initialization

function open ()
   pci.set_bus_master(pciaddress, true)
   base = ffi.cast("uint32_t*", pci.map_pci_memory(pciaddress, 0))
   register.define(config_registers_desc, r, base)
   register.define(statistics_registers_desc, s, base)
   init()
end

--- See data sheet section 4.6.3 "Initialization Sequence."

function init ()
   init_dma_memory()
   disable_interrupts()
   global_reset()
   wait_eeprom_autoread()
   wait_dma()
   init_statistics()
   init_receive()
   init_transmit()
end

function init_dma_memory ()
   rxdesc, rxdesc_phy = memory.dma_alloc(num_descriptors * ffi.sizeof(rxdesc_t))
   txdesc, txdesc_phy = memory.dma_alloc(num_descriptors * ffi.sizeof(txdesc_t))
   -- Add bounds checking
   rxdesc  = lib.bounds_checked(rxdesc_t, rxdesc, 0, num_descriptors)
   txdesc  = lib.bounds_checked(txdesc_t, txdesc, 0, num_descriptors)
end

function global_reset ()
   local reset = bits{LinkReset=3, DeviceReset=26}
   r.CTRL(reset)
   C.usleep(1000)
   r.CTRL:wait(reset, 0)
end

function disable_interrupts () end --- XXX do this
function wait_eeprom_autoread () r.EEC:wait(bits{AutoreadDone=9}) end
function wait_dma ()             r.RDRXCTL:wait(bits{DMAInitDone=3})  end

function init_statistics ()
   -- Read and then zero each statistic register
   for _,reg in pairs(s) do reg:read() reg:reset() end
end

function init_receive ()
   set_promiscuous_mode() -- accept all, no need to configure MAC address filter
--   r.RDRXCTL:set(bits{CRCStrip=0})
--   r.HLREG0:clr(bit.bor(bit.lshift(0x1f, 17), -- RSCFRSTSIZE
--                bits({RXLNGTHERREN=27, UndocumentedRXCRCSTRP=1})))
   r.HLREG0:clr(bits({RXLNGTHERREN=27}))
   r.RDBAL(rxdesc_phy % 2^32)
   r.RDBAH(rxdesc_phy / 2^32)
   r.RDLEN(num_descriptors * ffi.sizeof("union rx"))
   r.RXDCTL(bits{Enable=25})
   r.RXDCTL:wait(bits{enable=25})
   r.RXCTRL:set(bits{RXEN=0})
end

function set_promiscuous_mode () r.FCTRL(bits({MPE=8, UPE=9, BAM=10})) end

function init_transmit ()
   r.HLREG0:set(bits{TXCRCEN=0})
   r.TDBAL(txdesc_phy % 2^32)
   r.TDBAH(txdesc_phy / 2^32)
   r.TDLEN(num_descriptors * ffi.sizeof("union tx"))
   r.DMATXCTL(bits{TE=0})
   r.TXDCTL:wait(bits{Enable=25})
end

--- ### Transmit

--- See datasheet section 7.1 "Inline Functions -- Transmit Functionality."

txbuffers = {}
tdh, tdt = 0, 0 -- Cached values of TDT and TDH
txdesc_flags = bits{eop=24,ifcs=25}
function transmit (buf)
--   print("buf",buf)
   txdesc[tdt].data.address = buf.phy
   txdesc[tdt].data.options = bit.bor(buf.size, txdesc_flags)
   txbuffers[tdt] = buf
   tdt = (tdt + 1) % num_descriptors
   buffer.ref(buf)
end

function sync_transmit ()
   local old_tdh = tdh
   tdh = r.TDH()
   C.full_memory_barrier()
   -- Release processed buffers
   while old_tdh ~= tdh do
      buffer.deref(txbuffers[old_tdh])
      txbuffers[old_tdh] = nil
      old_tdh = (old_tdh + 1) % num_descriptors
   end
   r.TDT(tdt)
end

function can_transmit () return (tdt + 1) % num_descriptors ~= tdh end

--- ### Receive

--- See datasheet section 7.1 "Inline Functions -- Receive Functionality."

-- Queued
rxbuffers = {}
rdh, rdt, rxnext = 0, 0, 0

function receive ()
   assert(rdh ~= rxnext)
   local buf = rxbuffers[rxnext]
   local wb = rxdesc[rxnext].wb
   buf.size = wb.length
   assert(bit.band(wb.status, 1) == 1) -- Descriptor Done
   rxnext = (rxnext + 1) % num_descriptors
   buffer.deref(buf)
   assert(buf.size > 0)
   return buf
end

function can_receive () return rxnext ~= rdh end

function can_add_receive_buffer ()
   return (rdt + 1) % num_descriptors ~= rxnext
end

function add_receive_buffer (buf)
   assert(can_add_receive_buffer())
   local desc = rxdesc[rdt].data
   desc.address, desc.dd = buf.phy, buf.size
   rxbuffers[rdt] = buf
   rdt = (rdt + 1) % num_descriptors
   buffer.ref(buf)
end

function sync_receive ()
   -- XXX I have been surprised to see RDH = num_descriptors,
   --     must check what that means. -luke
   rdh = math.min(r.RDH(), num_descriptors-1)
   assert(rdh < num_descriptors)
   C.full_memory_barrier()
   r.RDT(rdt)
end

function sync () sync_receive() sync_transmit() end

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

function wait_linkup ()
   test.waitfor("linkup", linkup, 20, 250000)
end

--- ### Status and diagnostics

function linkup () return bitset(r.LINKS(), 30) end

function get_configuration_state ()
   return { AUTOC = r.AUTOC(), HLREG0 = r.HLREG0() }
end

function restore_configuration_state (saved_state)
   r.AUTOC(saved_state.AUTOC)
   r.HLREG0(saved_state.HLREG0)
end

function enable_mac_loopback ()
   r.AUTOC:set(bits({ForceLinkUp=0, LMS10G=13}))
   r.HLREG0:set(bits({Loop=15}))
end

function selftest (options)
   local port = require("port")
   options = options or {}
   io.write("intel10g selftest: pciaddr="..pciaddress)
   for key,value in pairs(options) do
      io.write(" "..key.."="..tostring(value))
   end
   print()
   options.device = getfenv()
   options.program = port.Port.loopback_test
   options.module = 'intel10g'
   options.secs = 10
   open_for_loopback_test()
   port.selftest(options)
--   register.dump(r)
   register.dump(s, true)
end

function open_for_loopback_test ()
   open() enable_mac_loopback() test.waitfor("linkup", linkup, 20, 250000)
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
