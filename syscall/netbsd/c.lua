-- This sets up the table of C functions
-- For BSD we hope we do not need many overrides
-- however stat appears to be "fixed" up in libc to return incorrect results TODO why?

local ffi = require "ffi"

local types = require "syscall.types"
local t, pt, s = types.t, types.pt, types.s

local C = setmetatable({}, {__index = ffi.C})

-- TODO could move to constants
local stat50 = 439
local fstat50 = 440
local lstat50 = 441

C.stat = function(path, buf)
  return C.syscall(stat50, pt.void(path), pt.void(buf))
end

C.fstat = function(fd, path, buf)
  return C.syscall(fstat50, t.int(fd), pt.void(path), pt.void(buf))
end

C.lstat = function(path, buf)
  return C.syscall(lstat50, pt.void(path), pt.void(buf))
end

return C

