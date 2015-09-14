-- OpenBSD specific syscalls

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

-- pty functions, using libc ones for now; the libc ones use a database of name to dev mappings
function S.ptsname(fd)
  local name = ffi.C.ptsname(getfd(fd))
  if not name then return nil end
  return ffi.string(name)
end

function S.grantpt(fd) return retbool(ffi.C.grantpt(getfd(fd))) end
function S.unlockpt(fd) return retbool(ffi.C.unlockpt(getfd(fd))) end

return S

end

