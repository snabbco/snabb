module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local packet = require("core.packet")
require("lib.raw.raw_h")
require("apps.socket.io_h")

dev = {}

function dev:new (ifname)
   assert(ifname)
   local fd = C.open_raw(ifname)
   if fd == -1 then return nil, -1 end
   self.__index = self
   return setmetatable({fd = fd}, self)
end

function dev:transmit (p)
   assert(self.fd)
   assert(C.send_packet(self.fd, p) ~= -1)
end

function dev:can_transmit ()
   return C.can_transmit(self.fd) == 1
end

function dev:receive ()
   assert(self.fd)
   local p = packet.allocate()
   local s = C.receive_packet(self.fd, p)
   assert(s ~= -1)
   return p
end

function dev:can_receive ()
   return C.can_receive(self.fd) == 1
end

function dev:stop ()
   assert(self.fd)
   return C.close_raw(self.fd)
end
