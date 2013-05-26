
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

require "syscall.netbsd.ffitypes".init(abi)

local c = require "syscall.netbsd.constants"
local errors = require "syscall.netbsd.errors"

local ostypes = require "syscall.netbsd.types"

local types
if abi.host == "netbsd" then
  -- if running rump on netbsd just return normal NetBSD types
  -- note that we get these by calling the whole thing so we do not get metatype redefinition erros
  types = require "syscall".types
else
  -- running on another OS
  types = require "syscall.rump.types".init(abi, c, errors, ostypes)
end

local C = require "syscall.rump.c".init(abi, c, types)
local ioctl = require("syscall.netbsd.ioctl")(abi, s)
local fcntl = require("syscall.netbsd.fcntl")(abi, c, types)

c.IOCTL = ioctl -- cannot put in S, needed for tests, cannot be put in c earlier due to deps

local S = require "syscall.syscalls".init(abi, c, C, types, ioctl, fcntl)

local function module(s)
  s = string.gsub(s, "%.", "_")
  ffi.load("rump" .. s, true)
end

S.abi, S.c, S.C, S.types, S.t = abi, c, C, types, types.t -- add to main table returned

-- add methods
S = require "syscall.methods".init(S)

-- add feature tests
S.features = require "syscall.features".init(S)

S.init = rump.rump_init
S.module = module

return S

