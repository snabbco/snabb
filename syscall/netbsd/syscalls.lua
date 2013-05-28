-- BSD specific syscalls

return function(S, hh, abi, c, C, types, ioctl)

local t, pt, s = types.t, types.pt, types.s

local istype, mktype, getfd = hh.istype, hh.mktype, hh.getfd
local ret64, retnum, retfd, retbool, retptr = hh.ret64, hh.retnum, hh.retfd, hh.retbool, hh.retptr

function S.accept(sockfd, flags, addr, addrlen) -- TODO add support for signal mask that paccept has
  addr = addr or t.sockaddr_storage()
  addrlen = addrlen or t.socklen1(addrlen or #addr)
  local ret
  if not flags
    then ret = C.accept(getfd(sockfd), addr, addrlen)
    else ret = C.paccept(getfd(sockfd), addr, addrlen, nil, c.SOCK[flags])
  end
  if ret == -1 then return nil, t.error() end
  return {fd = t.fd(ret), addr = t.sa(addr, addrlen[0])}
end

local mntstruct = {
  ffs = t.ufs_args,
  --nfs = t.nfs_args,
  --mfs = t.mfs_args,
  tmpfs = t.tmpfs_args,
  sysvbfs = t.ufs_args,
}

-- TODO allow putting data in same table rather than nested table?
function S.mount(filesystemtype, dir, flags, data, datalen)
  if type(data) == "string" then data = {fspec = pt.char(data)} end -- common case, for ufs etc
  if type(filesystemtype) == "table" then
    local t = filesystemtype
    dir = t.target or t.dir
    filesystemtype = t.type
    flags = t.flags
    data = t.data
    datalen = t.datalen
    if t.fspec then data = {fspec = pt.char(t.fspec)} end
  end
  if data then
    local tp = mntstruct[filesystemtype]
    if tp then data = mktype(tp, data) end
  else
    datalen = 0
  end
  local ret = C.mount(filesystemtype, dir, c.MNT[flags], data, datalen or #data)
  return retbool(ret)
end

function S.unmount(target, flags)
  return retbool(C.unmount(target, c.UMOUNT[flags]))
end

function S.mkfifo(pathname, mode) return retbool(C.mkfifo(pathname, c.S_I[mode])) end

function S.reboot(how, bootstr)
  return retbool(C.reboot(c.RB[how], bootstr))
end

return S

end

