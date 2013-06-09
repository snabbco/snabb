-- this is a simple port of the fstest.c from buildrump.sh just to show it works

-- version with no loading of S to check for accidental leakage

local R = require "syscall.rump.init" -- rump kernel functions

R.rump.init("vfs", "fs.kernfs")

print("init")

assert(R.mkdir("/kern", "0755"))

print("mkdir")

assert(R.mount("kernfs", "/kern"))

print("mount")

local fd = assert(R.open("/kern/version"))

print("open")

local str = assert(fd:read(nil, 1024))
print("kernel version is " .. str)
assert(fd:close())

assert(R.reboot())

