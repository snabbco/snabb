-- intel10g.lua -- Intel 82599 10GbE ethernet device driver

module(...,package.seeall)

local ffi = require "ffi"
local C = ffi.C
local lib = require("lib")
local bits, bitset = lib.bits, lib.bitset

-- DMA memory.
local num_descriptors = 32 * 1024
local buffer_count = 2 * 1024 * 1024
local rxdesc, rxdesc_phy
local txdesc, txdesc_phy
local buffers, buffers_phy

-- Configuration registers table.
r = {}
-- Statistics registers table.
s = {}

function open ()
   local pcidev = "0000:83:00.1"
   local pci_config_fd = pci.open_config(pcidev)
   pci.set_bus_master(pci_config_fd, true)
   base = ffi.cast("uint32_t*", pci.map_pci_memory(pcidev, 0))
   register.define(config_registers_desc, r, base)
   register.define(statistics_registers_desc, s, base)
   init_device()
end

function init_device ()
   init_dma_memory()
   disable_interrupts()
   global_reset()
   wait_eeprom_autoread()
   wait_dma()
--   setup_link()
   init_statistics()
   init_receive()
   init_transmit()
end

function disable_interrupts () end

function global_reset ()
   local reset = bits{LinkReset=3, DeviceReset=26}
   r.CTRL(reset)
   register.dump(r)
   C.usleep(1000)
   register.dump(r)
   r.CTRL:wait(reset, 0)
end

function wait_eeprom_autoread () r.EEC:wait(bits{AutoreadDone=9}) end
function wait_dma ()             r.RDRXCTL:wait(bits{DMAInitDone=3})  end

function init_statistics ()
   for _,reg in pairs(s) do reg.clear() end
end

function linkup () return bitset(r.LINKS(), 30) end

function enable_mac_loopback ()
   set(r.AUTOC, bits({ForceLinkUp=0, LMS10G=13}))
   set(r.HLREG0, bits({Loop=15}))
end

function init_receive ()
   set_promiscuous_mode() -- accept all, no need to configure MAC address filter
   r.RDRXCTL:set(bits{CRCStrip=0})
   r.HLREG0:clr(bits({RXLNGTHERREN=27, UndocumentedRXCRCSTRP=1}))
   r.RDBAL(rxdesc_phy % 2^32)
   r.RDBAH(rxdesc_phy / 2^32)
   r.RDLEN(num_descriptors * ffi.sizeof("union rx"))
   r.RXDCTL(bits{Enable=25})
   r.RXCTRL:set(bits{RXEN=0})
end

function init_transmit ()
   r.HLREG0:set(bits{TXCRCEN=0})
   r.TDBAL(txdesc_phy % 2^32)
   r.TDBAH(txdesc_phy / 2^32)
   r.TDLEN(num_descriptors * ffi.sizeof("union tx"))
   r.TDH(0)
   r.TDT(0)
   r.DMATXCTL(bits{TE=0})
   r.TXDCTL:wait(bits{Enable=25})
end

tdh, tdt = 0, 0 -- Cached values of TDT and TDH
txfree = 0
txdesc_flags = bits{eop=24,ifcs=25}
function transmit (address, size)
--   print("TX DUMP ("..size.."): " .. bit.tohex(ffi.cast("uint32_t*", address)[1]))
   txdesc[tdt].data.address = address
   txdesc[tdt].data.options = bit.bor(size, txdesc_flags)
   tdt = (tdt + 1) % num_descriptors
end

function can_reclaim_buffer ()
   return txfree ~= tdh
end

function reclaim_buffer ()
   if txfree ~= tdh then
      local address = txdesc[txfree].data.address
      txfree = (txfree + 1) % num_descriptors
      return ffi.cast("uint8_t*", address)
   end
end

function sync_transmit ()
   C.full_memory_barrier()
   tdh = r.TDH()
   r.TDT(tdt)
end

function can_transmit () return (tdt + 1) % num_descriptors ~= txfree end

-- Pointer to buffer address for each receive descriptor.
-- (So that we know even if the address in the receive descriptor is
-- overwritten during write-back.)
rxbuffers = ffi.new("uint8_t*[?]", num_descriptors)

rdh, rdt, rxnext = 0, 0, 0

-- Return the next available packet as two values: buffer, length.
-- If no packet is available then return nil.
function receive ()
   if rdh ~= rxnext then
      local buffer = rxbuffers[rxnext]
      local wb = rxdesc[rxnext].wb
--      local p = ffi.cast("uint32_t*", buffer)
--      io.write("RX DUMP ("..wb.length.."): ")
--      for i = 0, 8 do io.write(bit.tohex(p[i]).." ") end
--      print()
      rxnext = (rxnext + 1) % num_descriptors
      return buffer, wb.length
   end
end

function can_receive ()
   return rdh ~= rxnext
end

function can_add_receive_buffer ()
   return (rdt + 1) % num_descriptors ~= rdh
end

function add_receive_buffer (address, size)
   assert(can_add_receive_buffer())
   local desc = rxdesc[rdt].data
   desc.address, desc.dd = memory.map(address), size
   rxbuffers[rdt] = address
   rdt = (rdt + 1) % num_descriptors
end

function sync_receive ()
   C.full_memory_barrier()
   rdh = r.RDH()
   r.RDT(rdt)
