-- ffi definitions of BSD types

local abi = require "syscall.abi"

local cdef = require "ffi".cdef

cdef [[
typedef uint32_t mode_t;
typedef uint8_t sa_family_t;
typedef uint64_t dev_t;
]]

