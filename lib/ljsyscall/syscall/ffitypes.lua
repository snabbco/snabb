-- these are types which are currently the same for all ports
-- in a module so rump does not import twice
-- note that even if type is same (like pollfd) if the metatype is different cannot be here due to ffi

-- TODO not sure we want these long term, merge to individual OS files.

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local ffi = require "ffi"

local abi = require "syscall.abi"

local defs = {}

local function append(str) defs[#defs + 1] = str end

append [[
// 8 bit
typedef unsigned char cc_t;

// 16 bit
typedef uint16_t in_port_t;

// 32 bit
typedef uint32_t uid_t;
typedef uint32_t gid_t;
typedef int32_t pid_t;

typedef unsigned int socklen_t;

// 64 bit
typedef int64_t off_t;

// defined as long even though eg NetBSD defines as int on 32 bit, its the same.
typedef long ssize_t;
typedef unsigned long size_t;

// sighandler in Linux
typedef void (*sig_t)(int);

struct iovec {
  void *iov_base;
  size_t iov_len;
};
struct winsize {
  unsigned short ws_row;
  unsigned short ws_col;
  unsigned short ws_xpixel;
  unsigned short ws_ypixel;
};
struct in_addr {
  uint32_t       s_addr;
};
struct in6_addr {
  unsigned char  s6_addr[16];
};
struct ethhdr {
  unsigned char   h_dest[6];
  unsigned char   h_source[6];
  unsigned short  h_proto; /* __be16 */
} __attribute__((packed));
struct udphdr {
  uint16_t source;
  uint16_t dest;
  uint16_t len;
  uint16_t check;
};
]]

-- endian dependent TODO not really, define in independent way
if abi.le then
append [[
struct iphdr {
  uint8_t  ihl:4,
           version:4;
  uint8_t  tos;
  uint16_t tot_len;
  uint16_t id;
  uint16_t frag_off;
  uint8_t  ttl;
  uint8_t  protocol;
  uint16_t check;
  uint32_t saddr;
  uint32_t daddr;
};
]]
else
append [[
struct iphdr {
  uint8_t  version:4,
           ihl:4;
  uint8_t  tos;
  uint16_t tot_len;
  uint16_t id;
  uint16_t frag_off;
  uint8_t  ttl;
  uint8_t  protocol;
  uint16_t check;
  uint32_t saddr;
  uint32_t daddr;
};
]]
end

ffi.cdef(table.concat(defs, ""))


