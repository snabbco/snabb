-- OSX specific syscalls

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local abi = require "syscall.abi"

return function(S, hh, c, C, types)

local ret64, retnum, retfd, retbool, retptr = hh.ret64, hh.retnum, hh.retfd, hh.retbool, hh.retptr

local ffi = require "ffi"
local errno = ffi.errno

local h = require "syscall.helpers"

local istype, mktype, getfd = h.istype, h.mktype, h.getfd

local t, pt, s = types.t, types.pt, types.s

-- TODO lutimes is implemented using setattrlist(2) in OSX

function S.grantpt(fd) return S.ioctl(fd, "TIOCPTYGRANT") end
function S.unlockpt(fd) return S.ioctl(fd, "TIOCPTYUNLK") end
function S.ptsname(fd)
  local buf = t.buffer(128)
  local ok, err = S.ioctl(fd, "TIOCPTYGNAME", buf)
  if not ok then return nil, err end
  return ffi.string(buf)
end

function S.mach_absolute_time() return C.mach_absolute_time() end

return S

end

