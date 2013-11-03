-- This simply returns ABI information
-- Makes it easier to substitute for non-ffi solution, eg to run tests

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local ffi = require "ffi"

local abi = {
  arch = ffi.arch, -- ppc, x86, arm, x64, mips
  abi32 = ffi.abi("32bit"), -- boolean
  abi64 = ffi.abi("64bit"), -- boolean
  le = ffi.abi("le"), -- boolean
  be = ffi.abi("be"), -- boolean
  os = ffi.os:lower(), -- bsd, osx, linux
}

-- Makes no difference to us I believe
if abi.arch == "ppcspe" then abi.arch = "ppc" end

if abi.arch == "arm" and not ffi.abi("eabi") then error("only support eabi for arm") end

if abi.arch == "mips" then abi.mipsabi = "o32" end -- only one supported now

-- At the moment we only support NetBSD but do not attempt to detect it
-- If you want to support eg FreeBSD then will have to detect it

if abi.os == "bsd" then abi.os = "netbsd" end

-- you can use version 7 here
abi.netbsd = {version = 6}

-- rump params
abi.host = abi.os -- real OS, used for rump at present may change this

-- perhaps this should be in test suite not here
local function inlibc_fn(k) return ffi.C[k] end

ffi.cdef[[
  int __ljsyscall_under_xen;
]]

-- Xen generally behaves like NetBSD, but our tests need to do rump-like setup
if pcall(inlibc_fn, "__ljsyscall_under_xen") then abi.xen = true end

return abi

