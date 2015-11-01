-- test tmpfs

local oldassert = assert
local function assert(cond, s)
  return oldassert(cond, tostring(s)) -- annoyingly, assert does not call tostring!
end

local helpers = require "syscall.helpers"

local R = require "syscall.rump.init".init("vfs", "fs.tmpfs")

print("init")

assert(R.mkdir("/tmp", "0700"))

print("mkdir")

local data = {ta_version = 1, ta_nodes_max=100, ta_size_max=1048576, ta_root_mode=helpers.octal("0700")}
assert(R.mount{dir="/tmp", type="tmpfs", data=data})

print("mount")

assert(R.chdir("/tmp"))

print("chdir")

assert(R.reboot())

