-- choose correct ioctls for OS

local abi = require "syscall.abi"

return require(abi.os .. ".ioctl")

