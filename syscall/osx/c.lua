-- This sets up the table of C functions
-- For OSX we hope we do not need many overrides

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit

local function init(abi, c, types)

local ffi = require "ffi"

local t, pt, s = types.t, types.pt, types.s

local C = setmetatable({}, {__index = ffi.C})

-- new stat structure, else get legacy one; could use syscalls instead
C.stat = C.stat64
C.fstat = C.fstat64
C.lstat = C.lstat64

local getdirentries = 196

function C.getdirentries(fd, buf, len, basep)
  return C.syscall(getdirentries, t.int(fd), pt.void(buf), t.int(len), pt.void(basep))
end

return C

end

return {init = init}

