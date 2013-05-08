-- choose correct ffi functions for OS

-- TODO many are common and can be shared here

local abi = require "syscall.abi"

require(abi.os .. ".ffifunctions")

local cdef = require "ffi".cdef

require "syscall.ffitypes"

-- common functions

cdef[[
int close(int fd);
int open(const char *pathname, int flags, mode_t mode);
]]

