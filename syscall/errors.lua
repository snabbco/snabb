-- error messages

local abi = require "syscall.abi"

return require("syscall." .. abi.os .. ".errors")

