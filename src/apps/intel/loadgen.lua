module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local lib = require("core.lib")
local app = require("core.app")
local link = require("core.link")
local intel10g = require("apps.intel.intel10g")
local memory = require("core.memory")
local register = require("lib.hardware.register")
local receive, empty = link.receive, link.empty
local can_transmit, transmit

LoadGen = {}

function LoadGen:new (conf)
   local o = { pciaddr= conf.pciaddr,
               dev = intel10g.new_sf({pciaddr=conf.pciaddr}),
               report_rx = conf.report_rx, }
   o.dev:open()
   o.dev:wait_linkup()
   disable_tx_descriptor_writeback(o.dev)
   zero_descriptors(o.dev)
   can_transmit, transmit = o.dev.can_transmit, o.dev.transmit
   return setmetatable(o, {__index = LoadGen})
end

function disable_tx_descriptor_writeback (dev)
   -- Disable writeback of transmit descriptors.
   -- That way our transmit descriptors stay fresh and reusable.
   -- Tell hardware write them to this other memory instead.
   local bytes = intel10g.num_descriptors * ffi.sizeof(intel10g.rxdesc_t)
   local ptr, phy = memory.dma_alloc(bytes)
   dev.r.TDWBAL(phy % 2^32)
   dev.r.TDWBAH(phy / 2^32)
end

function zero_descriptors (dev)
   -- Clear unused descriptors
   local b = memory.dma_alloc(4096)
   for i = 0, intel10g.num_descriptors-1 do
      -- Make each descriptors point to valid DMA memory but be 0 bytes long.
      dev.txdesc[i].address = memory.virtual_to_physical(b)
      dev.txdesc[i].options = bit.lshift(1, 24) -- End of Packet flag
   end
end

function LoadGen:push ()
   if self.input.input then
      while not link.empty(self.input.input) and can_transmit(self.dev) do
         do local p = receive(self.input.input)
            transmit(self.dev, p)
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
      dev.r.TDT(intel10g.num_descriptors)
   else
      dev.r.TDT(tdh - 1)
   end
end

function LoadGen:report ()
   local s = self.dev.s
   local function format(reg)
      return lib.comma_value(tonumber(reg()))
   end

   print(self.pciaddr,
         "TXDGPC (TX packets)", format(s.TXDGPC),
         "GOTCL (TX octets)",   format(s.GOTCL))
   s.TXDGPC:reset()
   s.GOTCL:reset()
   if self.report_rx then
      print(self.pciaddr,
            -- TODO: RXDGPC reported 0 packets received, but non-filtered got packets.
            "RXNFGPC (RX packets)", format(s.RXNFGPC),
            "GORCL (RX octets)",    format(s.GORCL))
      s.RXNFGPC:reset()
      s.GORCL:reset()
   end
end
