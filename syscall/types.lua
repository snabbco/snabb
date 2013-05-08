-- choose correct types for OS

-- TODO many are common and can be shared here

local abi = require "syscall.abi"

return require(abi.os .. ".types")

