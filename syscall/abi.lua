-- This simply returns ABI information
-- Makes it easier to substitute for non-ffi solution, eg to run tests

local ffi = require "ffi"

return {
  architecture = ffi.arch, -- ppc, x86, arm, x64
  abi32 = ffi.abi("32bit"), -- boolean
  abi64 = ffi.abi("64bit"), -- boolean
  le = ffi.abi("le"), -- boolean
  be = ffi.abi("be"), -- boolean
}

