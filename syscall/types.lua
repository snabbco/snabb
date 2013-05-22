-- choose correct types for OS

-- this just calls the default types code (types2) with the normal defaults
-- this is so special use cases like rump kernel can override default behaviour

require "syscall.ffitypes"

local abi = require "syscall.abi"
local c = require "syscall.constants"
local errors = require "syscall.errors"
local ostypes = require("syscall." .. abi.os .. ".types")

local init = require "syscall.types2".init

return init(abi, c, errors, ostypes)

