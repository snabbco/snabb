-- choose correct ffi types for OS
-- TODO incorporate into ffifunctions and rename ffitypes-common to here?

local abi = require "syscall.abi"

require("syscall." .. abi.os .. ".ffitypes")

