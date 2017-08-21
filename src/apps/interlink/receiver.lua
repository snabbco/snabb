-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local shm = require("core.shm")
local interlink = require("lib.interlink")

local Receiver = {
   name = "apps.interlink.Receiver",
   config = {
      name = {required=true},
      create = {default=false}
   }
}

function Receiver:new (conf)
   local self = {}
   if conf.create then
      self.interlink = interlink.create(conf.name)
      self.destroy = conf.name
   else
      self.interlink = interlink.open(conf.name)
   end
   return setmetatable(self, {__index=Receiver})
end

function Receiver:pull ()
   local o, r, n = self.output.output, self.interlink, 0
   if not o then return end -- don’t forward packets until connected
   while not interlink.empty(r) and n < engine.pull_npackets do
      link.transmit(o, interlink.extract(r))
      n = n + 1
   end
   interlink.pull(r)
end

function Receiver:stop ()
   if self.destroy then
      interlink.free(self.interlink)
      shm.unlink(self.destroy)
   else
      shm.unmap(self.interlink)
   end
end

return Receiver
