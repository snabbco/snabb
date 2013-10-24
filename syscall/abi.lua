-- This simply returns ABI information
-- Makes it easier to substitute for non-ffi solution, eg to run tests

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math

local ffi = require "ffi"

local abi = {
  arch = ffi.arch, -- ppc, x86, arm, x64, mips
  abi32 = ffi.abi("32bit"), -- boolean
  abi64 = ffi.abi("64bit"), -- boolean
  le = ffi.abi("le"), -- boolean
  be = ffi.abi("be"), -- boolean
  eabi = ffi.abi("eabi"), -- boolean
  os = ffi.os:lower(), -- bsd, osx, linux
}

-- Makes no difference to us I believe
if abi.arch == "ppcspe" then abi.arch = "ppc" end

-- At the moment we only support NetBSD but do not attempt to detect it
-- If you want to support eg FreeBSD then will have to detect it

if abi.os == "bsd" then abi.os = "netbsd" end

if abi.os == "netbsd" then -- we default to version 6, as stable target; you can monkeypatch to 7 which is also supported
  abi.netbsd = {version = 6}
end

-- perhaps this should be in test suite not here
local function inlibc_fn(k) return ffi.C[k] end

ffi.cdef[[
  int __ljsyscall_under_xen;
]]

-- Xen generally behaves like NetBSD, but our tests need to do rump-like setup
if pcall(inlibc_fn, "__ljsyscall_under_xen") then abi.xen = true end

return abi

