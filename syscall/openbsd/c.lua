-- This sets up the table of C functions

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local abi = require "syscall.abi"

local ffi = require "ffi"

local voidp = ffi.typeof("void *")

local function void(x)
  return ffi.cast(voidp, x)
end

-- basically all types passed to syscalls are int or long, so we do not need to use nicely named types, so we can avoid importing t.
local int, long = ffi.typeof("int"), ffi.typeof("long")
local uint, ulong = ffi.typeof("unsigned int"), ffi.typeof("unsigned long")

local function inlibc_fn(k) return ffi.C[k] end

-- Syscalls that just return ENOSYS but are in libc. Note these might vary by version in future
local nosys_calls = {
  timer_create = true,
  timer_gettime = true,
  timer_settime = true,
  timer_delete = true,
  timer_getoverrun = true,
}

local C = setmetatable({}, {
  __index = function(C, k)
    if nosys_calls[k] then return nil end
    if pcall(inlibc_fn, k) then
      C[k] = ffi.C[k] -- add to table, so no need for this slow path again
      return C[k]
    else
      return nil
    end
  end
})

-- quite a few OpenBSD functions are weak aliases to __sys_ prefixed versions, some seem to resolve but others do not, odd.
-- this is true, but not needed on OpenBSD?
--C.futimes = ffi.C.__sys_futimes
--C.lutimes = ffi.C.__sys_lutimes
--C.utimes = ffi.C.__sys_utimes
--C.wait4 = ffi.C.__sys_wait4
--C.sigaction = ffi.C.__sys_sigaction

return C

