-- this file now does very little, just makes some modifications to syscalls
-- TODO want to try to remove everything from here

local abi = require "syscall.abi"

require("syscall." .. abi.os .. ".ffitypes").init(abi)
require "syscall.ffifunctions"

local c = require("syscall." .. abi.os .. ".constants")
local errors = require("syscall." .. abi.os .. ".errors")

local ostypes = require("syscall." .. abi.os .. ".types")

local types = require "syscall.types".init(abi, c, errors, ostypes, nil) -- nil is not rump

local t, pt, s = types.t, types.pt, types.s

local C = require("syscall." .. abi.os .. ".c").init(abi, c, types)
local ioctl = require("syscall." .. abi.os .. ".ioctl")(abi, types) -- TODO add init fn
local fcntl = require("syscall." .. abi.os .. ".fcntl")(abi, c, types) -- TODO add init fn

local S = require "syscall.syscalls".init(abi, c, C, types, ioctl, fcntl)

c.IOCTL = ioctl -- cannot put in S, needed for tests, cannot be put in c earlier due to deps

S.abi, S.c, S.C, S.types, S.t = abi, c, C, types, t -- add to main table returned

-- add functions from libc
S = require "syscall.libc".init(S)

-- add methods
S = require "syscall.methods".init(S)

-- add feature tests
S.features = require "syscall.features".init(S)

return S

