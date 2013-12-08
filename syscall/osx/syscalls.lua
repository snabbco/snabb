-- OSX specific syscalls

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

return function(S, hh, abi, c, C, types, ioctl)

local ffi = require "ffi"
local errno = ffi.errno

local istype, mktype, getfd = hh.istype, hh.mktype, hh.getfd
local ret64, retnum, retfd, retbool, retptr = hh.ret64, hh.retnum, hh.retfd, hh.retbool, hh.retptr

local t, pt, s = types.t, types.pt, types.s

function S.accept(sockfd, flags, addr, addrlen)
  assert(not flags, "TODO add accept flags emulation") -- TODO emulate netbsd paccept/Linux accept4
  addr = addr or t.sockaddr_storage()
  addrlen = addrlen or t.socklen1(addrlen or #addr)
  local saddr = pt.sockaddr(addr)
  local ret, err = C.accept(getfd(sockfd), saddr, addrlen)
  if ret == -1 then return nil, t.error(err or errno()) end
  return {fd = t.fd(ret), addr = t.sa(addr, addrlen[0])}
end

function S.utimes(filename, ts)
  if ts then ts = t.timeval2(ts) end
  return retbool(C.utimes(filename, ts))
end

function S.futimes(fd, ts)
  if ts then ts = t.timeval2(ts) end
  return retbool(C.futimes(getfd(fd), ts))
end

-- TODO lutimes is implemented using setattrlist(2) in OSX

function S.getdirentries(fd, buf, size, basep)
  size = size or 4096
  buf = buf or t.buffer(size)
  local ret, err = C.getdirentries(getfd(fd), buf, size, basep)
  if ret == -1 then return nil, t.error(err or errno()) end
  return t.dirents(buf, ret)
end


return S

end

