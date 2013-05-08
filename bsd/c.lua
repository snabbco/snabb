-- This sets up the table of C functions
-- For BSD we hope we do not need many overrides

local ffi = require "ffi"

require "bsd.ffifunctions"

return ffi.C

