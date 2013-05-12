-- This sets up the table of C functions
-- For BSD we hope we do not need many overrides

local ffi = require "ffi"

local types = require "syscall.types"
local t, pt, s = types.t, types.pt, types.s

local C = setmetatable({}, {__index = ffi.C})

-- SYS___stat50    439
C.stat = function(path, buf)
  return C.syscall(439, pt.void(path), pt.void(buf))
end

return C

