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

local ffi  = require("ffi")
local fabric = ffi.load("fabric")
local dev  = fabric.open_shm("/tmp/ba")
local c    = require("c")
local port = require("port")
local C    = ffi.C

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
local ports = { port.new(1, "/tmp/a"),
		port.new(2, "/tmp/b") }

port.trace("/tmp/switch.pcap")

-- Switch logic
local fdb = {} -- { MAC -> [Port] }

function main ()
   while true do
      -- print("Main loop")
      for _,port in ipairs(ports) do
	 if port:available() then
	    local frame = port:receive()
	    local packet = makepacket(port, frame.data, frame.length)
	    input(packet)
	 end
      end
      C.usleep(100000)
   end
end

function makepacket (inputport, data, length)
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
      if not port:transmit(packet, port) then print "TX overflow" end
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

