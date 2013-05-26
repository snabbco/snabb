-- ffi definitions of BSD types
-- calls the common definitions shared with rump kernel

local abi = require "syscall.abi"

require "syscall.netbsd.commonffitypes".init(abi)


