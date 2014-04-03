module(...,package.seeall)

local app      = require("core.app")
local link     = require("core.link")
local basic_apps = require("apps.basic.basic_apps")
local buffer   = require("core.buffer")
local freelist = require("core.freelist")
local packet   = require("core.packet")
local lib      = require("core.lib")
local register = require("lib.hardware.register")
local intel10g = require("apps.intel.intel10g")
local vfio     = require("lib.hardware.vfio")
local config = require("core.config")

Intel82599 = {}

-- Create an Intel82599 App for the device with 'pciaddress'.
function Intel82599:new (pciaddress)
   local a = { dev = intel10g.new(pciaddress) }
   setmetatable(a, {__index = Intel82599 })
   intel10g.open(a.dev)
   intel10g.autonegotiate_sfi(a.dev)
   intel10g.wait_linkup(a.dev)
   return a
end

-- Allocate receive buffers from the given freelist.
function Intel82599:set_rx_buffer_freelist (fl)
   self.rx_buffer_freelist = fl
end

-- Pull in packets from the network and queue them on our 'tx' link.
function Intel82599:pull ()
   local l = self.output.tx
   if l == nil then return end
   self.dev:sync_receive()
   while not link.full(l) and self.dev:can_receive() do
      link.transmit(l, self.dev:receive())
   end
   self:add_receive_buffers()
end

function Intel82599:add_receive_buffers ()
   if self.rx_buffer_freelist == nil then
      -- Generic buffers
      while self.dev:can_add_receive_buffer() do
         self.dev:add_receive_buffer(buffer.allocate())
      end
   else
      -- Buffers from a special freelist
      local fl = self.rx_buffer_freelist
      while self.dev:can_add_receive_buffer() and freelist.nfree(fl) > 0 do
         self.dev:add_receive_buffer(freelist.remove(fl))
      end
   end
end

-- Push packets from our 'rx' link onto the network.
function Intel82599:push ()
   local l = self.input.rx
   if l == nil then return end
   while not link.empty(l) and self.dev:can_transmit() do
      local p = link.receive(l)
      self.dev:transmit(p)
      packet.deref(p)
   end
   self.dev:sync_transmit()
end

-- Report on relevant status and statistics.
function Intel82599:report ()
   print("report on intel device", self.dev.pciaddress)
   --register.dump(self.dev.r)
   register.dump(self.dev.s, true)
   register.dump({
      self.dev.r.TDH, self.dev.r.TDT,
      self.dev.r.RDH, self.dev.r.RDT,
      self.dev.r.AUTOC, self.dev.r.AUTOC2,
      self.dev.r.LINKS, self.dev.r.LINKS2,
   })
end

function selftest ()
   -- Create a pieline:
   --   Source --> Intel82599(loopback) --> Sink
   -- and push packets through it.
   local c = config.new()
   config.app(c, 'source1', basic_apps.Source)
   config.app(c, 'source2', basic_apps.Source)
   config.app(c, 'intel10g_05', Intel82599, '0000:05:00.0')
   config.app(c, 'intel10g_8a', Intel82599, '0000:8a:00.0')
   config.app(c, 'sink', basic_apps.Sink)
   config.link(c, 'source1.out -> intel10g_05.rx')
   config.link(c, 'source2.out -> intel10g_8a.rx')
   config.link(c, 'intel10g_05.tx -> sink.in1')
   config.link(c, 'intel10g_8a.tx -> sink.in2')
   app.configure(c)

   buffer.preallocate(100000)
   app.main({duration = 1})
end

