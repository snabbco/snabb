-- tester.lua -- Test switch operation by post-processing trace files.
-- Copright 2012 Snabb GmbH

module("tester",package.seeall)

local ffi  = require("ffi")
local pcap = require("pcap")
local C    = ffi.C

if #arg ~= 1 then
   print "Usage: tester <pcapfile>"
   print ""
   print "Test that the switching behaviour in pcapfile is correct."
   return
end

local file = io.open(arg[1], "r")
local pcap_file   = ffi.new("struct pcap_file")
local pcap_record = ffi.new("struct pcap_record")
local pcap_extra  = ffi.new("struct pcap_record_extra")

print("filename = " .. arg[1] .. " " .. #arg)
print(ffi.cast("struct pcap_file *", file:read(ffi.sizeof("struct pcap_file"))))

for packet, header, extra in pcap.records(arg[1]) do
   print(#packet, header, extra)
end

