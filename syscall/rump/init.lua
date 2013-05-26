
-- This mirrors syscall.lua, but some differences

local hostabi = require "syscall.abi"

local abi = {}
for k, v in pairs(hostabi) do abi[k] = v end
abi.rump = true
abi.host = abi.os
abi.os = "netbsd"

local ffi = require "ffi"

local rumpuser = ffi.load("rumpuser")
local rump = ffi.load("rump")

ffi.cdef[[
int rump_init(void);
]]

if abi.hostos == "netbsd" then
  require "syscall.netbsd.ffitypes" -- with rump on NetBSD the types are the same
else
  require "syscall.netbsd.commonffitypes".init(abi)
end

local c = require "syscall.netbsd.constants"
local errors = require "syscall.netbsd.errors"

local ostypes = require "syscall.netbsd.types"

local types
if abi.os == "netbsd" then
  -- if running rump on netbsd just return normal NetBSD types
  types = require "syscall.types".init(abi, c, errors, ostypes, nil)
else
  -- running on another OS
  types = require "syscall.rump.types".init(abi, c, errors, ostypes)
end

local C = require "syscall.rump.c".init(rumpabi, c, types)
local ioctl = require("syscall.netbsd.ioctl")(rumpabi, s)
local fcntl = require("syscall.netbsd.fcntl")(rumpabi, c, types)

c.IOCTL = ioctl -- cannot put in S, needed for tests, cannot be put in c earlier due to deps

local S = require "syscall.syscalls".init(rumpabi, c, C, types, ioctl, fcntl)

local function module(s)
  s = string.gsub(s, "%.", "_")
  ffi.load("rump" .. s, true)
end

S.abi, S.c, S.C, S.types, S.t = rumpabi, c, C, types, types.t -- add to main table returned

-- add methods
S = require "syscall.methods".init(S)

-- add feature tests
S.features = require "syscall.features".init(S)

S.init = rump.rump_init
S.module = module

return S

