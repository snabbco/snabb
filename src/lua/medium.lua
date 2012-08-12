-- medium.lua -- Network access medium.
-- Copyright 2012 Snabb GmbH. See the file COPYING for license details.

module(...,package.seeall)

local ffi    = require("ffi")
local snabb  = ffi.load("snabb")

-- Shared memory medium.
SHM = {}

function SHM:new (filename)
   local new = { first = true, shm = snabb.open_shm(filename) }
   setmetatable(new, {__index = self})
   return new
end

function SHM:transmit (packet)
   local ring = self.shm.host2vm
   if not shm.full(ring) then
      C.memcpy(ring.packets[ring.tail].data, packet.data, packet.length)
      ring.packets[ring.tail].length = packet.length
      shm.advance_tail(ring)
      return true
   else
      return false
   end
end

function SHM:receive ()
   local ring = self.shm.vm2host
   if shm.available(ring) then
      if self.first then
	 self.first = false
      else
	 shm.advance_head(ring)
      end
      return shm.packet(ring)
   else
      return nil
   end
end

-- Null medium.

Null = {}

function Null:new ()
   local new = {}
   setmetatable(new, {__index = self})
   return new
end

function Null:transmit (packet)
   return true
end

function Null:receive ()
   return nil
end

