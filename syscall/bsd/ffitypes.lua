-- ffi definitions of BSD types

local abi = require "syscall.abi"

local cdef = require "ffi".cdef

cdef [[
typedef uint32_t mode_t;
typedef uint8_t sa_family_t;
typedef uint64_t dev_t;

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
]]

