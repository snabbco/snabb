-- This sets up the table of C functions for BSD
-- We need to override functions that are versioned as the old ones selected otherwise

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local abi = require "syscall.abi"

local ffi = require "ffi"

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

-- was using __sysctl, but many sysctls provided by libc
C.sysctl = ffi.C.sysctl

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
C.utimes = ffi.C.__utimes50
C.posix_fadvise = ffi.C.__posix_fadvise50
C.lutimes = ffi.C.__lutimes50
C.futimes = ffi.C.__futimes50
C.getfh = ffi.C.__getfh30
C.kevent = ffi.C.__kevent50
C.mknod = ffi.C.__mknod50

C.gettimeofday = ffi.C.__gettimeofday50
C.settimeofday = ffi.C.__settimeofday50
C.adjtime = ffi.C.__adjtime50
C.setitimer = ffi.C.__setitimer50
C.getitimer = ffi.C.__getitimer50
C.clock_gettime = ffi.C.__clock_gettime50
C.clock_settime = ffi.C.__clock_settime50
C.clock_getres = ffi.C.__clock_getres50
C.nanosleep = ffi.C.__nanosleep50
C.timer_settime = ffi.C.__timer_settime50
C.timer_gettime = ffi.C.__timer_gettime50

-- use underlying syscall not wrapper
C.getcwd = ffi.C.__getcwd

C.sigaction = ffi.C.__libc_sigaction14 -- TODO not working I think need to use tramp_sigaction, see also netbsd pause()

return C

