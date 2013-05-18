-- define C functions for rump

local ffi = require "ffi"

local rump = ffi.load("rump")

require "syscall.rump.ffifunctions"

local C = {
  mkdir = rump.rump___sysimpl_mkdir,
  mount = rump.rump___sysimpl_mount50,
  open = rump.rump___sysimpl_open,
  read = rump.rump___sysimpl_read,
  close = rump.rump___sysimpl_close,
  reboot = rump.rump___sysimpl_reboot,
}

return C


