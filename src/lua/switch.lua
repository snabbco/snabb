-- Copyright 2012 Snabb GmbH
--
-- Ethernet switch module.
--
-- Packets are represented as tables with the following fields:
--   inputport = port the packet was received on
--   src, dst  = string representations of the ethernet src/dst addresses
--   length    = number of bytes of data
--   data      = pointer to memory buffer containing data

module(...,package.seeall)

require("shm")

local ffi = require("ffi")
local fabric = ffi.load("fabric")
local dev = fabric.open_shm("/tmp/ba")
local c   = require("c")
local C = ffi.C

-- Ethernet frame format

ffi.cdef[[
      struct ethh {
	 uint8_t  dst[6];
	 uint8_t  src[6];
	 uint16_t type;   // NOTE: Network byte order!
      } __attribute__ ((__packed__));
]]

-- Counters

-- Switch ports
local ports = {fabric.open_shm("/tmp/a"),
	       fabric.open_shm("/tmp/b")}

-- Switch logic
local fdb = {} -- { MAC -> [Port] }

function main ()
   while true do
      -- print("Main loop")
      for _,port in ipairs(ports) do
	 local ring = port.vm2host
	 if shm.available(ring) then
	    local packet = makepacket(port,
				      ring.packets[ring.head].length,
				      ring.packets[ring.head].data)
	    input(packet)
	    shm.advance_head(ring)
	 end
      end
      C.usleep(100000)
   end
end

function makepacket (inputport, length, data)
   print "makepacket"
   return {inputport = inputport,
	   length    = length,
	   data      = data,
	   src       = ffi.string(data, 6),
	   dst       = ffi.string(data + 6, 6)}
end

-- Input a packet into the switching logic.
function input (packet)
   fdb:update(packet)
   output(packet)
end

-- Output `eth' to the appropriate ports.
function output (packet)
   print("Sending packet to " .. #fdb:lookup(packet))
   for _,port in ipairs(fdb:lookup(packet)) do
      transmit(packet, port)
   end
end

-- Transmit PACKET onto PORT.
function transmit (packet, port)
   -- Make a full copy to keep it simple
   local txring = port.host2vm
   if not shm.full(txring) then
      print "tx"
      C.memcpy(txring.packets[txring.tail].data,
	       packet.data,
	       packet.length)
      txring.packets[txring.tail].length = packet.length
      shm.advance_tail(txring)
   else
      print "full"
   end
end

-- Forwarding database

function fdb:update (packet)
   self[packet.src] = packet.inputport
end

function fdb:lookup (packet)
   if self[packet.dst] then
      return {self[packet.dst]}
   else
      return ports
   end
end

-- Utils

function mac2string (mac)
   return ((string.gsub(string, ".",
                        function (c)
                           return string.format("%02X:", string.byte(c))
                        end)))
end

