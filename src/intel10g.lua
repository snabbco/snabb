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

-- Register table to be populated during init.
r = {}

-- Register set description as an easy-to-parse string.
--
--   Register   ::= Name Offset Indexing Permission Description
--
--   Name       ::= <identifier>
--   Offset     ::= <number>
--   Indexing   ::= "-"
--              ::= OffsetStep "*" Min ".." Max
--   OffsetStep ::= "+" <number>
--   Min        ::= <number>
--   Max        ::= <number>
--   Permission ::= "(RO)" | "(RW)"
--   
registerspec = [[
      AUTOC     0x042A0 -            (RW) Auto Negotiation Control
      CTRL      0x00000 -            (RW) Device Control
      DMATXCTL  0x04A80 -            (RW) DMA Tx Control
      EEC       0x10010 -            (RW) EEPROM/Flash Control
      FCTRL     0x05080 -            (RW) Filter Control
      HLREG0    0x04240 -            (RW) MAC Core Control 0
      LINKS     0x042A4 -            (RO) Link Status Register
      RDBAL     0x01000 +0x40*0..63  (RW) Receive Descriptor Base Address Low
      RDBAH     0x01004 +0x40*0..63  (RW) Receive Descriptor Base Address High
      RDLEN     0x01008 +0x40*0..63  (RW) Receive Descriptor Length
      RDH       0x01010 +0x40*0..63  (RO) Receive Descriptor Head
      RDT       0x01018 +0x40*0..63  (RW) Receive Descriptor Tail
      RXDCTL    0x01028 +0x40*0..63  (RW) Receive Descriptor Control
      RDRXCTL   0x02F00 -            (RW) Receive DMA Control
      RTTDCS    0x04900 -            (RW) DCB Transmit Descriptor Plane Control
      RXCTRL    0x03000 -            (RW) Receive Control
      STATUS    0x00008 -            (RO) Device Status
      TDBAL     0x06000 +0x40*0..127 (RW) Transmit Descriptor Base Address Low
      TDBAH     0x06004 +0x40*0..127 (RW) Transmit Descriptor Base Address High
      TDH       0x06010 +0x40*0..127 (RO) Transmit Descriptor Head
      TDT       0x06018 +0x40*0..127 (RW) Transmit Descriptor Tail
      TDLEN     0x06008 +0x40*0..127 (RW) Transmit Descriptor Length
      TXDCTL    0x06028 +0x40*0..127 (RW) Transmit Descriptor Control
]]

function init_device ()
   init_dma_memory()
   disable_interrupts()
   global_reset()
   wait_eeprom_autoread()
   wait_dma()
   setup_link()
   init_statistics()
   init_receive()
   init_transmit()
end

function disable_interrupts () end

function global_reset()
   local reset = bits{LinkReset=3, DeviceReset=26}
   r.CTRL(reset)
   registerdump()
   C.usleep(1000)
   registerdump()
   wait(r.CTRL, reset, 0)
end

function wait_eeprom_autoread () wait(r.EEC,     bits{AutoreadDone=9}) end
function wait_dma ()             wait(r.RDRXCTL, bits{DMAInitDone=3})  end

function wait (register, bitmask, value)
   waitfor(function () return bit.band(register(), bitmask) == (value or bitmask) end)
end

function waitfor (condition)
   while not condition() do print "Waiting" C.usleep(100) end
end

function software_reset ()
   
end

function link_reset ()
   -- XXX Assume EEPROM selects correct PHY and enables autonegotiation.
end

function linkup () return bitset(r.LINKS(), 30) end
function enable_mac_loopback ()
   set(r.AUTOC, bits({ForceLinkUp=0}))
   set(r.HLREG0, bits({Loop=15}))
end

-- Set BITMASK in register R.
function set (r, bitmask) r(bit.bor(bitmask, r())) end
function clr (r, bitmask) r(bit.band(bit.bnot(bitmask), r())) end

function setup_link() end
function init_statistics() end

function init_receive ()
   set_promiscuous_mode() -- accept all, no need to configure MAC address filter
   r.RDBAL(rxdesc_phy % 2^32)
   r.RDBAH(rxdesc_phy / 2^32)
   r.RDLEN(num_descriptors * ffi.sizeof("union rx"))
   r.RXDCTL(bits{Enable=25})
   set(r.RXCTRL, bits{RXEN=0})
end

function init_transmit ()
   set(r.RTTDCS, bits{ARBDIS=6})
   clr(r.RTTDCS, bits{ARBDIS=6})
   r.TDBAL(txdesc_phy % 2^32)
   r.TDBAH(txdesc_phy / 2^32)
   r.TDLEN(num_descriptors * ffi.sizeof("union tx"))
   r.DMATXCTL(bits{TE=0})
   r.TDT(0)
   set(r.TXDCTL, bits{Enable=25})
   wait(r.TXDCTL, bits{Enable=25})
end

local txdesc_flags = bits({dtype=20, eop=24, ifcs=25, dext=29})
function test_transmit ()
   txdesc[0].data.address = buffers_phy
   txdesc[0].data.options = bit.bor(1024, txdesc_flags)
   r.TDT(1)
end

function init_dma_memory ()
   rxdesc, rxdesc_phy = memory.dma_alloc(num_descriptors * ffi.sizeof("union rx"))
   txdesc, txdesc_phy = memory.dma_alloc(num_descriptors * ffi.sizeof("union tx"))
   buffers, buffers_phy = memory.dma_alloc(buffer_count * ffi.sizeof("uint8_t"))
   -- Add bounds checking
   rxdesc  = lib.protected("union rx", rxdesc, 0, num_descriptors)
   txdesc  = lib.protected("union tx", txdesc, 0, num_descriptors)
   buffers = lib.protected("uint8_t", buffers, 0, buffer_count)
end

function set_promiscuous_mode () r.FCTRL(bits({MPE=8, UPE=9, BAM=10})) end

-- Create a hardware register object called NAME with ADDRESS.
-- The ADDRESS is the byte-offset relative to the uint32_t* BASE_POINTER.
function defregister (name, address, base_pointer)
   assert(address % 4 == 0)
   local type = ffi.metatype(
      -- Each register has its own anonymous struct type wrapping a pointer.
      ffi.typeof("struct { uint32_t *ptr; }"),
      { __call = function(reg, value)
		    if value == nil then return reg.ptr[0]
		    else                 reg.ptr[0] = value end
		 end,
	__tostring = function(reg)
			return name..":"..bit.tohex(reg())
		     end })
   r[name] = type(base_pointer + address/4)
   return r[name]
end


function selftest ()
   print("intel10g")
   local pcidev = "0000:83:00.1"
   local pci_config_fd = pci.open_config(pcidev)
   pci.set_bus_master(pci_config_fd, true)
   base = ffi.cast("uint32_t*", pci.map_pci_memory(pcidev, 0))
   defregisters(registerspec, base)
   init_device()
   enable_mac_loopback()
   test.waitfor("linkup", linkup, 20, 250000)
   C.usleep(100000)
   test_transmit()
   C.usleep(100000)
   registerdump()
end

function defregisters (spec, base)
   local pattern = " *(%S+) +(%S+) +(%S+) +(%S+) (.-)\n"
   for name,offset,index,perm,desc in spec:gmatch(pattern) do
      defregister(name, tonumber(offset), base)
   end
end

function registerdump ()
   print "Register dump:"
   local strings = {}
   for _,reg in pairs(r) do table.insert(strings, tostring(reg)) end
   table.sort(strings)
   for _,reg in pairs(strings) do io.write(("%20s\n"):format(reg)) end
end

