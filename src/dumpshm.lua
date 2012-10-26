-- dumpshm.lua -- Dump a SHM interface as text and pcap.
--
-- Copyright 2012 Snabb GmbH. See the file LICENSE.

module("dumpshm",package.seeall)

local ffi = require("ffi")
local shm = require("shm")
local snabb = ffi.load("snabb")

if #arg ~= 1 and #arg ~= 3 then
   io.stderr:write("Usage: dumpshm <shmfile> [vm2host host2vm]\n")
end

function main ()
   local dev = snabb.open_shm(arg[1])
   print("SHM_RING_SIZE   = " .. tostring(ffi.C.SHM_RING_SIZE))
   print("SHM_PACKET_SIZE = " .. tostring(ffi.C.SHM_PACKET_SIZE))
   print("magic           = " .. tostring(dev.magic))
   print("version         = " .. tostring(dev.version))
   print("vm2host head:tail = "..dev.vm2host.head..":"..dev.vm2host.tail)
   print("host2vm head:tail = "..dev.host2vm.head..":"..dev.host2vm.tail)
   if #arg >= 3 then
      print()
      dump_ring_to_pcap(dev.vm2host, arg[2])
      print("wrote vm2host to " .. arg[2])
      dump_ring_to_pcap(dev.host2vm, arg[3])
      print("wrote host2vm to " .. arg[3])
   end
end

function dump_ring_to_pcap(ring, filename)
   local file = io.open(filename, "w+")
   pcap.write_file_header(file)
   for i = 0, ffi.C.SHM_RING_SIZE-1, 1 do
      pcap.write_record(file, ring.packets[i].data, ring.packets[i].length)
   end
   file.close()
end

main()
