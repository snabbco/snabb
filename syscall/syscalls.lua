-- choose correct syscalls for OS, plus shared calls
-- note that where functions are identical if present but may be missing they can also go here

function init(abi, c, C, types, ioctl, fcntl)

local ffi = require "ffi"
local bit = require "bit"

local h = require "syscall.helpers"

local t, pt, s = types.t, types.pt, types.s

local inlibc = h.inlibc

local S = {}

-- helpers
local zeropointer = pt.void(0)
local errpointer = pt.void(-1)
local err64 = t.uint64(-1LL)

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
  if ret == err64 then return nil, t.error() end
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
  if type(dev) == "table" then dev = dev.dev end -- TODO allow array eg {2, 2} - major, minor
  return retbool(C.mknod(pathname, c.S_I[mode], dev or 0))
end
-- TODO read should have consistent return type but then will differ from other calls.
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
function S.readlink(path, buffer, size)
  size = size or c.PATH_MAX
  buffer = buffer or t.buffer(size)
  local ret = tonumber(C.readlink(path, buffer, size))
  if ret == -1 then return nil, t.error() end
  return ffi.string(buffer, ret)
end
function S.fsync(fd) return retbool(C.fsync(getfd(fd))) end
function S.fdatasync(fd) return retbool(C.fdatasync(getfd(fd))) end
function S.stat(path, buf)
  if not buf then buf = t.stat() end
  local ret = C.stat(path, buf)
  if ret == -1 then return nil, t.error() end
  return buf
end
function S.lstat(path, buf)
  if not buf then buf = t.stat() end
  local ret = C.lstat(path, buf)
  if ret == -1 then return nil, t.error() end
  return buf
end
function S.fstat(fd, buf)
  if not buf then buf = t.stat() end
  local ret = C.fstat(getfd(fd), buf)
  if ret == -1 then return nil, t.error() end
  return buf
