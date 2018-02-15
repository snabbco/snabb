-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local shm = require("core.shm")
local interlink = require("lib.interlink")

local Receiver = {name="apps.interlink.Receiver"}

function Receiver:new (_, name)
   local self = {}
   self.shm_name = "group/interlink/"..name
   self.interlink = interlink.new(self.shm_name)
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
   interlink.free(self.interlink, self.shm_name)
end

return Receiver
