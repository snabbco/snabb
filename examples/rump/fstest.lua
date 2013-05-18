-- this is a simple port of the fstest.c from buildrump.sh just to show it works
-- As we have only defined C so far not syscall it is pretty gross to use

local ffi = require "ffi"

function octal(s) return tonumber(s, 8) end

local rump = require "syscall.rump.init"

rump.module "vfs"
rump.module "fs.kernfs"

rump.init()

local C = require "syscall.rump.c"

local ok = C.mkdir("/kern", octal("0755"))
assert(ok == 0, "mkdir " .. ok)
local ok = C.mount("kernfs", "/kern", 0, nil, 0)
assert(ok == 0, "mount " .. ok)
local fd = C.open("/kern/version", 0, 0)
assert(fd >= 0, "open " .. fd)

local buf_t = ffi.typeof("char[?]")
local buf = buf_t(1024)
local n = C.read(fd, buf, 1024)
assert(n >= 0, "read " .. n)
print(ffi.string(buf, n))
local ok = C.close(fd)
assert(ok >= 0, "close " .. ok)
local ok = C.reboot(0, nil)
assert(ok == 0, "reboot " .. ok)
