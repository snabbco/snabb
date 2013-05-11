-- ffi definitions of OSX types

local abi = require "syscall.abi"

local cdef = require "ffi".cdef

cdef [[
typedef uint16_t mode_t;
typedef uint8_t sa_family_t;
]]

