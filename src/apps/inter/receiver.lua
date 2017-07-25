-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local shm = require("core.shm")
local ring = require("apps.inter.mcp_ring")

Receiver = {
   config = {
      name = {required=true},
      create = {default=false},
      size = {default=link.max+1}
   }
}

function Receiver:new (conf)
   local self = {}
   if conf.create then
      self.ring = ring.create(conf.size, conf.name)
      self.destroy = conf.name
   else
      self.ring = shm.open(conf.name, ring.mcp_t(conf.size))
   end
   ring.init(self.ring)
   return setmetatable(self, {__index=Receiver})
end

function Receiver:pull ()
   local o, r, n = self.output.output, self.ring, 0
   while not ring.empty(r) and n < engine.pull_npackets do
      link.transmit(o, ring.extract(r))
      n = n + 1
   end
   ring.pull(r)
end

function Receiver:stop ()
   shm.unmap(self.ring)
   if self.destroy then
      shm.unlink(self.destroy)
   end
end

return Receiver
