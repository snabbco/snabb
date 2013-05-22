-- types for rump kernel

abi = require "syscall.abi"

if abi.os == "netbsd" then
  return require "syscall.types" -- if running rump on netbsd just return normal types
end

-- running on another OS

local errors = require "syscall.netbsd.errors"
local c = require "syscall.netbsd.constants"

return require "syscall.types2"


