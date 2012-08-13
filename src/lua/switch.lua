-- Copyright 2012 Snabb GmbH. See the file COPYING for license details.
--
-- Ethernet switch module.
--
-- Packets are represented as tables with the following fields:
--   inputport = port the packet was received on
--   src, dst  = string representations of the ethernet src/dst addresses
--   length    = number of bytes of data
--   data      = pointer to memory buffer containing data

module("switch",package.seeall)

require("shm")

local ffi  = require("ffi")
local c    = require("c")
local port = require("port")
local medium = require("medium")
local C    = ffi.C

local tracefile

function trace (filename)
   tracefile = io.open(filename, "w+")
   pcap.write_file_header(tracefile)
end

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
--local ports = { port.new(1, "/tmp/a"),
--		port.new(2, "/tmp/b") }

-- local ports = { port.new(1), port.new(2), port.new(3) }

local ports = {}
local allports = {}

function addport(id, medium, ...)
   local port = port.Port:new(id, medium, ...)
   table.insert(ports, port)
   table.insert(allports, #allports + 1)
end

function getport(id)
   return ports[id]
end

-- testing data

local pcap_file   = ffi.new("struct pcap_file")
local pcap_record = ffi.new("struct pcap_record")
local pcap_extra  = ffi.new("struct pcap_record_extra")

-- Switch logic
local fdb = {} -- { MAC -> [Port] }

function main ()
   while true do
      -- print("Main loop")
      for _,port in ipairs(ports) do
	 local frame = port:receive()
	 if frame ~= nil then
	    local packet = makepacket(port, frame.data, frame.length)
	    input(packet)
	 end
      end
      C.usleep(100000)
   end
end

function testmain ()
   local testfile = arg[1]
   for data, header, extra in pcap.records(testfile) do
      if extra.flags == 0 then
	 local frame = ffi.cast("char *", data)
	 local packet = makepacket(extra.port_id, frame, header.orig_len)
	 input(packet)
      end
   end
end

function makepacket (inputport, data, length)
   return {inputport = inputport,
	   length    = length,
	   data      = data,
	   src       = ffi.string(data, 6),
	   dst       = ffi.string(data + 6, 6)}
end

function tracepacket (packet, direction)
   if tracefile then
      pcap.write_record(tracefile, packet.data, packet.length,
			packet.inputport.id, direction == "input")
   end
end

-- Input a packet into the switching logic.
function input (packet)
   tracepacket(packet, "input")
   fdb:update(packet)
   output(packet)
end

-- Output `eth' to the appropriate ports.
function output (packet)
   print("Sending packet to " .. #fdb:lookup(packet))
   for _,port in ipairs(fdb:lookup(packet)) do
      if port ~= packet.inputport.id then
	 print(tostring(packet.inputport.id) .. " -> " .. tostring(port) .. " (" .. tostring(packet.length) .. ")")
	 if (ports[port]):transmit(packet) then
	    tracepacket(packet, "output")
	 else
	    print "TX overflow" end
      end
   end
end

-- Forwarding database

function fdb:update (packet)
   self[packet.src] = packet.inputport.id
end

function fdb:lookup (packet)
   local out = self[packet.dst]
   if out ~= nil and out ~= packet.inputport then
      print("out = " .. tostring(out))
      return {out}
   else
      return allports
   end
end

-- testmain()

