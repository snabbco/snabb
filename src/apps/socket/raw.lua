module(...,package.seeall)

local app    = require("core.app")
local link   = require("core.link")
local packet = require("core.packet")
local dev    = require("apps.socket.dev").dev

RawSocket = {}

function RawSocket:new (ifname)
   assert(ifname)
   self.__index = self
   return setmetatable({ dev = dev:new(ifname) }, self)
end

function RawSocket:pull ()
   assert(self.dev)
   local l = self.output.tx
   if l == nil then return end
   while not link.full(l) and self.dev:can_receive() do
      link.transmit(l, self.dev:receive())
   end
end

function RawSocket:push ()
   assert(self.dev)
   local l = self.input.rx
   if l == nil then return end
   while not link.empty(l) and self.dev:can_transmit() do
      local p = link.receive(l)
      self.dev:transmit(p)
      packet.deref(p)
   end
end

function selftest ()
   print("RawSocket selftest not implemented")
end

