-- choose correct ioctls for OS

local abi = require "syscall.abi"
local s = require "syscall.types".s

return require("syscall." .. abi.os .. ".ioctl").init(abi, s)

