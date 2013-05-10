-- choose correct types for OS

-- these are either simple ffi types or ffi metatypes for the kernel types
-- plus some Lua metatables for types that cannot be sensibly done as Lua types eg arrays, integers

-- note that some types will be overridden, eg default fd type will have metamethods added

local ffi = require "ffi"
local bit = require "bit"

require "syscall.ffitypes"

local h = require "syscall.helpers"

local ntohl, ntohl, ntohs, htons = h.ntohl, h.ntohl, h.ntohs, h.htons

local c = require "syscall.constants"

local abi = require "syscall.abi"

local C = ffi.C -- for inet_pton etc, TODO due to be replaced with Lua

local types = {}

local t, pt, s, ctypes = {}, {}, {}, {} -- types, pointer types and sizes tables
types.t, types.pt, types.s, types.ctypes = t, pt, s, ctypes

--helpers
local function ptt(tp)
  local ptp = ffi.typeof(tp .. " *")
  return function(x) return ffi.cast(ptp, x) end
end

local function addtype(name, tp, mt)
  if mt then t[name] = ffi.metatype(tp, mt) else t[name] = ffi.typeof(tp) end
  ctypes[tp] = t[name]
  pt[name] = ptt(tp)
  s[name] = ffi.sizeof(t[name])
end

local function lenfn(tp) return ffi.sizeof(tp) end

local lenmt = {__len = lenfn}

-- generic types

local addtypes = {
  char = "char",
  uchar = "unsigned char",
  int = "int",
  uint = "unsigned int",
  int16 = "int16_t",
  uint16 = "uint16_t",
  int32 = "int32_t",
  uint32 = "uint32_t",
  int64 = "int64_t",
  uint64 = "uint64_t",
  long = "long",
  ulong = "unsigned long",
  uintptr = "uintptr_t",
  intptr = "intptr_t",
  size = "size_t",
  mode = "mode_t",
  dev = "dev_t",
  loff = "loff_t",
  pid = "pid_t",
  sa_family = "sa_family_t",
}

local addstructs = {
}

for k, v in pairs(addtypes) do addtype(k, v) end
for k, v in pairs(addstructs) do addtype(k, v, lenmt) end

-- include OS specific types
local hh = {ptt = ptt, addtype = addtype, lenfn = lenfn, lenmt = lenmt}

types = require(abi.os .. ".types")(types, hh)

return types

