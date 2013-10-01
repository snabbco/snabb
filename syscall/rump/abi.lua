-- ffi abi definitions

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math

local hostabi = require "syscall.abi"

local abi = {}
for k, v in pairs(hostabi) do abi[k] = v end
abi.rump = true
abi.host = abi.os
abi.os = "netbsd"
-- note you can run with abi.netbsd = {version = 7} here too
abi.netbsd = {version = 6}

abi.types = "netbsd" -- you can set to Linux, or monkeypatch (see tests)

return abi

