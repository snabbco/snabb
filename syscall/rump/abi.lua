-- ffi abi definitions

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit

local hostabi = require "syscall.abi"

local abi = {}
for k, v in pairs(hostabi) do abi[k] = v end
abi.rump = true
abi.host = abi.os
abi.os = "netbsd"
-- note you can run with abi.netbsd = {version = 7} here too
abi.netbsd = {version = 6}

-- testing the rump Linux ABI; not working yet
--abi.os = "linux"

return abi

