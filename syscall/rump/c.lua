

local ffi = require "ffi"

local rumpuser = ffi.load("rumpuser")
local rump = ffi.load("rump")
local rumpvfs = ffi.load("rumpvfs", true)
local rumpfs_kernfs = ffi.load("rumpfs_kernfs", true)

ffi.cdef[[
int rump_init(void);
]]

require "syscall.rump.ffifunctions"

local C = {
  mkdir = rump.rump___sysimpl_mkdir,
  mount = rump.rump___sysimpl_mount50,
  open = rump.rump___sysimpl_open,
  read = rump.rump___sysimpl_read,
  close = rump.rump___sysimpl_close,
  reboot = rump.rump___sysimpl_reboot,
}

return {C = C, init = rump.rump_init}


