// See:
//   http://www.winpcap.org/ntar/draft/PCAP-DumpFileFormat.html
//   https://github.com/the-tcpdump-group/libpcap/blob/master/sf-pcap-ng.c
module(...,package.seeall)

local ffi = require("ffi")

ffi.cdef[[
struct pcapng_block_header {
   uint32_t block_type;
   uint32_t total_length;
};

struct pcapng_block_trailer {
   uint32_t total_length;
};

struct pcapng_option_header {
   uint16_t option_code;
   uint16_t option_length;
};

struct pcapng_interface_description {
   uint16_t linktype;
   uint16_t reserved;
   uint32_t snaplen;
   // ... options, trailer ...
};

struct pcapng_enhanced_packet_fields {
   uint32_t interface_id;
   uint32_t timestamp_high;
   uint32_t timestamp_low;
   uint32_t caplen;
   uint32_t len;
   // ... packet data, options, trailer ...
};
]]

function open_trace_for_write (filename)
end

function write_interface_description (trace, name, l)
end

function write_packet (trace, p, timestamp)
end

function close_trace (trace)
end

