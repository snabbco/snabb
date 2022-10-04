-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local lib = require("core.lib")
local app = require("core.app")
local link = require("core.link")
local intel_mp = require("apps.intel_mp.intel_mp")
local memory = require("core.memory")
local register = require("lib.hardware.register")
local receive, empty = link.receive, link.empty

local can_transmit, transmit
local num_descriptors = 4096

LoadGen = {}

function LoadGen:new (pciaddress)
   local function new_driver(conf)
      conf = lib.parse(conf, intel_mp.Intel82599.config)
      return intel_mp.Intel82599:new(conf)
   end
   local o = {
      pciaddress = pciaddress,
      dev = new_driver({
         pciaddr = pciaddress,
         ring_buffer_size = num_descriptors,
         wait_for_link = true,
      })
   }
--   o.dev:open()
--   o.dev:wait_linkup()
   disable_tx_descriptor_writeback(o.dev)
   zero_descriptors(o.dev)
   return setmetatable(o, {__index = LoadGen})
end

function disable_tx_descriptor_writeback (dev)
   -- Disable writeback of transmit descriptors.
   -- That way our transmit descriptors stay fresh and reusable.
   -- Tell hardware write them to this other memory instead.
   local bytes = num_descriptors * ffi.sizeof(intel_mp.rxdesc_t)
   local ptr, phy = memory.dma_alloc(bytes)
   dev.r.TDWBAL(phy % 2^32)
   dev.r.TDWBAH(phy / 2^32)
end

function zero_descriptors (dev)
   -- Clear unused descriptors
   local b = memory.dma_alloc(4096)
   for i = 0, num_descriptors-1 do
      -- Make each descriptors point to valid DMA memory but be 0 bytes long.
      dev.txdesc[i].address = memory.virtual_to_physical(b)
      dev.txdesc[i].flags = bit.lshift(1, 24) -- End of Packet flag
   end
end

function LoadGen:push ()
   local dev = self.dev
   if self.input.input then
      while not link.empty(self.input.input) and dev:can_transmit() do
         do local p = receive(self.input.input)
            dev:transmit(p)
         end
      end
   end
end

function LoadGen:pull ()
   -- Set TDT behind TDH to make all descriptors available for TX.
   local dev = self.dev
   local tdh = dev.r.TDH()
   if dev.tdt == 0 then return end
   C.full_memory_barrier()
   if tdh == 0 then
      dev.r.TDT(num_descriptors)
   else
      dev.r.TDT(tdh - 1)
   end
end

function LoadGen:report ()
   print(self.pciaddress,
         "TXDGPC (TX packets)", lib.comma_value(tonumber(self.dev.r.TXDGPC())),
         "GOTCL (TX bytes)", lib.comma_value(tonumber(self.dev.r.GOTCL())))
   print(self.pciaddress,
         "RXDGPC (RX packets)", lib.comma_value(tonumber(self.dev.r.RXDGPC())),
         "GORCL (RX bytes)", lib.comma_value(tonumber(self.dev.r.GORCL())))
   self.dev.r.TXDGPC:reset()
   self.dev.r.GOTCL:reset()
   self.dev.r.RXDGPC:reset()
   self.dev.r.GORCL:reset()
end
