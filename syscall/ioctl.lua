-- choose correct ioctls for OS

local abi = require "syscall.abi"

return require("syscall." .. abi.os .. ".ioctl")

