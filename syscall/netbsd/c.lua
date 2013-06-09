-- This sets up the table of C functions for BSD
-- We need to override functions that are versioned as the old ones selected otherwise

local function init(abi, c, types)

local ffi = require "ffi"

local t, pt, s = types.t, types.pt, types.s

local C = setmetatable({}, {__index = ffi.C})

C.mount = function(fstype, dir, flags, data, data_len)
  return C.syscall(c.SYS.mount50, fstype, dir, t.int(flags), pt.void(data), t.size(data_len))
end

C.stat = function(path, buf)
  return C.syscall(c.SYS.stat50, pt.void(path), pt.void(buf))
end

C.fstat = function(fd, path, buf)
  return C.syscall(c.SYS.fstat50, t.int(fd), pt.void(path), pt.void(buf))
end

C.lstat = function(path, buf)
  return C.syscall(c.SYS.lstat50, pt.void(path), pt.void(buf))
end

C.getcwd = function(buf, size)
  return C.syscall(c.SYS.__getcwd, pt.void(buf), t.size(size))
end

return C

end

return {init = init}

