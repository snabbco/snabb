-- choose correct syscalls for OS, plus shared calls
-- note that where functions are identical if present but may be missing they can also go here

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit

local function init(abi, c, C, types, ioctl, fcntl)

local ffi = require "ffi"
local bit = require "bit"

local h = require "syscall.helpers"

local t, pt, s = types.t, types.pt, types.s

local S = {}

-- helpers

local errpointer
if abi.abi64 then errpointer = pt.void(0xffffffffffffffffULL) else errpointer = pt.void(0xffffffff) end
local err64 = 0xffffffffffffffffULL

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

-- generic iterators; these count down to 0 so need no closure
local function reviter(array, i)
  i = i - 1
  if i >= 0 then return i, array[i] end
end

local function retiter(ret, array)
  ret = tonumber(ret)
  if ret == -1 then return nil, t.error() end
  return reviter, array, ret
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
function S.flock(fd, operation) return retbool(C.flock(getfd(fd), c.LOCK[operation])) end
-- TODO read should have consistent return type but then will differ from other calls.
function S.read(fd, buf, count)
  if buf then return retnum(C.read(getfd(fd), buf, count or #buf or 4096)) end -- user supplied a buffer, standard usage
  count = count or 4096
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
-- TODO maybe this not going along with OS is confusing?
if C.dup3 then
  -- TODO dup3 can have a race condition (see Linux man page) although Musl fixes, appears eglibc does not
  -- TODO also emulate if nosys?
  function S.dup(oldfd, newfd, flags)
    if not newfd then return retfd(C.dup(getfd(oldfd))) end
    if not flags then return retfd(C.dup2(getfd(oldfd), getfd(newfd))) end
    return retfd(C.dup3(getfd(oldfd), getfd(newfd), flags))
  end
else -- OSX does not have dup3
  function S.dup(oldfd, newfd, flags)
    assert(not flags, "TODO: emulate dup3 behaviour on OSX")
    if not newfd then return retfd(C.dup(getfd(oldfd))) end
    return retfd(C.dup2(getfd(oldfd), getfd(newfd))) -- TODO set flags on newfd
  end
end
S.dup2 = S.dup
S.dup3 = S.dup
function S.sendto(fd, buf, count, flags, addr, addrlen)
  if not addr then addrlen = 0 end
  local saddr = pt.sockaddr(addr)
  return retnum(C.sendto(getfd(fd), buf, count or #buf, c.MSG[flags], saddr, addrlen or #addr))
end
function S.recvfrom(fd, buf, count, flags, addr, addrlen)
  if not addr then addrlen = 0 end
  addrlen = addrlen or #addr
  if type(addrlen) == "number" then addrlen = t.socklen1(addrlen) end
  local saddr = pt.sockaddr(addr)
  return retnum(C.recvfrom(getfd(fd), buf, count or #buf, c.MSG[flags], saddr, addrlen))
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
-- TODO {get,set}sockopt may need better type handling see new sockopt file
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
function S.bind(sockfd, addr, addrlen)
  local saddr = pt.sockaddr(addr)
  return retbool(C.bind(getfd(sockfd), saddr, addrlen or #addr))
end
function S.listen(sockfd, backlog) return retbool(C.listen(getfd(sockfd), backlog or c.SOMAXCONN)) end
function S.connect(sockfd, addr, addrlen)
  local saddr = pt.sockaddr(addr)
  return retbool(C.connect(getfd(sockfd), saddr, addrlen or #addr))
end
function S.getsockname(sockfd, addr, addrlen)
  addr = addr or t.sockaddr_storage()
  addrlen = addrlen or t.socklen1(#addr)
  local saddr = pt.sockaddr(addr)
  local ret = C.getsockname(getfd(sockfd), saddr, addrlen)
  if ret == -1 then return nil, t.error() end
  return t.sa(addr, addrlen[0])
end
function S.getpeername(sockfd, addr, addrlen)
  addr = addr or t.sockaddr_storage()
  addrlen = addrlen or t.socklen1(#addr)
  local saddr = pt.sockaddr(addr)
  local ret = C.getpeername(getfd(sockfd), saddr, addrlen)
  if ret == -1 then return nil, t.error() end
  return t.sa(addr, addrlen[0])
end
function S.shutdown(sockfd, how) return retbool(C.shutdown(getfd(sockfd), c.SHUT[how])) end
function S.poll(fds, timeout) return retnum(C.poll(fds.pfd, #fds, timeout or -1)) end

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
function S.select(sel, timeout) -- note same structure as returned
  local r, w, e
  local nfds = 0
  if timeout then timeout = mktype(t.timeval, timeout) end
  r, nfds = mkfdset(sel.readfds or {}, nfds or 0)
  w, nfds = mkfdset(sel.writefds or {}, nfds)
  e, nfds = mkfdset(sel.exceptfds or {}, nfds)
  local ret = C.select(nfds, r, w, e, timeout)
  if ret == -1 then return nil, t.error() end
  return {readfds = fdisset(sel.readfds or {}, r), writefds = fdisset(sel.writefds or {}, w),
          exceptfds = fdisset(sel.exceptfds or {}, e), count = tonumber(ret)}
end

-- TODO note that actual syscall modifies timeout, which is non standard, like ppoll
function S.pselect(sel, timeout, set) -- note same structure as returned
  local r, w, e
  local nfds = 0
  if timeout then timeout = mktype(t.timespec, timeout) end
  if set then set = mktype(t.sigset, set) end
  r, nfds = mkfdset(sel.readfds or {}, nfds or 0)
  w, nfds = mkfdset(sel.writefds or {}, nfds)
  e, nfds = mkfdset(sel.exceptfds or {}, nfds)
  local ret = C.pselect(nfds, r, w, e, timeout, set)
  if ret == -1 then return nil, t.error() end
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
function S.mlockall(flags) return retbool(C.mlockall(c.MCL[flags])) end
function S.munlockall() return retbool(C.munlockall()) end
function S.madvise(addr, length, advice) return retbool(C.madvise(addr, length, c.MADV[advice])) end

function S.ioctl(d, request, argp)
  local read, singleton = false, false
  local name = request
  if type(name) == "string" then
    request = ioctl[name]
  end
  if type(request) == "table" then
    local write = request.write
    local tp = request.type
    read = request.read
    singleton = request.singleton
    request = request.number
    if type(argp) ~= "string" and type(argp) ~= "cdata" then
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
  local ret = C.ioctl(getfd(d), request, argp)
  if ret == -1 then return nil, t.error() end
  if read and singleton then return argp[0] end
  if read then return argp end
  return true -- will need override for few linux ones that return numbers
end

if C.pipe2 then
  function S.pipe(flags, fd2)
    fd2 = fd2 or t.int2()
    local ret = C.pipe2(fd2, c.OPIPE[flags])
    if ret == -1 then return nil, t.error() end
    return t.pipe(fd2)
  end
else
  function S.pipe(flags, fd2)
    assert(not flags, "TODO add pipe flags emulation") -- TODO emulate flags from Linux pipe2
    fd2 = fd2 or t.int2()
    local ret = C.pipe(fd2)
    if ret == -1 then return nil, t.error() end
    return t.pipe(fd2)
  end
end

function S.nanosleep(req, rem)
  rem = rem or t.timespec()
  local ret = C.nanosleep(mktype(t.timespec, req), rem)
  if ret == -1 then
    if ffi.errno() == c.E.INTR then return rem else return nil, t.error() end
  end
  return true
end

function S.gettimeofday(tv)
  tv = tv or t.timeval() -- note it is faster to pass your own tv if you call a lot
  local ret = C.gettimeofday(tv, nil)
  if ret == -1 then return nil, t.error() end
  return tv
end

function S.getrusage(who, ru)
  ru = ru or t.rusage()
  local ret = C.getrusage(c.RUSAGE[who], ru)
  if ret == -1 then return nil, t.error() end
  return ru
end

function S.fork() return retnum(C.fork()) end
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
  local ret = C.wait4(pid, status, c.W[options], ru)
  if ret == -1 then return nil, t.error() end
  return t.wait(ret, status[0], ru)
end

function S.setpriority(which, who, prio) return retbool(C.setpriority(c.PRIO[which], who or 0, prio)) end

-- although the pty functions are not syscalls, we include here, like eg shm functions, as easier to provide as methods on fds
function S.posix_openpt(flags) return S.open("/dev/ptmx", flags) end
S.openpt = S.posix_openpt
function S.isatty(fd)
  local tc = S.tcgetattr(fd)
  if tc then return true else return false end
end

-- now call OS specific for non-generic calls
local hh = {
  istype = istype, mktype = mktype, getfd = getfd,
  ret64 = ret64, retnum = retnum, retfd = retfd, retbool = retbool, retptr = retptr, retiter = retiter
}

local S = require("syscall." .. abi.os .. ".syscalls")(S, hh, abi, c, C, types, ioctl)

return S

end

return {init = init}

