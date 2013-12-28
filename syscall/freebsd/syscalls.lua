-- FreeBSD specific syscalls

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

function S.reboot(howto) return C.reboot(c.RB[howto]) end

function S.bindat(dirfd, sockfd, addr, addrlen)
  local saddr = pt.sockaddr(addr)
  return retbool(C.bindat(c.AT_FDCWD[dirfd], getfd(sockfd), saddr, addrlen or #addr))
end
function S.connectat(dirfd, sockfd, addr, addrlen)
  local saddr = pt.sockaddr(addr)
  return retbool(C.connectat(c.AT_FDCWD[dirfd], getfd(sockfd), saddr, addrlen or #addr))
end

local function isptmaster(fd) return fd:ioctl("TIOCPTMASTER") end
S.grantpt = isptmaster
S.unlockpt = isptmaster

local SPECNAMELEN = 63

function S.ptsname(fd)
  local ok, err = isptmaster(fd)
  if not ok then return nil, err end
  local buf = t.buffer(SPECNAMELEN)
  local fgn = t.fiodgname_arg{buf = buf, len = SPECNAMELEN}
  local ok, err = fd:ioctl("FIODGNAME", fgn)
  if not ok then return nil, err end
  return "/dev/" .. ffi.string(buf)
end

return S

end

