-- choose correct C functions for OS

local abi = require "syscall.abi"

require "syscall.ffifunctions"

return require("syscall." .. abi.os .. ".c")

