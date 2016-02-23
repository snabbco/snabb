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
};

/* This is the header of a packet on disk.  */
struct pcap_record {
    /* record header */
    uint32_t ts_sec;         /* timestamp seconds */
    uint32_t ts_usec;        /* timestamp microseconds */
    uint32_t incl_len;       /* number of octets of packet saved in file */
    uint32_t orig_len;       /* actual length of packet */
};

/* This is the header of a packet as passed to pcap_offline_filter.  */
struct pcap_pkthdr {
    /* record header */
    long ts_sec;             /* timestamp seconds */
    long ts_usec;            /* timestamp microseconds */
    uint32_t incl_len;       /* number of octets of packet saved in file */
    uint32_t orig_len;       /* actual length of packet */
};
]]

-- BPF program format.  Note: the bit module represents uint32_t values
-- with the high-bit set as negative int32_t values, so we do the same
-- for all of our 32-bit values including the "k" field in BPF
-- instructions.
ffi.cdef[[
struct bpf_insn { uint16_t code; uint8_t jt, jf; int32_t k; };
struct bpf_program { uint32_t bf_len; struct bpf_insn *bf_insns; };
]]
local bpf_program_mt = {
  __len = function (program) return program.bf_len end,
  __index = function (program, idx)
     assert(idx >= 0 and idx < #program)
     return program.bf_insns[idx]
  end
}

bpf_insn = ffi.typeof("struct bpf_insn")
bpf_program = ffi.metatype("struct bpf_program", bpf_program_mt)
pcap_record = ffi.typeof("struct pcap_record")
pcap_pkthdr = ffi.typeof("struct pcap_pkthdr")

function selftest ()
   print("selftest: ffi_types")
   print("OK")
end
