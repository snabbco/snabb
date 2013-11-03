-- This sets up the table of C functions
-- For OSX we hope we do not need many overrides

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(abi, c)

local ffi = require "ffi"

local voidp = ffi.typeof("void *")

local function void(x)
  return ffi.cast(voidp, x)
end

-- basically all types passed to syscalls are int or long, so we do not need to use nicely named types, so we can avoid importing t.
local int, long = ffi.typeof("int"), ffi.typeof("long")
local uint, ulong = ffi.typeof("unsigned int"), ffi.typeof("unsigned long")

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
  return C.syscall(getdirentries, int(fd), void(buf), int(len), void(basep))
end

return C

end

return {init = init}

