module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
Npackets = {
   config = {
      npackets = { default = 1000000 }
   }
}

function Npackets:new (conf)
   return setmetatable({n = conf.npackets}, { __index = Npackets})
end

function Npackets:push ()
   while not link.empty(self.input.input) and
      self.n > 0 do
      link.transmit(self.output.output, link.receive(self.input.input))
      self.n = self.n - 1
   end
end

function selftest()
   local synth = require("apps.test.synth")
   local basic_apps = require("apps.basic.basic_apps")
   local counter = require("core.counter")

   local c = config.new()
   config.app(c, "src", synth.Synth)
   config.app(c, "n", Npackets, { npackets = 100 })
   config.app(c, "sink", basic_apps.Sink)
   config.link(c, "src.output -> n.input")
   config.link(c, "n.output -> sink.input")
   engine.configure(c)
   assert(engine.app_table.n.n == 100)
   engine.main({duration=1})
   assert(engine.app_table.n.n == 0)
   assert(counter.read(engine.link_table['src.output -> n.input'].stats.txpackets) > 100)
   local cnt = counter.read(engine.link_table['n.output -> sink.input'].stats.rxpackets)
   assert(100 == cnt)
end
