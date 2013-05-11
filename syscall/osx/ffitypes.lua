-- ffi definitions of BSD types

local abi = require "syscall.abi"

local cdef = require "ffi".cdef

cdef [[
typedef uint8_t sa_family_t;
]]

