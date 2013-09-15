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

-- TODO if the NetBSD is not compiled with compat syscalls these will be missing, and we should use unversioned ones.

-- use new versions
C.mount = ffi.C.__mount50
C.stat = ffi.C.__stat50
C.fstat = ffi.C.__fstat50
C.lstat = ffi.C.__lstat50
C.getdents = ffi.C.__getdents30
C.socket = ffi.C.__socket30
C.select = ffi.C.__select50
C.pselect = ffi.C.__pselect50

C.fhopen = ffi.C.__fhopen40
C.fhstat = ffi.C.__fhstat50
C.fhstatvfs1 = ffi.C.__fhstatvfs140
C.utimes = ffi.C.utimes50
C.posix_fadvise = ffi.C.posix_fadvise50
C.lutimes = ffi.C.lutimes50
C.futimes = ffi.C.futimes50
C.getfh = ffi.C.getfh30

-- use underlying syscall not wrapper
C.getcwd = ffi.C.__getcwd

return C

end

return {init = init}

