-- choose correct ffi types for OS

local abi = require "syscall.abi"

require "syscall.ffitypes-common"

require("syscall." .. abi.os .. ".ffitypes")

