-- This sets up the table of C functions for BSD
-- We need to override functions that are versioned as the old ones selected otherwise

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit

local function init(abi, c, types)

local ffi = require "ffi"

local t, pt, s = types.t, types.pt, types.s

local function inlibc_fn(k) return ffi.C[k] end

local C = setmetatable({}, {
  __index = function(C, k)
    if pcall(inlibc_fn, k) then
      C[k] = ffi.C[k] -- add to table, so no need for this slow path again
      return C[k]
    else
      return nil
    end
  end
})

C.mount = ffi.C.__mount50
C.stat = ffi.C.__stat50

C.fstat = function(fd, path, buf)
  return C.syscall(c.SYS.fstat50, t.int(fd), pt.void(path), pt.void(buf))
end

C.lstat = function(path, buf)
  return C.syscall(c.SYS.lstat50, pt.void(path), pt.void(buf))
end

C.getcwd = function(buf, size)
  return C.syscall(c.SYS.getcwd, pt.void(buf), t.size(size))
end

C.getdents = function(fd, buf, nbytes)
  return C.syscall(c.SYS.getdents30, t.int(fd), pt.void(buf), t.size(nbytes))
end

C.utimes = function(path, ts)
  return C.syscall(c.SYS.utimes50, pt.void(path), pt.void(ts))
end

C.futimes = function(fd, ts)
  return C.syscall(c.SYS.futimes50, t.int(fd), pt.void(ts))
end

C.lutimes = function(path, ts)
  return C.syscall(c.SYS.lutimes50, pt.void(path), pt.void(ts))
end

return C

end

return {init = init}

