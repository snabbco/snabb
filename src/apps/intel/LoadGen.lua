module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local lib = require("core.lib")
local app = require("core.app")
local buffer = require("core.buffer")
local intel10g = require("apps.intel.intel10g")
local memory = require("core.memory")
local register = require("lib.hardware.register")

function new (self, pciaddress)
   local o = { pciaddress = pciaddress,
               dev = intel10g.new(pciaddress) }
   intel10g.open_for_loopback_test(o.dev)
   disable_tx_descriptor_writeback(o.dev)
   zero_descriptors(o.dev)
   return setmetatable(o, {__index = getfenv()})
end

function disable_tx_descriptor_writeback (dev)
   -- Disable writeback of transmit descriptors.
   -- That way our transmit descriptors stay fresh and reusable.
   -- Tell hardware write them to this other memory instead.
   local bytes = dev.num_descriptors * ffi.sizeof(intel10g.rxdesc_t)
   local ptr, phy = memory.dma_alloc(bytes)
   dev.r.TDWBAL(phy % 2^32)
   dev.r.TDWBAH(phy / 2^32)
end

function zero_descriptors (dev)
   print("zd")
   -- Clear unused descriptors
   local b = buffer.allocate()
   for i = 0, dev.num_descriptors-1 do
      -- Make each descriptors point to valid DMA memory but be 0 bytes long.
      dev.txdesc[i].data.address = b.physical
      dev.txdesc[i].data.options = bit.lshift(1, 24) -- End of Packet flag
   end
   print("/zd")
end

function push (self)
   assert(self.input.input)
   while not app.empty(self.input.input) and self.dev:can_transmit() do
      local p = app.receive(self.input.input)
      self.dev:transmit(p)
   end
end

function pull (self)
   -- Set TDT behind TDH to make all descriptors available for TX.
   local dev = self.dev
   local tdh = dev.r.TDH()
--   print("tdh", tdh, "tdt", dev.r.TDT(), "dev.tdt", dev.tdt)
   if dev.tdt == 0 then return end
   C.full_memory_barrier()
   if tdh == 0 then
      dev.r.TDT(dev.num_descriptors)
   else
      dev.r.TDT(tdh - 1)
   end
end

function report (self)
--   print(self.pciaddress, self.dev.s.TXDGPC)
   print(self.pciaddress,
         "TXDGPC (TX packets)", lib.comma_value(tonumber(self.dev.s.TXDGPC())),
         "GOTCL (TX octets)", lib.comma_value(tonumber(self.dev.s.GOTCL())))
   self.dev.s.TXDGPC:reset()
   self.dev.s.GOTCL:reset()
end

