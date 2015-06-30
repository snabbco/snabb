-- choose correct syscalls for OS, plus shared calls
-- note that where functions are identical if present but may be missing they can also go here
-- note that OS specific calls are loaded at the end so they may override generic calls here

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local abi = require "syscall.abi"
local ffi = require "ffi"
local bit = require "syscall.bit"

local h = require "syscall.helpers"
local err64 = h.err64
local errpointer = h.errpointer
local getfd, istype, mktype, reviter = h.getfd, h.istype, h.mktype, h.reviter

local function init(C, c, types)

-- this could be an arguments, fcntl syscall is a function of this
local fcntl = require("syscall." .. abi.os .. ".fcntl").init(types)

local errno = ffi.errno

local t, pt, s = types.t, types.pt, types.s

local S = {}

local function getdev(dev)
  if type(dev) == "table" then return t.device(dev).dev end
  if ffi.istype(t.device, dev) then dev = dev.dev end
  return dev
end

-- return helpers.

-- 64 bit return helpers. Only use for lseek in fact; we use tonumber but remove if you need files over 56 bits long
-- TODO only luaffi needs the cast as wont compare to number; hopefully fixed in future with 5.3 or a later luaffi.
local function ret64(ret, err)
  if ret == err64 then return nil, t.error(err or errno()) end
  return tonumber(ret)
end

local function retnum(ret, err) -- return Lua number where double precision ok, eg file ops etc
  ret = tonumber(ret)
  if ret == -1 then return nil, t.error(err or errno()) end
  return ret
end

local function retfd(ret, err)
  if ret == -1 then return nil, t.error(err or errno()) end
  return t.fd(ret)
end

-- used for no return value, return true for use of assert
local function retbool(ret, err)
  if ret == -1 then return nil, t.error(err or errno()) end
  return true
end

-- used for pointer returns, -1 is failure
local function retptr(ret, err)
  if ret == errpointer then return nil, t.error(err or errno()) end
  return ret
end

-- generic iterator; this counts down to 0 so need no closure
local function retiter(ret, err, array)
  ret = tonumber(ret)
  if ret == -1 then return nil, t.error(err or errno()) end
  return reviter, array, ret
end

