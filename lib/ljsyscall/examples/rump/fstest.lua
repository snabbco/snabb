-- this is a simple port of the fstest.c from buildrump.sh just to show it works

local S = require "syscall" -- your OS functions

S.setenv("RUMP_VERBOSE", "1")

local R = require "syscall.rump.init".init("vfs", "fs.kernfs")

assert(R.mkdir("/kern", "0755"))
assert(R.mount("kernfs", "/kern"))

local fd = assert(R.open("/kern/version"))

local str = assert(fd:read(nil, 1024))
print("kernel version is " .. str)
assert(fd:close())

assert(R.reboot())

