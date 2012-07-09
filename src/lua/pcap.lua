-- pcap.lua -- simple pcap file export
--
-- Copyright 2012 Snabb GmbH

module(...,package.seeall)

local ffi = require("ffi")
local c   = require("c")

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

struct pcap_record_extra {
   /* Extra metadata that we append to the pcap record, after the payload. */
   uint32_t port_id; /* port the packet is captured on */
   uint32_t flags;   /* bit 0 set means input, bit 0 clear means output */
   uint64_t reserved0, reserved1, reserved2, reserved3;
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

local pcap_extra = ffi.new("struct pcap_record_extra")
ffi.C.memset(pcap_extra, 0, ffi.sizeof(pcap_extra))

function write_record(file, ffi_buffer, length, port, input)
   local pcap_record = ffi.new("struct pcap_record")
   local incl_len = length;
   if port ~= nil then
      incl_len = incl_len + ffi.sizeof(pcap_extra)
      pcap_extra.port_id = port
      pcap_extra.flags = (input and 0) or 1
   end
   pcap_record.incl_len = incl_len
   pcap_record.orig_len = length
   file:write(ffi.string(pcap_record, ffi.sizeof(pcap_record)))
   file:write(ffi.string(ffi_buffer, length))
   if port ~= nil then
      print 'write extra bytes...'
      file:write(ffi.string(pcap_extra, ffi.sizeof(pcap_extra)))
   end
   file:flush()
end

