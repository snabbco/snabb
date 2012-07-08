-- port.lua -- Switch network port
-- Copyright 2012 Snabb GmbH.
-- Free software under MIT license. See http://opensource.org/licenses/MIT

module(...,package.seeall)

local ffi = require("ffi")
local shm = require("shm")
local fabric = ffi.load("fabric")
local C = ffi.C

local ports = {}
local Port = { id = nil, statistics = nil }

-- Create a new port with a meaningful identifier.
function new (id, filename)
   local self = { first = true }
   setmetatable(self, {__index = Port})
   table.insert(ports, self)
   if filename then self:connect(filename) end
   return self
end

-- Connect to a shared memory packet ring.
function Port:connect (shmfilename)
   self.shm = fabric.open_shm(shmfilename)
end

-- Enable tracing of packets to a file.
function Port:trace (pcapfilename)
   self.tracefile = io.open(pcapfilename, "w+")
   pcap.write_file_header(self.tracefile)
end

-- Disable packet tracing.
function Port:untrace ()
   self.tracefile:close()
   self.tracefile = nil
end

function Port:available()
   return shm.available(self.shm.vm2host)
end

function Port:full()
   return shm.full(self.shm.host2vm)
end

function Port:receive ()
   if self:available() then
      local ring = self.shm.vm2host
      -- Free the previous packet, if there is one.
      -- Each packet stays alive until the next one is read.
      if self.first then
	 self.first = false
      else
	 shm.advance_head(ring)
      end
      return shm.packet(ring)
   end
end

function Port:transmit (packet)
   if shm.full(self.shm.host2vm) then
      return false
   end
   if self.tracefile then
      pcap.write_record(self.tracefile, packet.data, packet.length)
   end
   local ring = self.shm.host2vm
   C.memcpy(ring.packets[ring.tail].data, packet.data, packet.length)
   ring.packets[ring.tail].length = packet.length
   shm.advance_tail(ring)
   return true
end

function allports ()
   return ports
end

