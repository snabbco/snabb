-- This sets up the table of C functions for BSD
-- We need to override functions that are versioned as the old ones selected otherwise

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, print, error, assert, tonumber, tostring,
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

-- for NetBSD we use libc names not syscalls, as assume you will have libc linked or statically linked with all symbols exported.
-- this is so we can use NetBSD libc even where syscalls have been redirected to rump calls.

-- use new versions
C.mount = ffi.C.__mount50
C.stat = ffi.C.__stat50
C.fstat = ffi.C.__fstat50
C.lstat = ffi.C.__lstat50
C.getdents = ffi.C.__getdents30

-- use underlying syscall not wrapper
C.getcwd = ffi.C.__getcwd

return C

end

return {init = init}

