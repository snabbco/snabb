-- choose correct types for OS

local abi = require "syscall.abi"

return require(abi.os .. ".types")

