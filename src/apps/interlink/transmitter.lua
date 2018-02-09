-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local shm = require("core.shm")
local interlink = require("lib.interlink")

local Transmitter = {
   name = "apps.interlink.Transmitter",
   config = {
      name = {required=true}
   }
}

function Transmitter:new (conf)
   return setmetatable(
      {name=conf.name, interlink=interlink.new(conf.name)},
      {__index=Transmitter}
   )
end

function Transmitter:push ()
   local i, r = self.input.input, self.interlink
   while not (interlink.full(r) or link.empty(i)) do
      local p = link.receive(i)
      packet.account_free(p) -- stimulate breathing
      interlink.insert(r, p)
   end
   interlink.push(r)
end

function Transmitter:stop ()
   interlink.free(self.interlink, self.name)
end

return Transmitter
