-- port.lua -- Switch network port
-- Copyright 2012 Snabb GmbH.
-- Free software under MIT license. See http://opensource.org/licenses/MIT

module(...,package.seeall)

local ffi = require("ffi")
local shm = require("shm")
local fabric = ffi.load("fabric")
local C = ffi.C

-- List of all ports.
local ports = {}
-- Port class.
local Port = { id = nil, statistics = nil }
-- Global TCPDUMP trace file.
local tracefile = nil

-- Create a new port with a meaningful identifier.
function new (id, filename)
   local self = { id = id, first = true }
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
function trace (pcapfilename)
   tracefile = io.open(pcapfilename, "w+")
   pcap.write_file_header(tracefile)
end

-- Disable packet tracing.
function untrace ()
   tracefile:close()
   tracefile = nil
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
      local packet = shm.packet(ring)
      if tracefile then
	 pcap.write_record(tracefile, packet.data, packet.length, self.id, true)
      end
      return packet
   end
end

function Port:transmit (packet)
   if shm.full(self.shm.host2vm) then
      return false
   end
   if tracefile then
      pcap.write_record(tracefile, packet.data, packet.length, self.id, false)
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

