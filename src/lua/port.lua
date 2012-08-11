-- port.lua -- Switch network port
-- Copyright 2012 Snabb GmbH. See the file LICENSE.

module(...,package.seeall)

local ffi = require("ffi")
local shm = require("shm")
local fabric = ffi.load("fabric")
local C = ffi.C

-- List of all ports.
local ports = {}
-- Global TCPDUMP trace file.
local tracefile = nil

-- Port class.
Port = { id = nil, statistics = nil }

-- Create a new port with a meaningful identifier.
function Port:new (id, mediumtype, ...)
   local medium = mediumtype:new(...)
   local new = { id = id, medium = medium }
   setmetatable(new, {__index = self})
   table.insert(ports, new)
   return new
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

function Port:receive ()
   return self.medium.receive()
end

function Port:transmit (packet)
   return self.medium.transmit(packet)
end

function allports ()
   return ports
end

