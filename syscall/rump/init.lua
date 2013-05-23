
-- This mirrors syscall.lua, but some differences

local ffi = require "ffi"

local rumpuser = ffi.load("rumpuser")
local rump = ffi.load("rump")

ffi.cdef[[
int rump_init(void);
]]

if ffi.os == "netbsd" then
  require "syscall.netbsd.ffitypes" -- with rump on NetBSD the types are the same
else
  require "syscall.netbsd.common.ffitypes".init(true) -- rump = true
end

local C = require "syscall.rump.c"
local types = require "syscall.rump.types"

local function module(s)
  s = string.gsub(s, "%.", "_")
  ffi.load("rump" .. s, true)
end

local S = {}

S.init = rump.rump_init
S.module = module
S.C = C
S.types = types

return S

