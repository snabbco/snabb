-- this puts everything into one table ready to use

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit

local function init(abi)

require "syscall.ffitypes"
require("syscall." .. (abi.types or abi.os) .. ".ffitypes").init(abi)

if not abi.rump then require "syscall.ffifunctions" end

local c = require("syscall." .. (abi.types or abi.os) .. ".constants")
local errors = require("syscall." .. abi.os .. ".errors")
local ostypes = require("syscall." .. (abi.types or abi.os) .. ".types")

local ostypes2
if abi.types == "linux" then ostypes2 = require "syscall.rump.linux" end

local types = require "syscall.types".init(abi, c, errors, ostypes, ostypes2)

local t, pt, s = types.t, types.pt, types.s

local cmod
if abi.rump then cmod = "syscall.rump.c" else cmod = "syscall." .. abi.os .. ".c" end
local C = require(cmod).init(abi, c, types)

if abi.rump and abi.types == "linux" then abi.os = "linux" end -- after this, we pretend to be Linux

local ioctl = require("syscall." .. abi.os .. ".ioctl").init(abi, types)
local fcntl = require("syscall." .. abi.os .. ".fcntl").init(abi, c, types)

local S = require "syscall.syscalls".init(abi, c, C, types, ioctl, fcntl)

c.IOCTL = ioctl -- cannot put in S, needed for tests, cannot be put in c earlier due to deps

S.abi, S.c, S.C, S.types, S.t = abi, c, C, types, t -- add to main table returned

-- add compatibility code
S = require "syscall.compat".init(S)

-- add functions from libc
S = require "syscall.libc".init(S)

-- add methods
S = require "syscall.methods".init(S)

-- add feature tests
S.features = require "syscall.features".init(S)

-- link in fcntl
S.__fcntl = fcntl

-- add utils
S.util = require "syscall.util".init(S)

if abi.os == "linux" then
  S.cgroup = require "syscall.linux.cgroup".init(S)
  S.nl = require "syscall.linux.nl".init(S)
  -- TODO add the other Linux specific modules here
end

return S

end

return {init = init}

