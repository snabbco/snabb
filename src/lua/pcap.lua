-- pcap.lua -- simple pcap file export
--
-- Copyright 2012 Snabb GmbH

module(...,package.seeall)

local ffi = require("ffi")

-- PCAP file format: http://wiki.wireshark.org/Development/LibpcapFileFormat/
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

function write_file_header(file)
   local pcap_file = ffi.new("struct pcap_file")
   pcap_file.magic_number = 0xa1b2c3d4
   pcap_file.version_major = 2
   pcap_file.version_minor = 4
   pcap_file.snaplen = 65535
   pcap_file.network = 1
   file:write(ffi.string(pcap_file, ffi.sizeof(pcap_file)))
   file:flush()
end

function write_record(file, ffi_buffer, length)
   local pcap_record = ffi.new("struct pcap_record")
   pcap_record.incl_len = length
   pcap_record.orig_len = length
   file:write(ffi.string(pcap_record, ffi.sizeof(pcap_record)))
   file:write(ffi.string(ffi_buffer, length))
   file:flush()
end

