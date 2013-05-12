-- This sets up the table of C functions
-- For OSX we hope we do not need many overrides

local ffi = require "ffi"

local types = require "syscall.types"
local t, pt, s = types.t, types.pt, types.s

local C = setmetatable({}, {__index = ffi.C})

-- new stat structure, else get legacy one
C.stat = C.stat64
C.fstat = C.fstat64
C.lstat = C.lstat64

return C

