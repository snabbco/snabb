-- choose correct syscalls for OS, plus shared calls

local ffi = require "ffi"
local bit = require "bit"

local c = require "syscall.constants"
local C = require "syscall.c"
local types = require "syscall.types"
local abi = require "syscall.abi"

local t, pt, s = types.t, types.pt, types.s

local S = {}

-- helpers
local zeropointer = pt.void(0)
local errpointer = pt.void(-1)

local function getfd(fd)
  if type(fd) == "number" or ffi.istype(t.int, fd) then return fd end
  return fd:getfd()
end

-- makes code tidier
local function istype(tp, x) if ffi.istype(tp, x) then return x else return false end end

-- even simpler version coerces to type
local function mktype(tp, x) if ffi.istype(tp, x) then return x else return tp(x) end end

-- return helpers.

-- straight passthrough, only needed for real 64 bit quantities. Used eg for seek (file might have giant holes!)
local function ret64(ret)
  if ret == t.uint64(-1) then return nil, t.error() end
  return ret
end

local function retnum(ret) -- return Lua number where double precision ok, eg file ops etc
  ret = tonumber(ret)
  if ret == -1 then return nil, t.error() end
  return ret
end

local function retfd(ret)
  if ret == -1 then return nil, t.error() end
  return t.fd(ret)
end

-- used for no return value, return true for use of assert
local function retbool(ret)
  if ret == -1 then return nil, t.error() end
  return true
end

-- used for pointer returns, -1 is failure
local function retptr(ret)
  if ret == errpointer then return nil, t.error() end
  return ret
end

-- generic system calls
function S.open(pathname, flags, mode) return retfd(C.open(pathname, c.O[flags], c.MODE[mode])) end
function S.close(fd) return retbool(C.close(getfd(fd))) end
function S.chdir(path) return retbool(C.chdir(path)) end
function S.fchdir(fd) return retbool(C.fchdir(getfd(fd))) end
function S.mkdir(path, mode) return retbool(C.mkdir(path, c.MODE[mode])) end
function S.rmdir(path) return retbool(C.rmdir(path)) end
function S.unlink(pathname) return retbool(C.unlink(pathname)) end

-- now call OS specific for non-generic calls
local hh = {
  istype = istype, mktype = mktype , getfd = getfd,
  ret64 = ret64, retnum = retnum, retfd = retfd, retbool = retbool, retptr = retptr
}

local S = require(abi.os .. ".syscalls")(S, hh)

-- these functions are not always available as syscalls, so always define via other calls
function S.creat(pathname, mode) return S.open(pathname, "CREAT,WRONLY,TRUNC", mode) end

function S.nice(inc)
  local prio = S.getpriority("process", 0) -- this cannot fail with these args.
  local ok, err = S.setpriority("process", 0, prio + inc)
  if not ok then return nil, err end
  return S.getpriority("process", 0)
end

-- TODO setpgrp and similar - see the man page

return S

