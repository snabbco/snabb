-- ffi definitions of OSX types

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit

local function init(abi)

local defs = {}

local function append(str) defs[#defs + 1] = str end

append [[
typedef uint16_t mode_t;
typedef uint8_t sa_family_t;
typedef uint32_t dev_t;
typedef int64_t blkcnt_t;
typedef int32_t blksize_t;
typedef int32_t suseconds_t;
typedef uint16_t nlink_t;
typedef uint64_t ino_t; // at least on recent desktop; TODO define as ino64_t
typedef long time_t;
typedef int32_t daddr_t;
typedef unsigned long clock_t;
typedef unsigned int nfds_t;

/* actually not a struct at all in osx, just a uint32_t but for compatibility fudge it */
/* TODO this should work, otherwise need to move all sigset_t handling out of common types */
typedef struct {
  uint32_t      val[1];
} sigset_t;

typedef struct fd_set {
  int32_t fds_bits[32];
} fd_set;
struct pollfd
{
  int     fd;
  short   events;
  short   revents;
};
struct msghdr {
  void *msg_name;
  socklen_t msg_namelen;
  struct iovec *msg_iov;
  int msg_iovlen;
  void *msg_control;
  socklen_t msg_controllen;
  int msg_flags;
};
struct cmsghdr {
  size_t cmsg_len;
  int cmsg_level;
  int cmsg_type;
  unsigned char cmsg_data[?];
};
struct timespec {
  time_t tv_sec;
  long   tv_nsec;
};
struct timeval {
  time_t tv_sec;
  suseconds_t tv_usec;
};
struct sockaddr {
  uint8_t       sa_len;
  sa_family_t   sa_family;
  char          sa_data[14];
};
struct sockaddr_storage {
  uint8_t       ss_len;
  sa_family_t   ss_family;
  char          __ss_pad1[6];
  int64_t       __ss_align;
  char          __ss_pad2[128 - 2 - 8 - 6];
};
struct sockaddr_in {
  uint8_t         sin_len;
  sa_family_t     sin_family;
  in_port_t       sin_port;
  struct in_addr  sin_addr;
  int8_t          sin_zero[8];
};
struct sockaddr_in6 {
  uint8_t         sin6_len;
  sa_family_t     sin6_family;
  in_port_t       sin6_port;
  uint32_t        sin6_flowinfo;
  struct in6_addr sin6_addr;
  uint32_t        sin6_scope_id;
};
struct sockaddr_un {
  uint8_t         sun_len;
  sa_family_t     sun_family;
  char            sun_path[104];
};
struct stat {
  dev_t           st_dev;
  mode_t          st_mode;
  nlink_t         st_nlink;
  ino_t           st_ino;
  uid_t           st_uid;
  gid_t           st_gid;
  dev_t           st_rdev;
  struct timespec st_atimespec;
  struct timespec st_mtimespec;
  struct timespec st_ctimespec;
  struct timespec st_birthtimespec;
  off_t           st_size;
  blkcnt_t        st_blocks;
  blksize_t       st_blksize;
  uint32_t        st_flags;
  uint32_t        st_gen;
  int32_t         st_lspare;
  int64_t         st_qspare[2];
};
union sigval {
  int     sival_int;
  void    *sival_ptr;
};
typedef struct __siginfo {
  int     si_signo;
  int     si_errno;
  int     si_code;
  pid_t   si_pid;
  uid_t   si_uid;
  int     si_status;
  void    *si_addr;
  union sigval si_value;
  long    si_band;
  unsigned long   __pad[7];
} siginfo_t;
struct sigaction {
  union {
    void (*sa_handler)(int);
    void (*sa_sigaction)(int, siginfo_t *, void *);
  } sa_handler; // renamed as in Linux definition
  sigset_t sa_mask;
  int sa_flags;
};
struct dirent {
  uint64_t  d_ino;
  uint64_t  d_seekoff;
  uint16_t  d_reclen;
  uint16_t  d_namlen;
  uint8_t   d_type;
  char      d_name[1024];
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

local ffi = require "ffi"

ffi.cdef(table.concat(defs, ""))

end

return {init = init}

