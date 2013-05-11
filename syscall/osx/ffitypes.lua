-- ffi definitions of OSX types

local abi = require "syscall.abi"

local cdef = require "ffi".cdef

cdef [[
typedef uint16_t mode_t;
typedef uint8_t sa_family_t;
typedef uint32_t dev_t;

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
struct msghdr {
  void            *msg_name;
  socklen_t       msg_namelen;
  struct iovec    *msg_iov;
  int             msg_iovlen;
  void            *msg_control;
  socklen_t       msg_controllen;
  int             msg_flags;
};
]]

