-- OSX specific syscalls

return function(S, hh, abi, c, C, types, ioctl)

local istype, mktype, getfd = hh.istype, hh.mktype, hh.getfd
local ret64, retnum, retfd, retbool, retptr = hh.ret64, hh.retnum, hh.retfd, hh.retbool, hh.retptr

local t, pt, s = types.t, types.pt, types.s

function S.mkfifo(pathname, mode) return retbool(C.mkfifo(pathname, c.S_I[mode])) end

function S.accept(sockfd, flags, addr, addrlen)
  assert(not flags, "TODO add accept flags emulation") -- TODO emulate netbsd paccept/Linux accept4
  addr = addr or t.sockaddr_storage()
  addrlen = addrlen or t.socklen1(addrlen or #addr)
  local ret = C.accept(getfd(sockfd), addr, addrlen)
  if ret == -1 then return nil, t.error() end
  return {fd = t.fd(ret), addr = t.sa(addr, addrlen[0])}
end

function S.pipe(flags)
  assert(not flags, "TODO add pipe flags emulation") -- TODO emulate flags from Linux pipe2
  local fd2 = t.int2()
  local ret = C.pipe(fd2)
  if ret == -1 then return nil, t.error() end
  return t.pipe(fd2)
end

return S

end

