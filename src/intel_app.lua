module(...,package.seeall)

local app = require("app")
local intel10g = require("intel10g")

Intel82599 = {}

function Intel82599:new (pciaddress)
   local a = app.new(Intel82599)
   a.dev = intel10g.new(pciaddress)
   setmetatable(a, {__index = Intel82599 })
   intel10g.open_for_loopback_test(a.dev)
   return a
end

function Intel82599:pull ()
   local l = self.output.tx
   if l == nil then return end
   self.dev:sync_receive()
   while not app.full(l) and self.dev:can_receive() do
      app.transfer(l, self.dev:receive())
   end
   while self.dev:can_add_receive_buffer() do
      self.dev:add_receive_buffer(buffer.allocate())
   end
end

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

function Intel82599:report ()
   print("report on intel device")
   register.dump(self.dev.r)
   register.dump(self.dev.s, true)
end

function selftest ()
   app.apps.intel10g = Intel82599:new("0000:01:00.0")
   app.apps.source = app.new(app.Source)
   app.apps.sink   = app.new(app.Sink)
   app.connect("source", "out", "intel10g", "rx")
   app.connect("intel10g", "tx", "sink", "in")
   app.relink()
   local deadline = lib.timer(1e9)
   repeat app.breathe() until deadline()
   app.report()
end

