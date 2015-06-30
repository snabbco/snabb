-- This simply returns ABI information
-- Makes it easier to substitute for non-ffi solution, eg to run tests

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local ffi = require "ffi"

local function inlibc_fn(k) return ffi.C[k] end

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

if (abi.arch == "mips" or abi.arch == "mipsel") then abi.mipsabi = "o32" end -- only one supported now

if abi.os == "bsd" or abi.os == "osx" then abi.bsd = true end -- some shared BSD functionality

-- Xen generally behaves like NetBSD, but our tests need to do rump-like setup; bit of a hack
ffi.cdef[[
  int __ljsyscall_under_xen;
]]
if pcall(inlibc_fn, "__ljsyscall_under_xen") then abi.xen = true end

-- BSD detection
-- OpenBSD doesn't have sysctlbyname
-- The good news is every BSD has utsname
-- The bad news is that on FreeBSD it is a legacy version that has 32 byte unless you use __xuname
-- fortunately sysname is first so we can use this value
if not abi.xen and not abi.rump and abi.os == "bsd" then
  ffi.cdef [[
  struct _utsname {
  char    sysname[256];
  char    nodename[256];
  char    release[256];
  char    version[256];
  char    machine[256];
  };
  int uname(struct _utsname *);
  ]]
  local uname = ffi.new("struct _utsname")
  ffi.C.uname(uname)
  abi.os = ffi.string(uname.sysname):lower()
  abi.uname = uname
end

-- rump params
abi.host = abi.os -- real OS, used for rump at present may change this
abi.types = "netbsd" -- you can set to linux, or monkeypatch (see tests) to use Linux types

return abi
