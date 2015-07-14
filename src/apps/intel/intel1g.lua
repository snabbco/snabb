-- intel1g: Device driver app for Intel 1G network cards

module(..., package.seeall)

local ffi = require("ffi")
local C   = ffi.C
local pci = require("lib.hardware.pci")
local band, bor, lshift = bit.band, bit.bor, bit.lshift
local bits = require("core.lib").bits
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
   -- Setup device access
   pci.unbind_device_from_linux(pciaddress)
   local regs, mmiofd = pci.map_pci_memory(pciaddress, 0)
   local r = {}
   -- Common utilities
   -- bitvalue(0x42)      => 0x42
   -- bitvalue({a=7,b=2}) => 0x42
   local function bitvalue (value)
      return (type(value) == 'number') and value or bits(value)
   end
   local function poke32 (offset, value)
      value = bitvalue(value)
      lib.poke32(regs, offset, value)
   end
   local function peek32 (offset)
      returnlib.peek32(regs, offset)
   end
   local function set32 (offset, value)
      value = bitvalue(value)
      poke32(offset, bor(peek32(offset), value))
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

      local txdesc_t = ffi.typeof("struct { uint64_t address, flags; }")
      local txdesc_ring_t = ffi.typeof("$[$]", txdesc_t, ndesc)
      local txdesc = ffi.cast(ffi.typeof("$&", txdesc_ring_t),
                              memory.dma_alloc(ffi.sizeof(txdesc_ring_t)))
      
      -- Initialize transmit state
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
      local function sync ()
         local cursor = tdh
         tdh = regs[r.TDH]
         while cursor ~= tdh do
            packet.free(packets[cursor])
            packets[cursor] = nil
            cursor = ringnext(cursor)
         end
         regs[r.TDT] = tdt
      end

      -- Define push() method for app instance.
      function self:push ()
         local l = self.input[1]
         assert(l, "intel1g: no input link")
         while not link.empty(l) and can_transmit() do
            transmit(link.receive(l))
         end
         sync()
      end
   end
   -- Receive support
   if rxq then
      r.RDBAL  = 0xc000
      r.RDBAH  = 0xc004
      r.RDLEN  = 0xc008
      r.RDH    = 0xc010
      r.RDT    = 0xc018
      r.RXDCTL = 0xc028

      local rxdesc_t = ffi.typeof("struct { uint64_t address, flags; }")
      local rxdesc_ring_t = ffi.typeof("$[$]", rxdesc_t, ndesc)
      
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
         desc.flags = ...
         rxpackets[rdt] = p
         rdt = ringnext(rdt)
      end

   end
   
end

