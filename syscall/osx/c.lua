-- This sets up the table of C functions
-- For OSX we hope we do not need many overrides

local function init(abi, c, types)

local ffi = require "ffi"

local C = setmetatable({}, {__index = ffi.C})

-- new stat structure, else get legacy one; could use syscalls instead
C.stat = C.stat64
C.fstat = C.fstat64
C.lstat = C.lstat64
C.getdirentries = C.getdirentries64

return C

end

return {init = init}

