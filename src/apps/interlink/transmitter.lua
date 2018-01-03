-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local shm = require("core.shm")
local interlink = require("lib.interlink")

local Transmitter = {
   name = "apps.interlink.Transmitter",
   config = {
      name = {required=true},
      create = {default=false}
   }
}

function Transmitter:new (conf)
   local self = {}
   if conf.create then
      self.interlink = interlink.create(conf.name)
      self.destroy = conf.name
   else
      self.interlink = interlink.open(conf.name)
   end
   return setmetatable(self, {__index=Transmitter})
end

function Transmitter:push ()
   local i, r = self.input.input, self.interlink
   while not (interlink.full(r) or link.empty(i)) do
      interlink.insert(r, link.receive(i))
   end
   interlink.push(r)
end

function Transmitter:stop ()
   if self.destroy then
      interlink.free(self.interlink)
      shm.unlink(self.destroy)
   else
      shm.unmap(self.interlink)
   end
end

return Transmitter
