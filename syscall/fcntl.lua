-- choose OS specific fcntl code

local abi = require "syscall.abi"

return require("syscall." .. abi.os .. ".fcntl")


