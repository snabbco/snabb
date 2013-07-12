-- this is a hello world example

local S = require "syscall"

local stdout = S.stdout

stdout:write("Hello world from " .. S.abi.os .. "\n")

-- this requires rump kernel included...

local R = require "syscall.rump.init".init{"vfs", "fs.kernfs"}

assert(R.mkdir("/kern", "0755"))
assert(R.mount("kernfs", "/kern"))

local fd = assert(R.open("/kern/version"))

local str = assert(fd:read(nil, 1024))
print("hello world from " .. str .. "\n")
assert(fd:close())

S.exit("success")

