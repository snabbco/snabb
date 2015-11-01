-- BSD specific syscalls

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local abi = require "syscall.abi"

return function(S, hh, c, C, types)

local ffi = require "ffi"

local errno = ffi.errno

local t, pt, s = types.t, types.pt, types.s

local ret64, retnum, retfd, retbool, retptr, retiter = hh.ret64, hh.retnum, hh.retfd, hh.retbool, hh.retptr, hh.retiter

local h = require "syscall.helpers"
local istype, mktype, getfd = h.istype, h.mktype, h.getfd
local octal = h.octal

function S.paccept(sockfd, addr, addrlen, set, flags)
  if set then set = mktype(t.sigset, set) end
  local saddr = pt.sockaddr(addr)
  return retfd(C.paccept(getfd(sockfd), saddr, addrlen, set, c.SOCK[flags]))
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

function S.mount(fstype, dir, flags, data, datalen)
  local str
  if type(data) == "string" then -- common case, for ufs etc
    str = data
    data = {fspec = pt.char(str)}
  end
  if data then
    local tp = mntstruct[fstype]
    if tp then data = mktype(tp, data) end
  else
    datalen = 0
  end
  local ret = C.mount(fstype, dir, c.MNT[flags], data, datalen or #data)
  return retbool(ret)
end

function S.reboot(how, bootstr)
  return retbool(C.reboot(c.RB[how], bootstr))
end

function S.fsync_range(fd, how, start, length) return retbool(C.fsync_range(getfd(fd), c.FSYNC[how], start, length)) end

function S.getvfsstat(flags, buf, size) -- note order of args as usually leave buf empty
  flags = c.VFSMNT[flags or "WAIT"] -- default not zero
  if not buf then
    local n, err = C.getvfsstat(nil, 0, flags)
    if not n then return nil, t.error(err or errno()) end
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
  local ret, err = C.getcwd(buf, size)
  if ret == -1 then return nil, t.error(err or errno()) end
  return ffi.string(buf)
end

function S.kqueue1(flags) return retfd(C.kqueue1(c.O[flags])) end

-- TODO this is the same as ppoll other than if timeout is modified, which Linux syscall but not libc does; could merge
function S.pollts(fds, timeout, set)
  if timeout then timeout = mktype(t.timespec, timeout) end
  if set then set = mktype(t.sigset, set) end
  return retnum(C.pollts(fds.pfd, #fds, timeout, set))
end

function S.ktrace(tracefile, ops, trpoints, pid)
  return retbool(C.ktrace(tracefile, c.KTROP[ops], c.KTRFAC(trpoints, "V2"), pid))
end
function S.fktrace(fd, ops, trpoints, pid)
  return retbool(C.fktrace(getfd(fd), c.KTROP[ops], c.KTRFAC(trpoints, "V2"), pid))
end
function S.utrace(label, addr, len)
  return retbool(C.utrace(label, addr, len)) -- TODO allow string to be passed as addr?
end

-- pty functions
function S.grantpt(fd) return S.ioctl(fd, "TIOCGRANTPT") end
function S.unlockpt(fd) return 0 end
function S.ptsname(fd)
  local pm, err = S.ioctl(fd, "TIOCPTSNAME")
  if not pm then return nil, err end
  return ffi.string(pm.sn)
end

-- TODO we need to fix sigaction in NetBSD, syscall seems to have changed to sigaction_tramp
function S.pause() return S.select({}) end -- select on nothing forever

-- ksem functions. Not very well documented! You shoudl probably use pthreads in most cases
function S.ksem_init(value, semid)
  semid = semid or t.intptr1()
  local ok, err = C._ksem_init(value, semid)
  if not ok then return nil, t.error(err or errno()) end
  return semid[0]
end

function S.ksem_destroy(semid)
  return retbool(C._ksem_destroy(semid))
end

return S

end

