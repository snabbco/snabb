-- This sets up the table of C functions
-- For OSX we hope we do not need many overrides

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit

local function init(abi, c, types)

local ffi = require "ffi"

local t, pt, s = types.t, types.pt, types.s

local function inlibc_fn(k) return ffi.C[k] end

local C = setmetatable({}, {
  __index = function(C, k)
    if pcall(inlibc_fn, k) then
      C[k] = ffi.C[k] -- add to table, so no need for this slow path again
      return C[k]
    else
      return nil
    end
  end
})

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

