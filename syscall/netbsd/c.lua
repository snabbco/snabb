-- This sets up the table of C functions for BSD
-- We need to override functions that are versioned as the old ones selected otherwise

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local abi = require "syscall.abi"

local version = require "syscall.netbsd.version".version

local ffi = require "ffi"

local function inlibc_fn(k) return ffi.C[k] end

-- Syscalls that just return ENOSYS but are in libc.
local nosys_calls
if version == 6 then nosys_calls = {
  openat = true,
  faccessat = true,
  symlinkat = true,
  mkdirat = true,
  unlinkat = true,
  renameat = true,
  fstatat = true,
  fchmodat = true,
  fchownat = true,
  mkfifoat = true,
  mknodat = true,
}
end

local C = setmetatable({}, {
  __index = function(C, k)
    if nosys_calls and nosys_calls[k] then return nil end
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
C.mount = C.__mount50
C.stat = C.__stat50
C.fstat = C.__fstat50
C.lstat = C.__lstat50
C.getdents = C.__getdents30
C.socket = C.__socket30
C.select = C.__select50
C.pselect = C.__pselect50
C.fhopen = C.__fhopen40
C.fhstat = C.__fhstat50
C.fhstatvfs1 = C.__fhstatvfs140
C.utimes = C.__utimes50
C.posix_fadvise = C.__posix_fadvise50
C.lutimes = C.__lutimes50
C.futimes = C.__futimes50
C.getfh = C.__getfh30
C.kevent = C.__kevent50
C.mknod = C.__mknod50
C.pollts = C.__pollts50

C.gettimeofday = C.__gettimeofday50
C.settimeofday = C.__settimeofday50
C.adjtime = C.__adjtime50
C.setitimer = C.__setitimer50
C.getitimer = C.__getitimer50
C.clock_gettime = C.__clock_gettime50
C.clock_settime = C.__clock_settime50
C.clock_getres = C.__clock_getres50
C.nanosleep = C.__nanosleep50
C.timer_settime = C.__timer_settime50
C.timer_gettime = C.__timer_gettime50

-- use underlying syscall not wrapper
C.getcwd = C.__getcwd

C.sigaction = C.__libc_sigaction14 -- TODO not working I think need to use tramp_sigaction, see also netbsd pause()

return C

