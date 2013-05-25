-- this is a simple port of the fstest.c from buildrump.sh just to show it works
-- As we have only defined C so far not syscall it is pretty gross to use

local ffi = require "ffi"

function octal(s) return tonumber(s, 8) end

local S = require "syscall" -- your OS functions
local R = require "syscall.rump.init" -- rump kernel functions

S.setenv("RUMP_VERBOSE", "1")

R.module "vfs"
R.module "fs.kernfs"

R.init()

assert(R.mkdir("/kern", octal("0755"))) -- TODO allow numerical
assert(R.mount("kernfs", "/kern"))

local fd = assert(R.open("/kern/version"))

local str = assert(fd:read(nil, 1024))
print("kernel version is " .. str)
assert(fd:close())

assert(R.reboot(0, nil))