end
function S.truncate(path, length) return retbool(C.truncate(path, length)) end
function S.ftruncate(fd, length) return retbool(C.ftruncate(getfd(fd), length)) end

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
function S.send(fd, buf, count, flags) return retnum(C.send(getfd(fd), buf, count or #buf, c.MSG[flags])) end
function S.sendto(fd, buf, count, flags, addr, addrlen)
  return retnum(C.sendto(getfd(fd), buf, count or #buf, c.MSG[flags], addr, addrlen or #addr))
end
function S.recvfrom(fd, buf, count, flags, ss, addrlen)
  ss = ss or t.sockaddr_storage()
  addrlen = addrlen or t.socklen1(#ss)
  local ret = C.recvfrom(getfd(fd), buf, count, c.MSG[flags], ss, addrlen)
  if ret == -1 then return nil, t.error() end
  return {count = tonumber(ret), addr = t.sa(ss, addrlen[0])}
end
function S.sendmsg(fd, msg, flags)
  if not msg then -- send a single byte message, eg enough to send credentials
    local buf1 = t.buffer(1)
    local io = t.iovecs{{buf1, 1}}
    msg = t.msghdr{msg_iov = io.iov, msg_iovlen = #io}
  end
  return retbool(C.sendmsg(getfd(fd), msg, c.MSG[flags]))
end
function S.recvmsg(fd, msg, flags) return retnum(C.recvmsg(getfd(fd), msg, c.MSG[flags])) end
-- TODO {get,set}sockopt may need better type handling
function S.setsockopt(fd, level, optname, optval, optlen)
   -- allocate buffer for user, from Lua type if know how, int and bool so far
  if not optlen and type(optval) == 'boolean' then optval = h.booltoc(optval) end
  if not optlen and type(optval) == 'number' then
    optval = t.int1(optval)
    optlen = s.int
  end
  return retbool(C.setsockopt(getfd(fd), c.SOL[level], c.SO[optname], optval, optlen))
end
function S.getsockopt(fd, level, optname, optval, optlen)
  if not optval then optval, optlen = t.int1(), s.int end
  optlen = optlen or #optval
  local len = t.socklen1(optlen)
  local ret = C.getsockopt(getfd(fd), level, optname, optval, len)
  if ret == -1 then return nil, t.error() end
  return optval[0] -- TODO will not work if struct, eg see netfilter
end
function S.bind(sockfd, addr, addrlen) return retbool(C.bind(getfd(sockfd), addr, addrlen or #addr)) end
function S.listen(sockfd, backlog) return retbool(C.listen(getfd(sockfd), backlog or c.SOMAXCONN)) end
function S.connect(sockfd, addr, addrlen) return retbool(C.connect(getfd(sockfd), addr, addrlen or #addr)) end
function S.getsockname(sockfd, ss, addrlen)
  ss = ss or t.sockaddr_storage()
  addrlen = addrlen or t.socklen1(#ss)
  local ret = C.getsockname(getfd(sockfd), ss, addrlen)
  if ret == -1 then return nil, t.error() end
  return t.sa(ss, addrlen[0])
end
function S.getpeername(sockfd, ss, addrlen)
  ss = ss or t.sockaddr_storage()
  addrlen = addrlen or t.socklen1(#ss)
  local ret = C.getpeername(getfd(sockfd), ss, addrlen)
  if ret == -1 then return nil, t.error() end
  return t.sa(ss, addrlen[0])
end
function S.shutdown(sockfd, how) return retbool(C.shutdown(getfd(sockfd), c.SHUT[how])) end

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
function S.getgroups()
  local size = C.getgroups(0, nil) -- note for BSD could use NGROUPS_MAX instead
  if size == -1 then return nil, t.error() end
  local groups = t.groups(size)
  local ret = C.getgroups(size, groups.list)
  if ret == -1 then return nil, t.error() end
  return groups
end
function S.setgroups(groups)
  if type(groups) == "table" then groups = t.groups(groups) end
  return retbool(C.setgroups(groups.count, groups.list))
end
function S.sigaction(signum, handler, oldact)
  if type(handler) == "string" or type(handler) == "function" then
    handler = {handler = handler, mask = "", flags = 0} -- simple case like signal
  end
  if handler then handler = mktype(t.sigaction, handler) end
  return retbool(C.sigaction(c.SIG[signum], handler, oldact))
end
function S.sigprocmask(how, set)
  local oldset = t.sigset()
  local ret = C.sigprocmask(c.SIGPM[how], t.sigset(set), oldset)
  if ret == -1 then return nil, t.error() end
  return oldset
end
function S.sigpending()
  local set = t.sigset()
  local ret = C.sigpending(set)
  if ret == -1 then return nil, t.error() end
 return set
end
function S.sigsuspend(mask) return retbool(C.sigsuspend(t.sigset(mask))) end
function S.kill(pid, sig) return retbool(C.kill(pid, c.SIG[sig])) end

function S._exit(status) C._exit(c.EXIT[status]) end

function S.fcntl(fd, cmd, arg)
  cmd = c.F[cmd]
  if fcntl.commands[cmd] then arg = fcntl.commands[cmd](arg) end
  local ret = C.fcntl(getfd(fd), cmd, pt.void(arg or 0))
  if ret == -1 then return nil, t.error() end
  if fcntl.ret[cmd] then return fcntl.ret[cmd](ret, arg) end
  return true
end

-- now call OS specific for non-generic calls
local hh = {
  istype = istype, mktype = mktype , getfd = getfd,
  ret64 = ret64, retnum = retnum, retfd = retfd, retbool = retbool, retptr = retptr
}

local S = require("syscall." .. abi.os .. ".syscalls")(S, hh, abi, c, C, types, ioctl)

-- these functions are not always available as syscalls, so always define via other calls
function S.creat(pathname, mode) return S.open(pathname, "CREAT,WRONLY,TRUNC", mode) end

function S.nice(inc)
  local prio = S.getpriority("process", 0) -- this cannot fail with these args.
  local ok, err = S.setpriority("process", 0, prio + inc)
  if not ok then return nil, err end
  return S.getpriority("process", 0)
end

-- deprecated in NetBSD so implement with recvfrom
function S.recv(fd, buf, count, flags) return retnum(C.recvfrom(getfd(fd), buf, count or #buf, c.MSG[flags], nil, nil)) end

-- not a syscall in many systems, defined in terms of sigaction
function S.signal(signum, handler) -- defined in terms of sigaction
  local oldact = t.sigaction()
  local ok, err = S.sigaction(signum, handler, oldact)
  if not ok then return nil, err end
  return oldact.sa_handler
end

if not S.accept then
  function S.accept(sockfd, flags, addr, addrlen) -- TODO emulate netbsd paccept and Linux accept4
    assert(not flags, "TODO add accept flags emulation")
    addr = addr or t.sockaddr_storage()
    addrlen = addrlen or t.socklen1(addrlen or #addr)
    local ret = C.accept(getfd(sockfd), addr, addrlen)
    if ret == -1 then return nil, t.error() end
    return {fd = t.fd(ret), addr = t.sa(addr, addrlen[0])}
  end
end

if not S.pause then -- NetBSD and OSX deprecate pause
  function S.pause() return S.sigsuspend(t.sigset()) end
end

if not inlibc "pipe2" then
  function S.pipe(flags) -- TODO emulate flags
    assert(not flags, "TODO add pipe flags emulation")
    local fd2 = t.int2()
    local ret = C.pipe(fd2)
    if ret == -1 then return nil, t.error() end
    return t.pipe(fd2)
  end
else -- NetBSD and Linux have pipe2
  function S.pipe(flags)
    local fd2 = t.int2()
    local ret
    if flags then
      ret = C.pipe2(fd2, c.OPIPE[flags])
    else
      ret = C.pipe(fd2)
    end
    if ret == -1 then return nil, t.error() end
    return t.pipe(fd2)
  end
end

if not S.umount then S.umount = S.unmount end -- TODO reserse as well

-- TODO setpgrp and similar - see the man page

return S

end

return {init = init}

