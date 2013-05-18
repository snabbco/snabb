-- ffi definitions of BSD types

local abi = require "syscall.abi"

local cdef = require "ffi".cdef

local netbsd = require "syscall.netbsd.ffitypes-common"

netbsd.init(false) -- not rump kernel


