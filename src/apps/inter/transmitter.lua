-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local shm = require("core.shm")
local ring = require("apps.inter.mcp_ring")

Transmitter = {
   config = {
      name = {required=true},
      create = {default=false},
      size = {default=link.max+1}
   }
}

function Transmitter:new (conf)
   local self = {}
   if conf.create then
      self.ring = ring.create(conf.size, conf.name)
      self.destroy = conf.name
   else
      self.ring = shm.open(conf.name, ring.mcp_t(conf.size))
   end
   return setmetatable(self, {__index=Transmitter})
end

function Transmitter:push ()
   local i, r = self.input.input, self.ring
   while not (ring.full(r) or link.empty(i)) do
      ring.insert(r, link.receive(i))
   end
   ring.push(r)
end

function Transmitter:stop ()
   shm.unmap(self.ring)
   if self.destroy then
      shm.unlink(self.destroy)
   end
end

return Transmitter