end

function sync () sync_receive() sync_transmit() end

local txdesc_t = ffi.typeof [[
      union { struct { uint64_t address, options; } data;
              struct { uint64_t a, b; }             context; }
]]

local rxdesc_t = ffi.typeof [[
      union { struct { uint64_t address, dd; } data;
	      struct { uint16_t csum, id;
		       uint32_t mrq, status;
		       uint16_t length, vlan; } wb; }
]]

function init_dma_memory ()
   rxdesc, rxdesc_phy = memory.dma_alloc(num_descriptors * ffi.sizeof(rxdesc_t))
   txdesc, txdesc_phy = memory.dma_alloc(num_descriptors * ffi.sizeof(txdesc_t))
   buffers, buffers_phy = memory.dma_alloc(buffer_count * ffi.sizeof("uint8_t"))
   -- Add bounds checking
   rxdesc  = lib.protected(rxdesc_t, rxdesc, 0, num_descriptors)
   txdesc  = lib.protected(txdesc_t, txdesc, 0, num_descriptors)
   buffers = lib.protected("uint8_t", buffers, 0, buffer_count)
end

function set_promiscuous_mode () r.FCTRL(bits({MPE=8, UPE=9, BAM=10})) end

-- Create a hardware register object called NAME with ADDRESS.
-- The ADDRESS is the byte-offset relative to the uint32_t* BASE_POINTER.
function make_register (name, address, desc, base_pointer, mode)
   assert(address % 4 == 0)
   local acc = 0
   local type = ffi.metatype(
      -- Each register has its own anonymous struct type wrapping a pointer.
      ffi.typeof("struct { uint32_t *ptr; }"),
      { __call = function(reg, value)
		    if value == nil then
                       if mode == 'accumulate' then
                          acc = acc + reg.ptr[0]
                          return acc
                       else
                          return reg.ptr[0]
                       end
                    else
                       reg.ptr[0] = value
                       end
		 end,
        __index = function (reg, key)
                     if key == "desc" then
                        return desc
                     elseif key == "name" then
                        return name
		     elseif key == "clear" then
			return function ()
				  acc = reg.ptr[0]
				  acc = 0
			       end
                     end
                  end,
	__tostring = function(reg)
			return name..":"..bit.tohex(reg())
		     end })
   return type(base_pointer + address/4)
end

function wait_linkup ()
   test.waitfor("linkup", linkup, 20, 250000)
end

function selftest ()
   print("intel10g")
   open()
   enable_mac_loopback()
   test.waitfor("linkup", linkup, 20, 250000)
   local finished = lib.timer(1e9)
   buffers[0] = 99
   repeat
      sync()
      while can_add_receive_buffer() do add_receive_buffer(buffers_phy + 40960) end
      while can_transmit() do transmit(buffers_phy, 50) end
      sync()
--      C.usleep(1)
   until finished()
   assert(buffers[40960]==99)
   C.usleep(1000)
   print "stats"
   register.dump(s)
end

--- ## Configuration register description.

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
STATUS    0x00008 -            RO Device Status
TDBAL     0x06000 +0x40*0..127 RW Transmit Descriptor Base Address Low
TDBAH     0x06004 +0x40*0..127 RW Transmit Descriptor Base Address High
TDH       0x06010 +0x40*0..127 RO Transmit Descriptor Head
TDT       0x06018 +0x40*0..127 RW Transmit Descriptor Tail
TDLEN     0x06008 +0x40*0..127 RW Transmit Descriptor Length
TXDCTL    0x06028 +0x40*0..127 RW Transmit Descriptor Control
]]

--- ## Statistics register description.

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
PRC64         0x0405C -           RW Packets Received [64 Bytes] Count
PRC127        0x04060 -           RW Packets Received [65-127 Bytes] Count
PRC255        0x04064 -           RW Packets Received [128-255 Bytes] Count
PRC511        0x04068 -           RW Packets Received [256-511 Bytes] Count
PRC1023       0x0406C -           RW Packets Received [512-1023 Bytes] Count
PRC1522       0x04070 -           RW Packets Received [1024 to Max Bytes] Count
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
GPTC          0x04080 -           RO Good Packets Transmitted Count
GOTCL         0x04090 -           RC Good Octets Transmitted Count Low
GOTCH         0x04094 -           RC Good Octets Transmitted Count High
TXDGPC        0x087A0 -           RC DMA Good Tx Packet Counter
TXDGBCL       0x087A4 -           RC DMA Good Tx Byte Counter Low
TXDGBCH       0x087A8 -           RC DMA Good Tx Byte Counter High
RUC           0x040A4 -           RC Receive Undersize Count
RFC           0x040A8 -           RC Receive Fragment Count
ROC           0x040AC -           RC Receive Oversize Count
RJC           0x040B0 -           RC Receive Jabber Count
MNGPRC        0x040B4 -           RO Management Packets Received Count
MNGPDC        0x040B8 -           RO Management Packets Dropped Count
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
RQSMR         0x02300 +0x4*0..31  RW Receive Queue Statistic Mapping Registers
RXDSTATCTRL   0x02F40 -           RW Rx DMA Statistic Counter Control
TQSM          0x08600 +0x4*0..31  RW Transmit Queue Statistic Mapping Registers
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
