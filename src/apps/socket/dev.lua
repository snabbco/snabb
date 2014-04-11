module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local buffer = require("core.buffer")
local packet = require("core.packet")
require("lib.raw.raw_h")
require("apps.socket.io_h")

dev = {}

function dev:new(ifname)
   assert(ifname)
   self.__index = self
   local dev = { fd = C.open_raw(ifname) }
   return setmetatable(dev, self)
end

function dev:transmit(p)
   assert(self.fd)
   assert(C.send_packet(self.fd, p) ~= -1)
end

function dev:can_transmit()
   return C.can_transmit(self.fd) == 1
end

function dev:receive()
   assert(self.fd)
   local size = C.msg_size(self.fd)
   assert(size ~= -1)
   local p = packet.allocate()
   local nbuffers = math.ceil(size/buffer.size)
   assert(nbuffers <= C.PACKET_IOVEC_MAX)
   for i = 1, nbuffers do
      local b = buffer.allocate()
      packet.add_iovec(p, b, 0)
   end
   local s = C.receive_packet(self.fd, p)
   assert(s ~= -1)
   return p
end

function dev:can_receive()
   return C.can_receive(self.fd) == 1
end
