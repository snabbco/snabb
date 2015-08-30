-- intel1g: Device driver app for Intel 1G network cards
-- 
-- This is a device driver for the Intel I350 family of 1G network cards.
-- 
-- The driver aims to be fairly flexible about how it can be used. The
-- user can specify whether to initialize the NIC, which hardware TX
-- and RX queue should be used (or none), and the size of the TX/RX
-- descriptor rings. This should accomodate users who want to
-- initialize the NIC in an exotic way (e.g. with Linux igbe/ethtool),
-- or to dispatch packets across input queues in a specific way
-- (e.g. RSS and FlowDirector), or want to create many transmit-only
-- apps with private TX queues as a fast-path to get packets onto the
-- wire. The driver does not directly support these use cases but it
-- avoids abstractions that would potentially come into conflict with
-- them.
-- 
-- This flexibility does require more work from the user. For contrast
-- consider the intel10g driver: its VMDq mode automatically selects
-- available transmit/receive queues from a pool and initializes the
-- NIC to dispatch traffic to them based on MAC/VLAN. This is very
-- convenient but it also assumes that the NIC will only be used by
-- one driver in one process. This driver on the other hand does not
-- perform automatic queue assignment and so that must be done
-- separately (for example when constructing the app network with a
-- suitable configuration). The notion is that people constructing app
-- networks will have creative ideas that we are not able to
-- anticipate and so it is important to avoid assumptions about how
-- the driver will be used.
-- 
-- Data sheet (reference documentation):
-- http://www.intel.com/content/dam/www/public/us/en/documents/datasheets/ethernet-controller-i350-datasheet.pdf

module(..., package.seeall)

local ffi = require("ffi")
local C   = ffi.C
local pci = require("lib.hardware.pci")
local band, bor, bnot, lshift = bit.band, bit.bor, bit.bnot, bit.lshift
local lib  = require("core.lib")
local bits = lib.bits
local compiler_barrier = lib.compiler_barrier
local tophysical = core.memory.virtual_to_physical

-- app class
intel1g = {}