-- generic system calls
function S.close(fd) return retbool(C.close(getfd(fd))) end
function S.chdir(path) return retbool(C.chdir(path)) end
function S.fchdir(fd) return retbool(C.fchdir(getfd(fd))) end
function S.fchmod(fd, mode) return retbool(C.fchmod(getfd(fd), c.MODE[mode])) end
function S.fchown(fd, owner, group) return retbool(C.fchown(getfd(fd), owner or -1, group or -1)) end
function S.lchown(path, owner, group) return retbool(C.lchown(path, owner or -1, group or -1)) end
function S.chroot(path) return retbool(C.chroot(path)) end
function S.umask(mask) return C.umask(c.MODE[mask]) end
function S.sync() C.sync() end
function S.flock(fd, operation) return retbool(C.flock(getfd(fd), c.LOCK[operation])) end
-- TODO read should have consistent return type but then will differ from other calls.
function S.read(fd, buf, count)
  if buf then return retnum(C.read(getfd(fd), buf, count or #buf or 4096)) end -- user supplied a buffer, standard usage
  count = count or 4096
  buf = t.buffer(count)
  local ret, err = tonumber(C.read(getfd(fd), buf, count))
  if ret == -1 then return nil, t.error(err or errno()) end
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
if C.preadv and C.pwritev then -- these are missing in eg OSX
  function S.preadv(fd, iov, offset)
    iov = mktype(t.iovecs, iov)
    return retnum(C.preadv(getfd(fd), iov.iov, #iov, offset))
  end
  function S.pwritev(fd, iov, offset)
    iov = mktype(t.iovecs, iov)
    return retnum(C.pwritev(getfd(fd), iov.iov, #iov, offset))
  end
end
function S.lseek(fd, offset, whence)
  return ret64(C.lseek(getfd(fd), offset or 0, c.SEEK[whence or c.SEEK.SET]))
end
if C.readlink then
  function S.readlink(path, buffer, size)
    size = size or c.PATH_MAX
    buffer = buffer or t.buffer(size)
    local ret, err = tonumber(C.readlink(path, buffer, size))
    if ret == -1 then return nil, t.error(err or errno()) end
    return ffi.string(buffer, ret)
  end
else
  function S.readlink(path, buffer, size)
    size = size or c.PATH_MAX
    buffer = buffer or t.buffer(size)
    local ret, err = tonumber(C.readlinkat(c.AT_FDCWD.FDCWD, path, buffer, size))
    if ret == -1 then return nil, t.error(err or errno()) end
    return ffi.string(buffer, ret)
  end
end
function S.fsync(fd) return retbool(C.fsync(getfd(fd))) end
if C.stat then
  function S.stat(path, buf)
    if not buf then buf = t.stat() end
    local ret = C.stat(path, buf)
    if ret == -1 then return nil, t.error() end
    return buf
  end
else
  function S.stat(path, buf)
    if not buf then buf = t.stat() end
    local ret = C.fstatat(c.AT_FDCWD.FDCWD, path, buf, 0)
    if ret == -1 then return nil, t.error() end
    return buf
  end
end
if C.lstat then
  function S.lstat(path, buf)
    if not buf then buf = t.stat() end
    local ret, err = C.lstat(path, buf)
    if ret == -1 then return nil, t.error(err or errno()) end
    return buf
  end
else
  function S.lstat(path, buf)
    if not buf then buf = t.stat() end
    local ret, err = C.fstatat(c.AT_FDCWD.FDCWD, path, buf, c.AT.SYMLINK_NOFOLLOW)
    if ret == -1 then return nil, t.error(err or errno()) end
    return buf
  end
end
function S.fstat(fd, buf)
  if not buf then buf = t.stat() end
  local ret, err = C.fstat(getfd(fd), buf)
  if ret == -1 then return nil, t.error(err or errno()) end
  return buf
end
function S.truncate(path, length) return retbool(C.truncate(path, length)) end
function S.ftruncate(fd, length) return retbool(C.ftruncate(getfd(fd), length)) end

-- recent Linux does not have open, rmdir, unlink etc any more as syscalls
if C.open then
  function S.open(pathname, flags, mode) return retfd(C.open(pathname, c.O[flags], c.MODE[mode])) end
else
  function S.open(pathname, flags, mode) return retfd(C.openat(c.AT_FDCWD.FDCWD, pathname, c.O[flags], c.MODE[mode])) end
end
if C.rmdir then
  function S.rmdir(path) return retbool(C.rmdir(path)) end
else
  function S.rmdir(path) return retbool(C.unlinkat(c.AT_FDCWD.FDCWD, path, c.AT.REMOVEDIR)) end
end
if C.unlink then
  function S.unlink(pathname) return retbool(C.unlink(pathname)) end
else
  function S.unlink(path) return retbool(C.unlinkat(c.AT_FDCWD.FDCWD, path, 0)) end
end
if C.chmod then
  function S.chmod(path, mode) return retbool(C.chmod(path, c.MODE[mode])) end
else
  function S.chmod(path, mode) return retbool(C.fchmodat(c.AT_FDCWD.FDCWD, path, c.MODE[mode], 0)) end
end
if C.access then
  function S.access(pathname, mode) return retbool(C.access(pathname, c.OK[mode])) end
else
  function S.access(pathname, mode) return retbool(C.faccessat(c.AT_FDCWD.FDCWD, pathname, c.OK[mode], 0)) end
end
if C.chown then
  function S.chown(path, owner, group) return retbool(C.chown(path, owner or -1, group or -1)) end
else
  function S.chown(path, owner, group) return retbool(C.fchownat(c.AT_FDCWD.FDCWD, path, owner or -1, group or -1, 0)) end
end
if C.mkdir then
  function S.mkdir(path, mode) return retbool(C.mkdir(path, c.MODE[mode])) end
else
  function S.mkdir(path, mode) return retbool(C.mkdirat(c.AT_FDCWD.FDCWD, path, c.MODE[mode])) end
end
if C.symlink then
  function S.symlink(oldpath, newpath) return retbool(C.symlink(oldpath, newpath)) end
else
  function S.symlink(oldpath, newpath) return retbool(C.symlinkat(oldpath, c.AT_FDCWD.FDCWD, newpath)) end
end
if C.link then
  function S.link(oldpath, newpath) return retbool(C.link(oldpath, newpath)) end
else
  function S.link(oldpath, newpath) return retbool(C.linkat(c.AT_FDCWD.FDCWD, oldpath, c.AT_FDCWD.FDCWD, newpath, 0)) end
end
if C.rename then
  function S.rename(oldpath, newpath) return retbool(C.rename(oldpath, newpath)) end
else
  function S.rename(oldpath, newpath) return retbool(C.renameat(c.AT_FDCWD.FDCWD, oldpath, c.AT_FDCWD.FDCWD, newpath)) end
end
if C.mknod then
  function S.mknod(pathname, mode, dev) return retbool(C.mknod(pathname, c.S_I[mode], getdev(dev) or 0)) end
else
  function S.mknod(pathname, mode, dev) return retbool(C.mknodat(c.AT_FDCWD.FDCWD, pathname, c.S_I[mode], getdev(dev) or 0)) end
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
function S.socketpair(domain, stype, protocol, sv2)
  domain = c.AF[domain]
  sv2 = sv2 or t.int2()
  local ret, err = C.socketpair(domain, c.SOCK[stype], sproto(domain, protocol), sv2)
  if ret == -1 then return nil, t.error(err or errno()) end
  return true, nil, t.fd(sv2[0]), t.fd(sv2[1])
end

function S.dup(oldfd) return retfd(C.dup(getfd(oldfd))) end
if C.dup2 then function S.dup2(oldfd, newfd) return retfd(C.dup2(getfd(oldfd), getfd(newfd))) end end
if C.dup3 then function S.dup3(oldfd, newfd, flags) return retfd(C.dup3(getfd(oldfd), getfd(newfd), flags or 0)) end end

function S.sendto(fd, buf, count, flags, addr, addrlen)
  if not addr then addrlen = 0 end
  local saddr = pt.sockaddr(addr)
  return retnum(C.sendto(getfd(fd), buf, count or #buf, c.MSG[flags], saddr, addrlen or #addr))
end
function S.recvfrom(fd, buf, count, flags, addr, addrlen)
  local saddr
  if addr == false then
    addr = nil
    addrlen = nil
  else
    if addr then
      addrlen = addrlen or #addr
    else
      addr = t.sockaddr_storage()
      addrlen = addrlen or s.sockaddr_storage
    end
    if type(addrlen) == "number" then addrlen = t.socklen1(addrlen) end
    saddr = pt.sockaddr(addr)
  end
  local ret, err = C.recvfrom(getfd(fd), buf, count or #buf, c.MSG[flags], saddr, addrlen) -- TODO addrlen 0 here???
  ret = tonumber(ret)
  if ret == -1 then return nil, t.error(err or errno()) end
  if addr then return ret, nil, t.sa(addr, addrlen[0]) else return ret end
end
function S.sendmsg(fd, msg, flags)
  if not msg then -- send a single byte message, eg enough to send credentials
    local buf1 = t.buffer(1)
    local io = t.iovecs{{buf1, 1}}
    msg = t.msghdr{msg_iov = io.iov, msg_iovlen = #io}
  end
  return retnum(C.sendmsg(getfd(fd), msg, c.MSG[flags]))
end
function S.recvmsg(fd, msg, flags) return retnum(C.recvmsg(getfd(fd), msg, c.MSG[flags])) end

-- TODO better handling of msgvec, create one structure/table
if C.sendmmsg then
  function S.sendmmsg(fd, msgvec, flags)
    msgvec = mktype(t.mmsghdrs, msgvec)
    return retbool(C.sendmmsg(getfd(fd), msgvec.msg, msgvec.count, c.MSG[flags]))
  end
end
if C.recvmmsg then
  function S.recvmmsg(fd, msgvec, flags, timeout)
    if timeout then timeout = mktype(t.timespec, timeout) end
    msgvec = mktype(t.mmsghdrs, msgvec)
    return retbool(C.recvmmsg(getfd(fd), msgvec.msg, msgvec.count, c.MSG[flags], timeout))
  end
end

-- TODO {get,set}sockopt may need better type handling see new unfinished sockopt file, plus not always c.SO[]
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
  local ret, err = C.getsockopt(getfd(fd), c.SOL[level], c.SO[optname], optval, len)
  if ret == -1 then return nil, t.error(err or errno()) end
  if len[0] ~= optlen then error("incorrect optlen for getsockopt: set " .. optlen .. " got " .. len[0]) end
  return optval[0] -- TODO will not work if struct, eg see netfilter
end
function S.bind(sockfd, addr, addrlen)
  local saddr = pt.sockaddr(addr)
  return retbool(C.bind(getfd(sockfd), saddr, addrlen or #addr))
end
function S.listen(sockfd, backlog) return retbool(C.listen(getfd(sockfd), backlog or c.SOMAXCONN)) end
function S.connect(sockfd, addr, addrlen)
  local saddr = pt.sockaddr(addr)
  return retbool(C.connect(getfd(sockfd), saddr, addrlen or #addr))
end
function S.accept(sockfd, addr, addrlen)
  local saddr = pt.sockaddr(addr)
  if addr then addrlen = addrlen or t.socklen1() end
  return retfd(C.accept(getfd(sockfd), saddr, addrlen))
end
function S.getsockname(sockfd, addr, addrlen)
  addr = addr or t.sockaddr_storage()
  addrlen = addrlen or t.socklen1(#addr)
  local saddr = pt.sockaddr(addr)
  local ret, err = C.getsockname(getfd(sockfd), saddr, addrlen)
  if ret == -1 then return nil, t.error(err or errno()) end
  return t.sa(addr, addrlen[0])
end
function S.getpeername(sockfd, addr, addrlen)
  addr = addr or t.sockaddr_storage()
  addrlen = addrlen or t.socklen1(#addr)
  local saddr = pt.sockaddr(addr)
  local ret, err = C.getpeername(getfd(sockfd), saddr, addrlen)
  if ret == -1 then return nil, t.error(err or errno()) end
  return t.sa(addr, addrlen[0])
end
function S.shutdown(sockfd, how) return retbool(C.shutdown(getfd(sockfd), c.SHUT[how])) end
if C.poll then
  function S.poll(fds, timeout) return retnum(C.poll(fds.pfd, #fds, timeout or -1)) end
end
-- TODO rework fdset interface, see issue #71
-- fdset handlers
local function mkfdset(fds, nfds) -- should probably check fd is within range (1024), or just expand structure size
  local set = t.fdset()
  for i, v in ipairs(fds) do
    local fd = tonumber(getfd(v))
    if fd + 1 > nfds then nfds = fd + 1 end
    local fdelt = bit.rshift(fd, 5) -- always 32 bits
    set.fds_bits[fdelt] = bit.bor(set.fds_bits[fdelt], bit.lshift(1, fd % 32)) -- always 32 bit words
  end
  return set, nfds
end

local function fdisset(fds, set)
  local f = {}
  for i, v in ipairs(fds) do
    local fd = tonumber(getfd(v))
    local fdelt = bit.rshift(fd, 5) -- always 32 bits
    if bit.band(set.fds_bits[fdelt], bit.lshift(1, fd % 32)) ~= 0 then table.insert(f, v) end -- careful not to duplicate fd objects
  end
  return f
end

-- TODO convert to metatype. Problem is how to deal with nfds
if C.select then
function S.select(sel, timeout) -- note same structure as returned
  local r, w, e
  local nfds = 0
  if timeout then timeout = mktype(t.timeval, timeout) end
  r, nfds = mkfdset(sel.readfds or {}, nfds or 0)
  w, nfds = mkfdset(sel.writefds or {}, nfds)
  e, nfds = mkfdset(sel.exceptfds or {}, nfds)
  local ret, err = C.select(nfds, r, w, e, timeout)
  if ret == -1 then return nil, t.error(err or errno()) end
  return {readfds = fdisset(sel.readfds or {}, r), writefds = fdisset(sel.writefds or {}, w),
          exceptfds = fdisset(sel.exceptfds or {}, e), count = tonumber(ret)}
end
else
  function S.select(sel, timeout)
    if timeout then timeout = mktype(t.timespec, timeout / 1000) end
    return S.pselect(sel, timeout)
  end
end

-- TODO note that in Linux syscall modifies timeout, which is non standard, like ppoll
function S.pselect(sel, timeout, set) -- note same structure as returned
  local r, w, e
  local nfds = 0
  if timeout then timeout = mktype(t.timespec, timeout) end
  if set then set = mktype(t.sigset, set) end
  r, nfds = mkfdset(sel.readfds or {}, nfds or 0)
  w, nfds = mkfdset(sel.writefds or {}, nfds)
  e, nfds = mkfdset(sel.exceptfds or {}, nfds)
  local ret, err = C.pselect(nfds, r, w, e, timeout, set)
  if ret == -1 then return nil, t.error(err or errno()) end
  return {readfds = fdisset(sel.readfds or {}, r), writefds = fdisset(sel.writefds or {}, w),
          exceptfds = fdisset(sel.exceptfds or {}, e), count = tonumber(ret)}
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
if C.getpgrp then
  function S.getpgrp() return retnum(C.getpgrp()) end
else
  function S.getpgrp() return retnum(C.getpgid(0)) end
end
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

function S.sigprocmask(how, set, oldset)
  oldset = oldset or t.sigset()
  if not set then how = c.SIGPM.SETMASK end -- value does not matter if set nil, just returns old set
  local ret, err = C.sigprocmask(c.SIGPM[how], t.sigset(set), oldset)
  if ret == -1 then return nil, t.error(err or errno()) end
  return oldset
end
function S.sigpending()
  local set = t.sigset()
  local ret, err = C.sigpending(set)
  if ret == -1 then return nil, t.error(err or errno()) end
 return set
end
function S.sigsuspend(mask) return retbool(C.sigsuspend(t.sigset(mask))) end
function S.kill(pid, sig) return retbool(C.kill(pid, c.SIG[sig])) end

-- _exit is the real exit syscall, or whatever is suitable if overridden in c.lua; libc.lua may override
function S.exit(status) C._exit(c.EXIT[status or 0]) end

function S.fcntl(fd, cmd, arg)
  cmd = c.F[cmd]
  if fcntl.commands[cmd] then arg = fcntl.commands[cmd](arg) end
  local ret, err = C.fcntl(getfd(fd), cmd, pt.void(arg or 0))
  if ret == -1 then return nil, t.error(err or errno()) end
  if fcntl.ret[cmd] then return fcntl.ret[cmd](ret, arg) end
  return true
end

-- TODO return metatype that has length and can gc?
function S.mmap(addr, length, prot, flags, fd, offset)
  return retptr(C.mmap(addr, length, c.PROT[prot], c.MAP[flags], getfd(fd or -1), offset or 0))
end
function S.munmap(addr, length)
  return retbool(C.munmap(addr, length))
end
function S.msync(addr, length, flags) return retbool(C.msync(addr, length, c.MSYNC[flags])) end
function S.mlock(addr, len) return retbool(C.mlock(addr, len)) end
function S.munlock(addr, len) return retbool(C.munlock(addr, len)) end
function S.munlockall() return retbool(C.munlockall()) end
function S.madvise(addr, length, advice) return retbool(C.madvise(addr, length, c.MADV[advice])) end

function S.ioctl(d, request, argp)
  local read, singleton = false, false
  local name = request
  if type(name) == "string" then
    request = c.IOCTL[name]
  end
  if type(request) == "table" then
    local write = request.write
    local tp = request.type
    read = request.read
    singleton = request.singleton
    request = request.number
    if type(argp) ~= "string" and type(argp) ~= "cdata" and type ~= "userdata" then
      if write then
        if not argp then error("no argument supplied for ioctl " .. name) end
        argp = mktype(tp, argp)
      end
      if read then
        argp = argp or tp()
      end
    end
  else -- some sane defaults if no info
    if type(request) == "table" then request = request.number end
    if type(argp) == "string" then argp = pt.char(argp) end
    if type(argp) == "number" then argp = t.int1(argp) end
  end
  local ret, err = C.ioctl(getfd(d), request, argp)
  if ret == -1 then return nil, t.error(err or errno()) end
  if read and singleton then return argp[0] end
  if read then return argp end
  return true -- will need override for few linux ones that return numbers
end

if C.pipe then
  function S.pipe(fd2)
    fd2 = fd2 or t.int2()
    local ret, err = C.pipe(fd2)
    if ret == -1 then return nil, t.error(err or errno()) end
    return true, nil, t.fd(fd2[0]), t.fd(fd2[1])
  end
else
  function S.pipe(fd2)
    fd2 = fd2 or t.int2()
    local ret, err = C.pipe2(fd2, 0)
    if ret == -1 then return nil, t.error(err or errno()) end
    return true, nil, t.fd(fd2[0]), t.fd(fd2[1])
  end
end

if C.gettimeofday then
  function S.gettimeofday(tv)
    tv = tv or t.timeval() -- note it is faster to pass your own tv if you call a lot
    local ret, err = C.gettimeofday(tv, nil)
    if ret == -1 then return nil, t.error(err or errno()) end
    return tv
  end
end

if C.settimeofday then
  function S.settimeofday(tv) return retbool(C.settimeofday(tv, nil)) end
end

function S.getrusage(who, ru)
  ru = ru or t.rusage()
  local ret, err = C.getrusage(c.RUSAGE[who], ru)
  if ret == -1 then return nil, t.error(err or errno()) end
  return ru
end

if C.fork then
  function S.fork() return retnum(C.fork()) end
else
  function S.fork() return retnum(C.clone(c.SIG.CHLD, 0)) end
end

function S.execve(filename, argv, envp)
  local cargv = t.string_array(#argv + 1, argv or {})
  cargv[#argv] = nil -- LuaJIT does not zero rest of a VLA
  local cenvp = t.string_array(#envp + 1, envp or {})
  cenvp[#envp] = nil
  return retbool(C.execve(filename, cargv, cenvp))
end

-- man page says obsolete for Linux, but implemented and useful for compatibility
function S.wait4(pid, options, ru, status) -- note order of arguments changed as rarely supply status (as waitpid)
  if ru == false then ru = nil else ru = ru or t.rusage() end -- false means no allocation
  status = status or t.int1()
  local ret, err = C.wait4(c.WAIT[pid], status, c.W[options], ru)
  if ret == -1 then return nil, t.error(err or errno()) end
  return ret, nil, t.waitstatus(status[0]), ru
end

if C.waitpid then
  function S.waitpid(pid, options, status) -- note order of arguments changed as rarely supply status
    status = status or t.int1()
    local ret, err = C.waitpid(c.WAIT[pid], status, c.W[options])
    if ret == -1 then return nil, t.error(err or errno()) end
    return ret, nil, t.waitstatus(status[0])
  end
end

if S.waitid then
  function S.waitid(idtype, id, options, infop) -- note order of args, as usually dont supply infop
    if not infop then infop = t.siginfo() end
    local ret, err = C.waitid(c.P[idtype], id or 0, infop, c.W[options])
    if ret == -1 then return nil, t.error(err or errno()) end
    return infop
  end
end

function S.setpriority(which, who, prio) return retbool(C.setpriority(c.PRIO[which], who or 0, prio)) end
-- Linux overrides getpriority as it offsets return values so that they are not negative
function S.getpriority(which, who)
  errno(0)
  local ret, err = C.getpriority(c.PRIO[which], who or 0)
  if ret == -1 and (err or errno()) ~= 0 then return nil, t.error(err or errno()) end
  return ret
end

-- these may not always exist, but where they do they have the same interface
if C.creat then
  function S.creat(pathname, mode) return retfd(C.creat(pathname, c.MODE[mode])) end
end
if C.pipe2 then
  function S.pipe2(flags, fd2)
    fd2 = fd2 or t.int2()
    local ret, err = C.pipe2(fd2, c.OPIPE[flags])
    if ret == -1 then return nil, t.error(err or errno()) end
    return true, nil, t.fd(fd2[0]), t.fd(fd2[1])
  end
end
if C.mlockall then
  function S.mlockall(flags) return retbool(C.mlockall(c.MCL[flags])) end
end
if C.linkat then
  function S.linkat(olddirfd, oldpath, newdirfd, newpath, flags)
    return retbool(C.linkat(c.AT_FDCWD[olddirfd], oldpath, c.AT_FDCWD[newdirfd], newpath, c.AT[flags]))
  end
end
if C.symlinkat then
  function S.symlinkat(oldpath, newdirfd, newpath) return retbool(C.symlinkat(oldpath, c.AT_FDCWD[newdirfd], newpath)) end
end
if C.unlinkat then
  function S.unlinkat(dirfd, path, flags) return retbool(C.unlinkat(c.AT_FDCWD[dirfd], path, c.AT[flags])) end
end
if C.renameat then
  function S.renameat(olddirfd, oldpath, newdirfd, newpath)
    return retbool(C.renameat(c.AT_FDCWD[olddirfd], oldpath, c.AT_FDCWD[newdirfd], newpath))
  end
end
if C.mkdirat then
  function S.mkdirat(fd, path, mode) return retbool(C.mkdirat(c.AT_FDCWD[fd], path, c.MODE[mode])) end
end
if C.fchownat then
  function S.fchownat(dirfd, path, owner, group, flags)
    return retbool(C.fchownat(c.AT_FDCWD[dirfd], path, owner or -1, group or -1, c.AT[flags]))
  end
end
if C.faccessat then
  function S.faccessat(dirfd, pathname, mode, flags)
    return retbool(C.faccessat(c.AT_FDCWD[dirfd], pathname, c.OK[mode], c.AT[flags]))
  end
end
if C.readlinkat then
  function S.readlinkat(dirfd, path, buffer, size)
    size = size or c.PATH_MAX
    buffer = buffer or t.buffer(size)
    local ret, err = C.readlinkat(c.AT_FDCWD[dirfd], path, buffer, size)
    ret = tonumber(ret)
    if ret == -1 then return nil, t.error(err or errno()) end
    return ffi.string(buffer, ret)
  end
end
if C.mknodat then
  function S.mknodat(fd, pathname, mode, dev)
    return retbool(C.mknodat(c.AT_FDCWD[fd], pathname, c.S_I[mode], getdev(dev) or 0))
  end
end
if C.utimensat then
  function S.utimensat(dirfd, path, ts, flags)
    if ts then ts = t.timespec2(ts) end -- TODO use mktype?
    return retbool(C.utimensat(c.AT_FDCWD[dirfd], path, ts, c.AT[flags]))
  end
end
if C.fstatat then
  function S.fstatat(fd, path, buf, flags)
    if not buf then buf = t.stat() end
    local ret, err = C.fstatat(c.AT_FDCWD[fd], path, buf, c.AT[flags])
    if ret == -1 then return nil, t.error(err or errno()) end
    return buf
  end
end
if C.fchmodat then
  function S.fchmodat(dirfd, pathname, mode, flags)
    return retbool(C.fchmodat(c.AT_FDCWD[dirfd], pathname, c.MODE[mode], c.AT[flags]))
  end
end
if C.openat then
  function S.openat(dirfd, pathname, flags, mode)
    return retfd(C.openat(c.AT_FDCWD[dirfd], pathname, c.O[flags], c.MODE[mode]))
  end
end

if C.fchroot then
  function S.fchroot(fd) return retbool(C.fchroot(getfd(fd))) end
end
if C.lchmod then
  function S.lchmod(path, mode) return retbool(C.lchmod(path, c.MODE[mode])) end
end

if C.fdatasync then
  function S.fdatasync(fd) return retbool(C.fdatasync(getfd(fd))) end
end
-- Linux does not have mkfifo syscalls, emulated
if C.mkfifo then
  function S.mkfifo(pathname, mode) return retbool(C.mkfifo(pathname, c.S_I[mode])) end
end
if C.mkfifoat then
  function S.mkfifoat(dirfd, pathname, mode) return retbool(C.mkfifoat(c.AT_FDCWD[dirfd], pathname, c.S_I[mode])) end
end
if C.utimes then
  function S.utimes(filename, ts)
    if ts then ts = t.timeval2(ts) end
    return retbool(C.utimes(filename, ts))
  end
end
if C.lutimes then
  function S.lutimes(filename, ts)
    if ts then ts = t.timeval2(ts) end
    return retbool(C.lutimes(filename, ts))
  end
end
if C.futimes then
  function S.futimes(fd, ts)
    if ts then ts = t.timeval2(ts) end
    return retbool(C.futimes(getfd(fd), ts))
  end
end

if C.getdents then
  function S.getdents(fd, buf, size)
    size = size or 4096 -- may have to be equal to at least block size of fs
    buf = buf or t.buffer(size)
    local ret, err = C.getdents(getfd(fd), buf, size)
    if ret == -1 then return nil, t.error(err or errno()) end
    return t.dirents(buf, ret)
  end
end
if C.futimens then
  function S.futimens(fd, ts)
    if ts then ts = t.timespec2(ts) end
    return retbool(C.futimens(getfd(fd), ts))
  end
end
if C.accept4 then
  function S.accept4(sockfd, addr, addrlen, flags)
    local saddr = pt.sockaddr(addr)
    if addr then addrlen = addrlen or t.socklen1() end
    return retfd(C.accept4(getfd(sockfd), saddr, addrlen, c.SOCK[flags]))
  end
end
if C.sigaction then
  function S.sigaction(signum, handler, oldact)
    if type(handler) == "string" or type(handler) == "function" then
      handler = {handler = handler, mask = "", flags = 0} -- simple case like signal
    end
    if handler then handler = mktype(t.sigaction, handler) end
    return retbool(C.sigaction(c.SIG[signum], handler, oldact))
  end
end
if C.getitimer then
  function S.getitimer(which, value)
    value = value or t.itimerval()
    local ret, err = C.getitimer(c.ITIMER[which], value)
    if ret == -1 then return nil, t.error(err or errno()) end
    return value
  end
end
if C.setitimer then
  function S.setitimer(which, it, oldtime)
    oldtime = oldtime or t.itimerval()
    local ret, err = C.setitimer(c.ITIMER[which], mktype(t.itimerval, it), oldtime)
    if ret == -1 then return nil, t.error(err or errno()) end
    return oldtime
  end
end
if C.clock_getres then
  function S.clock_getres(clk_id, ts)
    ts = ts or t.timespec()
    local ret, err = C.clock_getres(c.CLOCK[clk_id], ts)
    if ret == -1 then return nil, t.error(err or errno()) end
    return ts
  end
end
if C.clock_gettime then
  function S.clock_gettime(clk_id, ts)
    ts = ts or t.timespec()
    local ret, err = C.clock_gettime(c.CLOCK[clk_id], ts)
    if ret == -1 then return nil, t.error(err or errno()) end
    return ts
  end
end
if C.clock_settime then
  function S.clock_settime(clk_id, ts)
    ts = mktype(t.timespec, ts)
    return retbool(C.clock_settime(c.CLOCK[clk_id], ts))
  end
end
if C.clock_nanosleep then
  function S.clock_nanosleep(clk_id, flags, req, rem)
    rem = rem or t.timespec()
    local ret, err = C.clock_nanosleep(c.CLOCK[clk_id], c.TIMER[flags or 0], mktype(t.timespec, req), rem)
    if ret == -1 then
      if (err or errno()) == c.E.INTR then return true, nil, rem else return nil, t.error(err or errno()) end
    end
    return true -- no time remaining
  end
end

if C.timer_create then
  function S.timer_create(clk_id, sigev, timerid)
    timerid = timerid or t.timer()
    if sigev then sigev = mktype(t.sigevent, sigev) end
    local ret, err = C.timer_create(c.CLOCK[clk_id], sigev, timerid:gettimerp())
    if ret == -1 then return nil, t.error(err or errno()) end
    return timerid
  end
  function S.timer_delete(timerid) return retbool(C.timer_delete(timerid:gettimer())) end
  function S.timer_settime(timerid, flags, new_value, old_value)
    if old_value ~= false then old_value = old_value or t.itimerspec() else old_value = nil end
    new_value = mktype(t.itimerspec, new_value)
    local ret, err = C.timer_settime(timerid:gettimer(), c.TIMER[flags], new_value, old_value)
    if ret == -1 then return nil, t.error(err or errno()) end
    return true, nil, old_value
  end
  function S.timer_gettime(timerid, curr_value)
    curr_value = curr_value or t.itimerspec()
    local ret, err = C.timer_gettime(timerid:gettimer(), curr_value)
    if ret == -1 then return nil, t.error(err or errno()) end
    return curr_value
  end
  function S.timer_getoverrun(timerid) return retnum(C.timer_getoverrun(timerid:gettimer())) end
end

-- legacy in many OSs, implemented using recvfrom, sendto
if C.send then
  function S.send(fd, buf, count, flags) return retnum(C.send(getfd(fd), buf, count, c.MSG[flags])) end
end
if C.recv then
  function S.recv(fd, buf, count, flags) return retnum(C.recv(getfd(fd), buf, count, c.MSG[flags], false)) end
end

-- TODO not sure about this interface, maybe return rem as extra parameter see #103
if C.nanosleep then
  function S.nanosleep(req, rem)
    rem = rem or t.timespec()
    local ret, err = C.nanosleep(mktype(t.timespec, req), rem)
    if ret == -1 then
      if (err or errno()) == c.E.INTR then return true, nil, rem else return nil, t.error(err or errno()) end
    end
    return true -- no time remaining
  end
end

-- getpagesize might be a syscall, or in libc, or may not exist
if C.getpagesize then
  function S.getpagesize() return retnum(C.getpagesize()) end
end

if C.syncfs then
  function S.syncfs(fd) return retbool(C.syncfs(getfd(fd))) end
end

-- although the pty functions are not syscalls, we include here, like eg shm functions, as easier to provide as methods on fds
-- Freebsd has a syscall, other OSs use /dev/ptmx
if C.posix_openpt then
  function S.posix_openpt(flags) return retfd(C.posix_openpt(c.O[flags])) end
else
  function S.posix_openpt(flags) return S.open("/dev/ptmx", flags) end
end
S.openpt = S.posix_openpt

function S.isatty(fd)
  local tc, err = S.tcgetattr(fd)
  if tc then return true else return nil, err end
end

if c.IOCTL.TIOCGSID then -- OpenBSD only has in legacy ioctls
  function S.tcgetsid(fd) return S.ioctl(fd, "TIOCGSID") end
end

-- now call OS specific for non-generic calls
local hh = {
  ret64 = ret64, retnum = retnum, retfd = retfd, retbool = retbool, retptr = retptr, retiter = retiter
}

if (abi.rump and abi.types == "netbsd") or (not abi.rump and abi.bsd) then
  S = require("syscall.bsd.syscalls")(S, hh, c, C, types)
end
S = require("syscall." .. abi.os .. ".syscalls")(S, hh, c, C, types)

return S

end

return {init = init}

