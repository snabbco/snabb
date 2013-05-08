-- choose correct syscalls for OS

local abi = require "syscall.abi"

return require(abi.os .. ".syscalls")

