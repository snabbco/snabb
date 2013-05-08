-- choose correct C functions for OS

local abi = require "syscall.abi"

return require(abi.os .. ".c")

