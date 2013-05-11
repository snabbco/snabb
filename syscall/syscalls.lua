-- choose correct syscalls for OS, plus shared calls
-- note that where functions are identical if present but may be missing they can also go here

local ffi = require "ffi"
local bit = require "bit"

local c = require "syscall.constants"
local C = require "syscall.c"
local types = require "syscall.types"
local abi = require "syscall.abi"
local h = require "syscall.helpers"

local t, pt, s = types.t, types.pt, types.s

local inlibc = h.inlibc

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
function S.rename(oldpath, newpath) return retbool(C.rename(oldpath, newpath)) end
function S.chmod(path, mode) return retbool(C.chmod(path, c.MODE[mode])) end
function S.fchmod(fd, mode) return retbool(C.fchmod(getfd(fd), c.MODE[mode])) end
function S.chown(path, owner, group) return retbool(C.chown(path, owner or -1, group or -1)) end
function S.fchown(fd, owner, group) return retbool(C.fchown(getfd(fd), owner or -1, group or -1)) end
function S.lchown(path, owner, group) return retbool(C.lchown(path, owner or -1, group or -1)) end
function S.link(oldpath, newpath) return retbool(C.link(oldpath, newpath)) end
function S.linkat(olddirfd, oldpath, newdirfd, newpath, flags)
  return retbool(C.linkat(c.AT_FDCWD[olddirfd], oldpath, c.AT_FDCWD[newdirfd], newpath, c.AT_SYMLINK_FOLLOW[flags]))
end
function S.symlink(oldpath, newpath) return retbool(C.symlink(oldpath, newpath)) end
function S.chroot(path) return retbool(C.chroot(path)) end
function S.umask(mask) return C.umask(c.MODE[mask]) end
function S.sync() return C.sync() end
function S.mknod(pathname, mode, dev)
  if type(dev) == "table" then dev = dev.dev end
  return retbool(C.mknod(pathname, c.S_I[mode], dev or 0))
end
function S.read(fd, buf, count)
  if buf then return retnum(C.read(getfd(fd), buf, count)) end -- user supplied a buffer, standard usage
  if not count then count = 4096 end
  buf = t.buffer(count)
  local ret = C.read(getfd(fd), buf, count)
  if ret == -1 then return nil, t.error() end
  return ffi.string(buf, ret) -- user gets a string back, can get length from #string
end
function S.readv(fd, iov)
  iov = mktype(t.iovecs, iov)
  return retnum(C.readv(getfd(fd), iov.iov, #iov))
end
function S.write(fd, buf, count) return retnum(C.write(getfd(fd), buf, count or #buf)) end
function S.writev(fd, iov)
  iov = mktype(t.iovecs, iov)
  return retnum(C.writev(getfd(fd), iov.iov, #iov))
end
function S.pread(fd, buf, count, offset) return retnum(C.pread(getfd(fd), buf, count, offset)) end
function S.pwrite(fd, buf, count, offset) return retnum(C.pwrite(getfd(fd), buf, count or #buf, offset)) end
if inlibc "preadv" and inlibc "pwritev" then -- these are missing in eg OSX
  function S.preadv(fd, iov, offset)
    iov = mktype(t.iovecs, iov)
    return retnum(C.preadv(getfd(fd), iov.iov, #iov, offset))
  end
  function S.pwritev(fd, iov, offset)
    iov = mktype(t.iovecs, iov)
    return retnum(C.pwritev(getfd(fd), iov.iov, #iov, offset))
  end
end
function S.access(pathname, mode) return retbool(C.access(pathname, c.OK[mode])) end
function S.lseek(fd, offset, whence)
  return ret64(C.lseek(getfd(fd), offset or 0, c.SEEK[whence]))
end

local function sproto(domain, protocol) -- helper function to lookup protocol type depending on domain TODO table?
  protocol = protocol or 0
  if domain == c.AF.NETLINK then return c.NETLINK[protocol] end
  return c.IPPROTO[protocol]
end

function S.socket(domain, stype, protocol)
  domain = c.AF[domain]
  return retfd(C.socket(domain, c.SOCK[stype], sproto(domain, protocol)))
end
function S.socketpair(domain, stype, protocol)
  domain = c.AF[domain]
  local sv2 = t.int2()
  local ret = C.socketpair(domain, c.SOCK[stype], sproto(domain, protocol), sv2)
  if ret == -1 then return nil, t.error() end
  return t.socketpair(sv2)
end
if inlibc "dup3" then
  -- TODO dup3 can have a race condition (see Linux man page) although Musl fixes, appears eglibc does not
  function S.dup(oldfd, newfd, flags)
    if not newfd then return retfd(C.dup(getfd(oldfd))) end
    return retfd(C.dup3(getfd(oldfd), getfd(newfd), flags or 0))
  end
else -- OSX does not have dup3
  function S.dup(oldfd, newfd, flags)
    assert(not flags, "TODO: emulate dup3 behaviour on OSX")
    if not newfd then return retfd(C.dup(getfd(oldfd))) end
    return retfd(C.dup2(getfd(oldfd), getfd(newfd))) -- TODO set flags on newfd
  end
end

function S.getuid() return C.getuid() end
function S.geteuid() return C.geteuid() end
function S.getpid() return C.getpid() end
function S.getppid() return C.getppid() end
function S.getgid() return C.getgid() end
function S.getegid() return C.getegid() end
function S.setuid(uid) return retbool(C.setuid(uid)) end
function S.setgid(gid) return retbool(C.setgid(gid)) end
function S.seteuid(uid) return retbool(C.seteuid(uid)) end
function S.setegid(gid) return retbool(C.setegid(gid)) end
function S.getsid(pid) return retnum(C.getsid(pid or 0)) end
function S.setsid() return retnum(C.setsid()) end
function S.setpgid(pid, pgid) return retbool(C.setpgid(pid or 0, pgid or 0)) end
function S.getpgid(pid) return retnum(C.getpgid(pid or 0)) end
function S.getpgrp() return retnum(C.getpgrp()) end

function S._exit(status) C._exit(c.EXIT[status]) end

-- now call OS specific for non-generic calls
local hh = {
  istype = istype, mktype = mktype , getfd = getfd,
  ret64 = ret64, retnum = retnum, retfd = retfd, retbool = retbool, retptr = retptr
}

local S = require("syscall." .. abi.os .. ".syscalls")(S, hh)

-- these functions are not always available as syscalls, so always define via other calls
function S.creat(pathname, mode) return S.open(pathname, "CREAT,WRONLY,TRUNC", mode) end

function S.nice(inc)
  local prio = S.getpriority("process", 0) -- this cannot fail with these args.
  local ok, err = S.setpriority("process", 0, prio + inc)
  if not ok then return nil, err end
  return S.getpriority("process", 0)
end

-- deprecated in NetBSD so implement with recvfrom
function S.recv(fd, buf, count, flags) return retnum(C.recvfrom(getfd(fd), buf, count or #buf, c.MSG[flags], nil, 0)) end

-- TODO setpgrp and similar - see the man page

return S

