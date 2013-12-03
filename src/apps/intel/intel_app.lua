module(...,package.seeall)

local app      = require("core.app")
local basic_apps = require("apps.basic.basic_apps")
local buffer   = require("core.buffer")
local packet   = require("core.packet")
local lib      = require("core.lib")
local register = require("lib.hardware.register")
local intel10g = require("apps.intel.intel10g")

Intel82599 = {}

-- Create an Intel82599 App for the device with 'pciaddress'.
function Intel82599:new (pciaddress)
   local a = app.new(Intel82599)
   a.dev = intel10g.new(pciaddress)
   setmetatable(a, {__index = Intel82599 })
   intel10g.open_for_loopback_test(a.dev)
   return a
end

-- Pull in packets from the network and queue them on our 'tx' link.
function Intel82599:pull ()
   local l = self.output.tx
   if l == nil then return end
   self.dev:sync_receive()
   while not app.full(l) and self.dev:can_receive() do
      app.transmit(l, self.dev:receive())
   end
   while self.dev:can_add_receive_buffer() do
      self.dev:add_receive_buffer(buffer.allocate())
   end
end

-- Push packets from our 'rx' link onto the network.
function Intel82599:push ()
   local l = self.input.rx
   if l == nil then return end
   while not app.empty(l) and self.dev:can_transmit() do
      local p = app.receive(l)
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
   -- Create a pieline:
   --   Source --> Intel82599(loopback) --> Sink
   -- and push packets through it.
   app.apps.intel10g = Intel82599:new("0000:01:00.0")
   app.apps.source = app.new(basic_apps.Source)
   app.apps.sink   = app.new(basic_apps.Sink)
   app.connect("source", "out", "intel10g", "rx")
   app.connect("intel10g", "tx", "sink", "in")
   app.relink()
   buffer.preallocate(100000)
   local deadline = lib.timer(1e9)
   repeat app.breathe() until deadline()
   app.report()
end

