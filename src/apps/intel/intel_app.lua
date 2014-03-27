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
   intel10g.open_for_loopback_test(a.dev)
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
end

function selftest ()
   print("selftest: intel_app")
   if not vfio.is_vfio_available() then
      print("VFIO not available\nTest skipped")
      os.exit(app.TEST_SKIPPED_CODE)
   end
   -- Create a pieline:
   --   Source --> Intel82599(loopback) --> Sink
   -- and push packets through it.
   vfio.bind_device_to_vfio("0000:01:00.0")
   local c = config.new()
   config.app(c, "intel10g", Intel82599, "0000:01:00.0")
   config.app(c, "source", basic_apps.Source)
   config.app(c, "sink", basic_apps.Sink)
   config.link(c, "source.out -> intel10g.rx")
   config.link(c, "intel10g.tx -> sink.in")
   app.configure(c)
--[[
   app.apps.intel10g = Intel82599:new("0000:01:00.0")
   app.apps.source = app.new(basic_apps.Source)
   app.apps.sink   = app.new(basic_apps.Sink)
   app.connect("source", "out", "intel10g", "rx")
   app.connect("intel10g", "tx", "sink", "in")
   app.relink()
--]]
   buffer.preallocate(100000)
   app.main({duration = 1})
--   repeat app.breathe() until deadline()
--   app.report()
end

