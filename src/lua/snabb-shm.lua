#!/usr/bin/env luajit
-- Copyright 2012 Snabb GmbH

module(..,package.seeall)
require("pcap")

local ffi = require("ffi")
local C = ffi.C
local fabric = ffi.load("fabric")

ffi.cdef(io.open("/home/luke/hacking/QEMU/net/snabb-shm-dev.h"):read("*a"))
ffi.cdef(io.open("/home/luke/hacking/snabb-fabric/src/c/fabric.h"):read("*a"))

print("loaded ffi'ery")
print(ffi.sizeof("struct snabb_shm_dev"))

local shm = fabric.open_shm("/tmp/ba");

-- Return true if `shm' is a valid shared memory packet device.
function check_shm_file (shm)
   return shm.magic == 0x57ABB000 and shm.version == 1
end

-- Return true if a packet is available.
function available (shm)
   return shm.tx_tail ~= shm.tx_head + 1 % C.SHM_RING_SIZE
end

-- Return the current shm_packet in the ring.
function packet (shm)
   return shm.tx_ring[shm.tx_head]
end

-- Advance to the next packet in the ring.
function next (shm)
   shm.tx_head = (shm.tx_head + 1) % C.SHM_RING_SIZE
end

-- shm.tx_head = C.SHM_RING_SIZE

print("Ring valid: " .. tostring(check_shm_file(shm)))

-- shm.tx_head = 0

print("head = " .. shm.tx_head .. " tail = " .. shm.tx_tail)

-- Print availability

print("available: " .. tostring(available(shm)))

-- Print size of first packet

print("size[" .. shm.tx_head .. "] = " .. packet(shm).length)

next(shm)

-- Dump a packet out as pcap

ffi.cdef[[
struct pcap_file {
    /* file header */
    uint32_t magic_number;   /* magic number */
    uint16_t version_major;  /* major version number */
    uint16_t version_minor;  /* minor version number */
    int32_t  thiszone;       /* GMT to local correction */
    uint32_t sigfigs;        /* accuracy of timestamps */
    uint32_t snaplen;        /* max length of captured packets, in octets */
    uint32_t network;        /* data link type */
}

struct pcap_record {
    /* record header */
    uint32_t ts_sec;         /* timestamp seconds */
    uint32_t ts_usec;        /* timestamp microseconds */
    uint32_t incl_len;       /* number of octets of packet saved in file */
    uint32_t orig_len;       /* actual length of packet */
}
]]

local pcap_file = ffi.new("struct pcap_file")
pcap_file.magic_number = 0xa1b2c3d4
pcap_file.version_major = 2
pcap_file.version_minor = 4
pcap_file.snaplen = 65535
pcap_file.network = 1

print("writing pcap file..")
file = io.open("/tmp/x.pcap", "w+")
file:write(ffi.string(pcap_file, ffi.sizeof(pcap_file)))

local pcap_record = ffi.new("struct pcap_record")
while true do
   if available(shm) then
      print("Writing a " .. packet(shm).length .. " byte packet..")
      io.flush()
      pcap_record.incl_len = shm.tx_ring[shm.tx_head].length
      pcap_record.orig_len = pcap_record.incl_len
      file:write(ffi.string(pcap_record, ffi.sizeof(pcap_record)))
      file:write(ffi.string(shm.tx_ring[shm.tx_head].data, shm.tx_ring[shm.tx_head].length))
      file:flush()
      next(shm)
   else
      print("nuthin' doin' " .. shm.tx_head .. " " .. shm.tx_tail)
   end
end
file:close()

