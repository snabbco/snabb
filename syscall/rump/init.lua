
-- test only

local ffi = require "ffi"

local rumpuser = ffi.load("rumpuser")
local rump_syms = ffi.load("rump")

ffi.cdef[[
int rump_init(void);
]]

rump = {
  init = rump_syms.rump_init,
}

return rump

