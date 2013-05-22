-- choose correct types for OS

-- this just calls the default types code (types2) with the normal defaults
-- this is so special use cases like rump kernel can override default behaviour

require "syscall.ffitypes"

local abi = require "syscall.abi"
local errors = require "syscall.errors"
local c = require "syscall.constants"

local init = require "syscall.types2".init

return init(abi, errors, c)

