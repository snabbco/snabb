-- choose correct constants for OS

local abi = require "syscall.abi"

return require("syscall." .. abi.os .. ".constants")

