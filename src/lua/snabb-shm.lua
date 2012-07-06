#!/usr/bin/env luajit
-- Copyright 2012 Snabb Gmbh.

local ffi = require("ffi")
local fabric = ffi.load("fabric")

ffi.cdef(io.open("/home/luke/hacking/QEMU/net/snabb-shm-dev.h"):read("*a"))
ffi.cdef(io.open("/home/luke/hacking/snabb-fabric/src/c/fabric.h"):read("*a"))

print("loaded ffi'ery")
print(ffi.sizeof("struct snabb_shm_dev"))

local shm = fabric.open_shm("/tmp/ba");

-- shm.tx_head = ffi.C.SHM_RING_SIZE

print(shm.magic)

-- shm.tx_head = 0

print("head = " .. shm.tx_head .. " tail = " .. shm.tx_tail)

-- Print availability

print("available = " .. shm.tx_tail - shm.tx_head)

-- Print size of first packet

print("size[" .. shm.tx_head .. "] = " .. shm.tx_ring[shm.tx_head].length)

shm.tx_head = shm.tx_head + 1

-- Dump a packet out as pcap

ffi.cdef[[
struct pcap {
    /* file header */
    uint32_t magic_number;   /* magic number */
    uint16_t version_major;  /* major version number */
    uint16_t version_minor;  /* minor version number */
    int32_t  thiszone;       /* GMT to local correction */
    uint32_t sigfigs;        /* accuracy of timestamps */
    uint32_t snaplen;        /* max length of captured packets, in octets */
    uint32_t network;        /* data link type */
    /* record header */
    uint32_t ts_sec;         /* timestamp seconds */
    uint32_t ts_usec;        /* timestamp microseconds */
    uint32_t incl_len;       /* number of octets of packet saved in file */
    uint32_t orig_len;       /* actual length of packet */
}
]]

local pcap = ffi.new("struct pcap")
pcap.magic_number = 0xa1b2c3d4
pcap.version_major = 2
pcap.version_minor = 4
pcap.snaplen = 65535
pcap.network = 1
pcap.incl_len = shm.tx_ring[shm.tx_head].length
pcap.orig_len = pcap.incl_len

print("writing pcap file..")

io.output("/tmp/x.pcap", "w")
io.write(ffi.string(pcap, ffi.sizeof(pcap)))
io.write(ffi.string(shm.tx_ring[shm.tx_head].data, shm.tx_ring[shm.tx_head].length))
io.close()



