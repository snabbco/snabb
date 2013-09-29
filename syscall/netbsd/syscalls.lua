-- BSD specific syscalls

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit

return function(S, hh, abi, c, C, types, ioctl)

local ffi = require "ffi"

local t, pt, s = types.t, types.pt, types.s

local istype, mktype, getfd = hh.istype, hh.mktype, hh.getfd
local ret64, retnum, retfd, retbool, retptr, retiter = hh.ret64, hh.retnum, hh.retfd, hh.retbool, hh.retptr, hh.retiter

local helpers = require "syscall.helpers"

function S.accept(sockfd, flags, addr, addrlen) -- TODO add support for signal mask that paccept has
  addr = addr or t.sockaddr_storage()
  addrlen = addrlen or t.socklen1(addrlen or #addr)
  local saddr = pt.sockaddr(addr)
  local ret
  if not flags
    then ret = C.accept(getfd(sockfd), saddr, addrlen)
    else ret = C.paccept(getfd(sockfd), saddr, addrlen, nil, c.SOCK[flags])
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
  ptyfs = t.ptyfs_args,
  procfs = t.procfs_args,
}

-- TODO allow putting data in same table rather than nested table?
function S.mount(filesystemtype, dir, flags, data, datalen)
  local str, str2
  if type(data) == "string" then -- common case, for ufs etc
    str = data
    data = {fspec = pt.char(str)}
  end
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

-- this is identical to Linux, may be able to share TODO find out how OSX works
function S.getdents(fd, buf, size)
  size = size or 4096 -- may have to be equal to at least block size of fs
  buf = buf or t.buffer(size)
  local ret = C.getdents(getfd(fd), buf, size)
  if ret == -1 then return nil, t.error() end
  return t.dirents(buf, ret)
end

function S.utimensat(dirfd, path, ts, flags)
  if ts then ts = t.timespec2(ts) end
  return retbool(C.utimensat(c.AT_FDCWD[dirfd], path, ts, c.AT_SYMLINK_NOFOLLOW[flags]))
end

function S.futimens(fd, ts)
  if ts then ts = t.timespec2(ts) end
  return retbool(C.futimens(getfd(fd), ts))
end

function S.revoke(path) return retbool(C.revoke(path)) end
function S.chflags(path, flags) return retbool(C.chflags(path, c.CHFLAGS[flags])) end
function S.lchflags(path, flags) return retbool(C.lchflags(path, c.CHFLAGS[flags])) end
function S.fchflags(fd, flags) return retbool(C.fchflags(getfd(fd), c.CHFLAGS[flags])) end
function S.fchroot(fd) return retbool(C.fchroot(getfd(fd))) end
function S.pathconf(path, name) return retnum(C.pathconf(path, c.PC[name])) end
function S.fpathconf(fd, name) return retnum(C.fpathconf(getfd(fd), c.PC[name])) end
function S.fsync_range(fd, how, start, length) return retbool(C.fsync_range(getfd(fd), c.FSYNC[how], start, length)) end
function S.lchmod(path, mode) return retbool(C.lchmod(path, c.MODE[mode])) end

function S.getvfsstat(flags, buf, size) -- note order of args as usually leave buf empty
  flags = c.VFSMNT[flags or "WAIT"] -- default not zero
  if not buf then
    local n, err = C.getvfsstat(nil, 0, flags)
    if not n then return nil, err end
    --buf = t.statvfss(n) -- TODO define
    size = s.statvfs * n
  end
  size = size or #buf
  local n, err = C.getvfsstat(buf, size, flags)
  if not n then return nil, err end
  return buf -- TODO need type with number
end

-- TODO when we define this for osx can go in common code (curently defined in libc.lua)
function S.getcwd(buf, size)
  size = size or c.PATH_MAX
  buf = buf or t.buffer(size)
  local ret = C.getcwd(buf, size)
  if ret == -1 then return nil, t.error() end
  return ffi.string(buf)
end

-- pty functions
function S.grantpt(fd) return S.ioctl(fd, "TIOCGRANTPT") end
function S.unlockpt(fd) return 0 end
function S.ptsname(fd)
  local pm, err = S.ioctl(fd, "TIOCPTSNAME")
  if not pm then return nil, err end
  return ffi.string(pm.sn)
end
function S.tcgetattr(fd) return S.ioctl(fd, "TIOCGETA") end
local tcsets = {
  [c.TCSA.NOW]   = "TIOCSETA",
  [c.TCSA.DRAIN] = "TIOCSETAW",
  [c.TCSA.FLUSH] = "TIOCSETAF",
}
function S.tcsetattr(fd, optional_actions, tio)
  -- TODO also implement TIOCSOFT, which needs to make a modified copy of tio
  local inc = c.TCSA[optional_actions]
  return S.ioctl(fd, tcsets[inc], tio)
end
function S.tcsendbreak(fd, duration)
  local ok, err = S.ioctl(fd, "TIOCSBRK")
  if not ok then return nil, err end
  S.nanosleep(0.4) -- NetBSD just does constant time
  local ok, err = S.ioctl(fd, "TIOCCBRK")
  if not ok then return nil, err end
  return true
end
function S.tcdrain(fd)
  return S.ioctl(fd, "TIOCDRAIN")
end
function S.tcflush(fd, com)
  return S.ioctl(fd, "TIOCFLUSH", c.TCFLUSH[com]) -- while defined as FREAD, FWRITE, values same
end
local posix_vdisable = helpers.octal "0377" -- move to constants?
function S.tcflow(fd, action)
  action = c.TCFLOW[action]
  if action == c.TCFLOW.OOFF then return S.ioctl(fd, "TIOCSTOP") end
  if action == c.TCFLOW.OON then return S.ioctl(fd, "TIOCSTART") end
  if action ~= c.TCFLOW.ION and action ~= c.TCFLOW.IOFF then return nil end
  local term, err = S.tcgetattr(fd)
  if not term then return nil, err end
  local cc
  if action == c.TCFLOW.IOFF then cc = term.VSTOP else cc = term.VSTART end
  if cc ~= posix_vdisable and not S.write(fd, t.uchar1(cc), 1) then return nil end
  return true
end
function S.tcgetsid(fd) return S.ioctl(fd, "TIOCGSID") end

function S.kqueue(flags) return retfd(C.kqueue1(c.O[flags])) end
function S.kevent(kq, changelist, eventlist, timeout)
  if timeout then timeout = mktype(t.timespec, timeout) end
  local changes, changecount = nil, 0
  if changelist then changes, changecount = changelist.kev, changelist.count end
  if eventlist then
    return retiter(C.kevent(getfd(kq), changes, changecount, eventlist.kev, eventlist.count, timeout), eventlist.kev)
  end
  return retnum(C.kevent(getfd(kq), changes, changecount, nil, 0, timeout))
end

-- TODO this is the same as ppoll other than if timeout is modified, which Linux syscall but not libc does; could merge
function S.pollts(fds, timeout, set)
  if timeout then timeout = mktype(t.timespec, timeout) end
  if set then set = mktype(t.sigset, set) end
  return retnum(C.pollts(fds.pfd, #fds, timeout, set))
end

return S

end

