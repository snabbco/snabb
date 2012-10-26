-- medium.lua -- Network access medium.
-- Copyright 2012 Snabb GmbH. See the file COPYING for license details.

module(...,package.seeall)

local ffi    = require("ffi")
local snabb  = ffi.load("snabb")

-- Shared memory medium.
SHM = {}

function SHM:new (filename)
   local new = { shm = snabb.open_shm(filename) }
   setmetatable(new, {__index = self})
   return new
end

function SHM:transmit (packet)
   local ring = self.shm.host2vm
   if not shm.full(ring) then
      ffi.C.memcpy(ring.packets[ring.tail].data, packet.data, packet.length)
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
      local result = ring.packets[ring.head]
      shm.advance_head(ring)
      return result
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

-- TAP medium.

TAP = {}

function TAP:new (interfacename)
   local new = { fd = snabb.open_tap(interfacename or ""),
		 nextbuf = newbuffer() }
   assert(new.fd >= 0)
   setmetatable(new, {__index = self})
   return new
end

function TAP:transmit (packet)
   local writelen = ffi.C.write(self.fd, packet.data, packet.length)
   return writelen == packet.length
end

function TAP:receive (packet)
   local readlen = ffi.C.read(self.fd, self.nextbuf, 65536)
   if readlen > 0 then
      local frame = { data = self.nextbuf, length = readlen }
      self.nextbuf = newbuffer()
      return frame
   else
      return nil
   end
end

function newbuffer ()
   return ffi.new("char[65536]")
end

