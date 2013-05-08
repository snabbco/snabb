-- choose correct constants for OS

local abi = require "syscall.abi"

return require(abi.os .. ".constants")

