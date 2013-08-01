local oldassert = assert
local function assert(cond, s)
  return oldassert(cond, tostring(s))
end

local S = require "syscall" -- your OS functions

assert(S.abi.le, "This test requires little endian machine")

S.setenv("RUMP_VERBOSE", "1")

local R = require "syscall.rump.init".init("vfs", "fs.sysvbfs", "dev", "dev.disk")

local dev = "/de-vice"

assert(R.rump.etfs_register(dev, "buildrump.sh/tests/sysvbfs_le.img", "blk"))

local stat = assert(R.stat(dev))

assert(R.mkdir("/mnt", "0755"))
assert(R.mount("sysvbfs", "/mnt", "rdonly", dev))

local fd = assert(R.open("/mnt/README", "rdonly"))

local str = assert(fd:read())

assert(str == "Is that a small file system in your pocket or aren't you happy to see me?\n")

assert(fd:close())

assert(R.unmount("/mnt"))

