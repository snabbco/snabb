-- tracemaker.lua -- Create trace files for exercising the tester.
-- Copyright 2012 Snabb GmbH

-- These are hand-written traces to debug the tester. It would be
-- better to randomly generate these tests with something like
-- QuickCheck.

module("tracemaker",package.seeall)

local pcap = require("pcap")

-- Handy MAC addresses
local zero  = "\0\0\0\0\0\0"   -- 00:00:00:00:00:00
local one   = "\1\1\1\1\1\1"   -- 01:01:01:01:01:01
local two   = "\2\2\2\2\2\2"   -- 02:02:02:02:02:02
local mcast = "\x80\0\0\0\0\0" -- 80:00:00:00:00:00 (multicast)
-- Ethertype
local ipv4  = "\x08\x00"       -- ethertype
local none = "\x00\x00"

local IN  = true
local OUT = false

local endtrace = {IN, 0, zero..zero..none}

local traces = {
   -- FAILLOOP: Loop ethernet traffic illegally
   {"failloop", 
    {{IN,  0, zero..one..none},
     {OUT, 0, zero..one..none},
     endtrace}},
   -- FAILDROP: Drop input frame.
   {"faildrop",
    {{IN,  0, zero..one..none},
     endtrace}},
   -- FAILFORWARD: Don't forward the frame to its rightful port.
   {"failforward",
    {{IN,  0, zero..one..none},
     {OUT, 1, zero..one..none},
     {IN,  1, one..zero..none},
     {OUT, 2, one..zero..none},
     endtrace}},
   -- FAILFLOOD: Don't multicast to every port.
   {"failflood",
    -- Learn about ports 0,1,2
    {{IN,  0, zero..one..none},
     {OUT, 1, zero..one..none},
     {IN,  1, one..two..none},
     {OUT, 2, one..two..none},
     {IN,  2, two..zero..none},
     {OUT, 0, two..zero..none},
     -- Multicast only goes out one port
     {IN,  0, zero..mcast..none},
     {OUT, 1, zero..mcast..none},
     endtrace}},
   {"passall",
    {{IN,  0, zero..one..none},
     {OUT, 1, zero..one..none},
     {IN,  1, one..two..none},
     {OUT, 2, one..two..none},
     {IN,  2, two..zero..none},
     {OUT, 0, two..zero..none},
     -- Multicast only goes out one port
     {IN,  0, zero..mcast..none},
     {OUT, 1, zero..mcast..none},
     {OUT, 2, zero..mcast..none},
     endtrace}}
}

local debug = false

function generate(name, packets)
   if debug then print("Creating "..name..".cap") end
   local file = io.open(name..".cap", "w+")
   pcap.write_file_header(file)
   for _,packet in ipairs(packets) do
      pcap.write_record(file, packet[3], #packet[3],  packet[2], packet[1])
   end
end

for _,trace in ipairs(traces) do
   generate(trace[1], trace[2])
end

