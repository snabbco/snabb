-- choose correct ffi types for OS

-- TODO many are common and can be shared here

local abi = require "syscall.abi"

local cdef = require "ffi".cdef

cdef[[
// 16 bit
typedef uint16_t in_port_t;

// 32 bit
typedef uint32_t uid_t;
typedef uint32_t gid_t;
typedef uint32_t socklen_t;
typedef uint32_t id_t;
typedef int32_t pid_t;
typedef int32_t clockid_t;
typedef int32_t daddr_t;
typedef uint32_t le32; /* this is little endian */
typedef uint32_t off32_t; /* only used for eg mmap2 on Linux */

// 64 bit
typedef uint64_t off_t;

// typedefs which are word length
typedef unsigned long size_t;
typedef long ssize_t;
typedef long time_t;
typedef long blksize_t;
typedef long blkcnt_t;
typedef long clock_t;
typedef unsigned long ino_t;
typedef unsigned long nlink_t;
typedef unsigned long nfds_t;

struct iovec {
  void *iov_base;
  size_t iov_len;
};
struct in_addr {
  uint32_t       s_addr;
};
struct in6_addr {
  unsigned char  s6_addr[16];
};
]]

require("syscall." .. abi.os .. ".ffitypes")

