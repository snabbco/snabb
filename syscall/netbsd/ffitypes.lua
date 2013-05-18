-- ffi definitions of BSD types

local abi = require "syscall.abi"

local cdef = require "ffi".cdef

local init = require "syscall.netbsd.ffitypes-common"

init(false) -- not rump kernel