function intel1g:new (conf)
   local self = {}
   local pciaddress = conf.pciaddr
   local attach = conf.attach
   local txq = conf.txqueue or 0
   local rxq = conf.rxqueue or 0
   local ndesc = conf.ndescriptors or 512
   local rxburst = conf.rxburst or 128
   -- Setup device access
   pci.unbind_device_from_linux(pciaddress)
   local regs, mmiofd = pci.map_pci_memory(pciaddress, 0)
   local r = {}
   -- Common utilities
   -- bitvalue(0x42)      => 0x42
   -- bitvalue({a=7,b=2}) => 0x42
   local function bitvalue (value)
      return (type(value) == 'table') and bits(value) or tonumber(value)
   end
   local function poke32 (offset, value)
      value = bitvalue(value)
      compiler_barrier()
      regs[offset/4] = value
   end
   local function peek32 (offset)
      compiler_barrier()
      return regs[offset/4]
   end
   local function set32 (offset, value)
      value = bitvalue(value)
      poke32(offset, bor(peek32(offset), value))
   end
   local function clear32 (offset, value)
      value = bitvalue(value)
      poke32(offset, band(peek32(offset), bnot(value)))
   end
   local function wait32 (offset, mask, value)
      mask = bitvalue(mask)
      value = bitvalue(value)
      repeat until band(peek32(offset), mask) == (value or mask)
   end
   -- Return the next index into a ring buffer.
   -- (ndesc is a power of 2 and the ring wraps after ndesc-1.)
   local function ringnext (index)
      return band(index+1, ndesc-1)
   end

   -- Shutdown functions.
   local stop_nic, stop_transmit, stop_receive

   -- Device setup and initialization
   r.CTRL = 0x0000
   r.EIMC = 0x1528
   r.RCTL = 0x0100
   r.TCTL = 0x0400
   r.TCTL_EXT = 0x0404
   if not attach then
      -- Initialize device
      poke32(r.EIMC, 0xffffffff)      -- disable interrupts
      poke32(r.CTRL, {reset = 26})    -- reset
      wait32(r.CTRL, {reset = 26}, 0) -- wait reset complete
      poke32(r.EIMC, 0xffffffff)      -- re-disable interrupts
      set32 (r.CTRL, {setlinkup = 6})
      if conf.loopback then
         set32(r.RCTL, {loopbackmode0 = 6})
      end
      pci.set_bus_master(pciaddress, true)

      -- Define shutdown function for the NIC itself
      stop_nic = function ()
         -- XXX Are these the right actions?
         clear32(r.CTRL, {setlinkup = 6})        -- take the link down
         pci.set_bus_master(pciaddress, false) -- disable DMA
      end
   end

   -- Transmit support
   if txq then
      -- Define registers for the transmit queue that we are using
      r.TDBAL  = 0xe000 + txq*0x40
      r.TDBAH  = 0xe004 + txq*0x40
      r.TDLEN  = 0xe008 + txq*0x40
      r.TXDCTL = 0xe028 + txq*0x40
      r.TDH    = 0xe010 + txq*0x40
      r.TDT    = 0xe018 + txq*0x40

      -- Setup transmit descriptor memory
      local txdesc_t = ffi.typeof("struct { uint64_t address, flags; }")
      local txdesc_ring_t = ffi.typeof("$[$]", txdesc_t, ndesc)
      local txdesc = ffi.cast(ffi.typeof("$&", txdesc_ring_t),
                              memory.dma_alloc(ffi.sizeof(txdesc_ring_t)))

      -- Transmit state variables
      local txpackets = {}      -- packets currently queued
      local tdh, tdt = 0, 0     -- Cache of DMA head/tail indexes
      local txdesc_flags = bits({ifcs=25, dext=29, dtyp0=20, dtyp1=21, eop=24})

      -- Return true if we can enqueue another packet for transmission.
      local function can_transmit ()
         return ringnext(tdt) ~= tdh
      end

      -- Queue a packet for transmission.
      -- Precondition: can_transmit() => true
      local function transmit (p)
         txdesc[tdt].address = tophysical(p.data)
         txdesc[tdt].flags = bor(p.length, txdesc_flags, lshift(p.length+0ULL, 46))
         txpackets[tdt] = packet
         tdt = ringnext(tdt)
      end

      -- Synchronize DMA ring state with hardware.
      -- Free packets that have  been transmitted.
      local function sync_transmit ()
         local cursor = tdh
         tdh = peek32(r.TDH)
         while cursor ~= tdh do
            packet.free(packets[cursor])
            packets[cursor] = nil
            cursor = ringnext(cursor)
         end
         poke32(r.TDT, tdt)
      end

      -- Define push() method for app instance.
      function self:push ()
         local l = self.input[1]
         assert(l, "intel1g: no input link")
         while not link.empty(l) and can_transmit() do
            transmit(link.receive(l))
         end
         sync_transmit()
      end

      -- Define shutdown function for transmit
      stop_transmit = function ()
         poke32(r.TXDCTL, 0)
         wait32(r.TXDCTL, {enable = 25}, 0)
         for i = 0, ndesc-1 do
            if txpackets[i] then
               packet.free(txpackets[i])
               txpackets[i] = nil
            end
         end
      end
   end
   -- Receive support
   if rxq then
      r.RDBAL  = 0xc000 + rxq*0x40
      r.RDBAH  = 0xc004 + rxq*0x40
      r.RDLEN  = 0xc008 + rxq*0x40
      r.RDH    = 0xc010 + rxq*0x40
      r.RDT    = 0xc018 + rxq*0x40
      r.RXDCTL = 0xc028 + rxq*0x40

      local rxdesc_t = ffi.typeof([[
        struct { 
          uint64_t address;
          uint16_t length, cksum;
          uint8_t status, errors;
          uint16_t vlan;
        } __attribute__((packed))]])
      local rxdesc_ring_t = ffi.typeof("$[$]", rxdesc_t, ndesc)
      local rxdesc = ffi.cast(ffi.typeof("$&", rxdesc_ring_t),
                              memory.dma_alloc(ffi.sizeof(rxdesc_ring_t)))
      
      -- Receive state
      local rxpackets = {}
      local rdh, rdt, rxnext = 0, 0, 0

      -- Return true if we can enqueue another packet buffer.
      local function can_add_receive_buffer ()
         return ringnext(rdt) ~= rxnext
      end

      -- Enqueue a packet for DMA receive.
      local function add_receive_buffer (p)
         local desc = rxdesc[rdt]
         desc.address = tophysical(p.data)
         desc.flags = 0
         rxpackets[rdt] = p
         rdt = ringnext(rdt)
      end

      -- Return true if there is a DMA-completed packet ready to be received.
      local function can_receive ()
         return rxnext ~= rdh and band(rxdesc[rxnext].status, 0x1) ~= 0
      end

      -- Receive a packet.
      -- Precondition: can_receive() => true
      local function receive ()
         local desc = rxdesc[rxnext]
         local p = rxpackets[rxnext]
         p.length = desc.length
         rxpackets[rxnext] = nil
         rxnext = ringnext(rxnext)
         return p
      end

      -- Synchronize receive registers with hardware.
      local function sync_receive ()
         rdh = band(peek32(r.RDH), ndesc-1)
         poke32(r.RDT, rdt)
      end
      
      -- Define pull() method for app instance.
      function self:pull ()
         local l = self.output[1]
         assert(l, "intel1g: no output link")
         local limit = rxburst
         while limit > 0 and can_receive() do
            link.transmit(l, receive())
            limit = limit - 1
         end
         sync_receive()
      end

      -- Define shutdown function for receive
      stop_receive = function ()
         poke32(r.RXDCTL, 0)
         wait32(r.RXDCTL, {enable = 25}, 0)
         for i = 0, ndesc-1 do
            if rxpackets[i] then
               packet.free(rxpackets[i])
               rxpackets[i] = nil
            end
         end
         -- XXX return dma memory
      end
   end

   -- Stop all functions that are running.
   function self:stop ()
      if stop_receive  then stop_receive()  end
      if stop_transmit then stop_transmit() end
      if stop_nic      then stop_nic()      end
   end

   return self
end

function selftest ()
   print("selftest: intel1g")
   local pciaddr = os.getenv("SNABB_SELFTEST_INTEL1G_0")
   if not pciaddr then
      print("SNABB_SELFTEST_INTEL1G_0 not set")
      os.exit(engine.test_skipped_code)
   end
   
   local c = config.new()
   local basic = require("apps.basic.basic_apps")
   print(basic.Source, basic.Sink, intel1g)
   config.app(c, "source", basic.Source)
   config.app(c, "sink", basic.Sink)
   config.app(c, "nic", intel1g, {pciaddr=pciaddr})
   config.link(c, "source.tx->nic.rx")
   config.link(c, "nic.tx->sink.rx")
   engine.configure(c)
   engine.main({duration = 1.0, report = {showapps = true, showlinks = true}})
   print("selftest: ok")
end

