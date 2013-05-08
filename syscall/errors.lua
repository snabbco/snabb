-- choose correct errors for OS

local abi = require "syscall.abi"

return require(abi.os .. ".errors")

