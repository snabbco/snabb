-- This simply returns ABI information
-- Makes it easier to substitute for non-ffi solution, eg to run tests

local ffi = require "ffi"

local abi = {
  arch = ffi.arch, -- ppc, x86, arm, x64
  abi32 = ffi.abi("32bit"), -- boolean
  abi64 = ffi.abi("64bit"), -- boolean
  le = ffi.abi("le"), -- boolean
  be = ffi.abi("be"), -- boolean
  eabi = ffi.abi("eabi"), -- boolean
  os = ffi.os:lower(), -- bsd, osx, linux
}

-- At the moment we only support NetBSD but do not attempt to detect it
-- If you want to support eg FreeBSD then will have to detect it

if abi.os == "bsd" then abi.os = "netbsd" end

-- Makes no difference to us I believe
if abi.arch == "ppcspe" then abi.arch = "ppc" end

return abi

