-- This is the actual system calls for Linux

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local abi = require "syscall.abi"

return function(S, hh, c, C, types)

local ret64, retnum, retfd, retbool, retptr, retiter = hh.ret64, hh.retnum, hh.retfd, hh.retbool, hh.retptr, hh.retiter

local ffi = require "ffi"
local errno = ffi.errno

local bit = require "syscall.bit"

local t, pt, s = types.t, types.pt, types.s

local h = require "syscall.helpers"

local istype, mktype, getfd = h.istype, h.mktype, h.getfd

if abi.abi32 then
  -- override open call with largefile -- TODO move this hack to c.lua instead
  function S.open(pathname, flags, mode)
    flags = bit.bor(c.O[flags], c.O.LARGEFILE)
    return retfd(C.open(pathname, flags, c.MODE[mode]))
  end
  function S.openat(dirfd, pathname, flags, mode)
    flags = bit.bor(c.O[flags], c.O.LARGEFILE)
    return retfd(C.openat(c.AT_FDCWD[dirfd], pathname, flags, c.MODE[mode]))
  end
end

function S.pause() return retbool(C.pause()) end

function S.acct(filename) return retbool(C.acct(filename)) end

function S.getpriority(which, who)
  local ret, err = C.getpriority(c.PRIO[which], who or 0)
  if ret == -1 then return nil, t.error(err or errno()) end
  return 20 - ret -- adjust for kernel returned values as this is syscall not libc
end

-- we could allocate ptid, ctid, tls if required in flags instead. TODO add signal into flag parsing directly
function S.clone(flags, signal, stack, ptid, tls, ctid)
  flags = c.CLONE[flags] + c.SIG[signal]
  return retnum(C.clone(flags, stack, ptid, tls, ctid))
end

function S.unshare(flags) return retbool(C.unshare(c.CLONE[flags])) end
function S.setns(fd, nstype) return retbool(C.setns(getfd(fd), c.CLONE[nstype])) end

-- note that this is not strictly the syscall that has some other arguments, but has same functionality
function S.reboot(cmd) return retbool(C.reboot(c.LINUX_REBOOT_CMD[cmd])) end

function S.wait(status)
  status = status or t.int1()
  local ret, err = C.wait(status)
  if ret == -1 then return nil, t.error(err or errno()) end
  return ret, nil, t.waitstatus(status[0])
end
function S.waitpid(pid, options, status) -- note order of arguments changed as rarely supply status
  status = status or t.int1()
  local ret, err = C.waitpid(c.WAIT[pid], status, c.W[options])
  if ret == -1 then return nil, t.error(err or errno()) end
  return ret, nil, t.waitstatus(status[0])
end
function S.waitid(idtype, id, options, infop) -- note order of args, as usually dont supply infop
  if not infop then infop = t.siginfo() end
  local ret, err = C.waitid(c.P[idtype], id or 0, infop, c.W[options])
  if ret == -1 then return nil, t.error(err or errno()) end
  return infop
end

function S.exit(status) C.exit_group(c.EXIT[status]) end

function S.sync_file_range(fd, offset, count, flags)
  return retbool(C.sync_file_range(getfd(fd), offset, count, c.SYNC_FILE_RANGE[flags]))
end

-- not a syscall in Linux but method of implementation slightly non standard so here not compat
function S.futimens(fd, times)
  return S.utimensat(fd, nil, times, 0)
end

function S.getcwd(buf, size)
  size = size or c.PATH_MAX
  buf = buf or t.buffer(size)
  local ret, err = C.getcwd(buf, size)
  if ret == -1 then return nil, t.error(err or errno()) end
  return ffi.string(buf)
end

function S.statfs(path)
  local st = t.statfs()
  local ret, err = C.statfs(path, st)
  if ret == -1 then return nil, t.error(err or errno()) end
  return st
end

function S.fstatfs(fd)
  local st = t.statfs()
  local ret, err = C.fstatfs(getfd(fd), st)
  if ret == -1 then return nil, t.error(err or errno()) end
  return st
end

function S.mremap(old_address, old_size, new_size, flags, new_address)
  return retptr(C.mremap(old_address, old_size, new_size, c.MREMAP[flags], new_address))
end
function S.fadvise(fd, advice, offset, len) -- note argument order TODO change back?
  return retbool(C.fadvise64(getfd(fd), offset or 0, len or 0, c.POSIX_FADV[advice]))
end
function S.fallocate(fd, mode, offset, len)
  return retbool(C.fallocate(getfd(fd), c.FALLOC_FL[mode], offset or 0, len))
end
function S.posix_fallocate(fd, offset, len) return S.fallocate(fd, 0, offset, len) end
function S.readahead(fd, offset, count) return retbool(C.readahead(getfd(fd), offset, count)) end

function S.accept4(sockfd, addr, addrlen, flags)
  local saddr = pt.sockaddr(addr)
  return retfd(C.accept4(getfd(sockfd), saddr, addrlen, c.SOCK[flags]))
end

-- TODO change to type?
function S.uname()
  local u = t.utsname()
  local ret, err = C.uname(u)
  if ret == -1 then return nil, t.error(err or errno()) end
  return {sysname = ffi.string(u.sysname), nodename = ffi.string(u.nodename), release = ffi.string(u.release),
          version = ffi.string(u.version), machine = ffi.string(u.machine), domainname = ffi.string(u.domainname)}
end

function S.sethostname(s) -- only accept Lua string, do not see use case for buffer as well
  return retbool(C.sethostname(s, #s))
end

function S.setdomainname(s)
  return retbool(C.setdomainname(s, #s))
end

function S.settimeofday(tv) return retbool(C.settimeofday(tv, nil)) end

function S.time(time) return retnum(C.time(time)) end

function S.sysinfo(info)
  info = info or t.sysinfo()
  local ret, err = C.sysinfo(info)
  if ret == -1 then return nil, t.error(err or errno()) end
  return info
end

-- this is recommended way to size buffers for xattr
local function growattrbuf(f, a, b)
  local len = 512
  local buffer = t.buffer(len)
  local ret, err
  repeat
    if b then
      ret, err = f(a, b, buffer, len)
    else
      ret, err = f(a, buffer, len)
    end
    ret = tonumber(ret)
    if ret == -1 and (err or errno()) ~= c.E.RANGE then return nil, t.error(err or errno()) end
    if ret == -1 then
      len = len * 2
      buffer = t.buffer(len)
    end
  until ret >= 0

  return ffi.string(buffer, ret)
end

local function lattrbuf(sys, a)
  local s, err = growattrbuf(sys, a)
  if not s then return nil, err end
  local tab = h.split('\0', s)
  tab[#tab] = nil -- there is a trailing \0 so one extra
  return tab
end

function S.listxattr(path) return lattrbuf(C.listxattr, path) end
function S.llistxattr(path) return lattrbuf(C.llistxattr, path) end
function S.flistxattr(fd) return lattrbuf(C.flistxattr, getfd(fd)) end

function S.setxattr(path, name, value, flags)
  return retbool(C.setxattr(path, name, value, #value, c.XATTR[flags]))
end
function S.lsetxattr(path, name, value, flags)
  return retbool(C.lsetxattr(path, name, value, #value, c.XATTR[flags]))
end
function S.fsetxattr(fd, name, value, flags)
  return retbool(C.fsetxattr(getfd(fd), name, value, #value, c.XATTR[flags]))
end

function S.getxattr(path, name) return growattrbuf(C.getxattr, path, name) end
function S.lgetxattr(path, name) return growattrbuf(C.lgetxattr, path, name) end
function S.fgetxattr(fd, name) return growattrbuf(C.fgetxattr, getfd(fd), name) end

function S.removexattr(path, name) return retbool(C.removexattr(path, name)) end
function S.lremovexattr(path, name) return retbool(C.lremovexattr(path, name)) end
function S.fremovexattr(fd, name) return retbool(C.fremovexattr(getfd(fd), name)) end

-- helper function to set and return attributes in tables
-- TODO this would make more sense as types?
-- TODO listxattr should return an iterator not a table?
local function xattr(list, get, set, remove, path, t)
  local l, err = list(path)
  if not l then return nil, err end
  if not t then -- no table, so read
    local r = {}
    for _, name in ipairs(l) do
      r[name] = get(path, name) -- ignore errors
    end
    return r
  end
  -- write
  for _, name in ipairs(l) do
    if t[name] then
      set(path, name, t[name]) -- ignore errors, replace
      t[name] = nil
    else
      remove(path, name)
    end
  end
  for name, value in pairs(t) do
    set(path, name, value) -- ignore errors, create
  end
  return true
end

function S.xattr(path, t) return xattr(S.listxattr, S.getxattr, S.setxattr, S.removexattr, path, t) end
function S.lxattr(path, t) return xattr(S.llistxattr, S.lgetxattr, S.lsetxattr, S.lremovexattr, path, t) end
function S.fxattr(fd, t) return xattr(S.flistxattr, S.fgetxattr, S.fsetxattr, S.fremovexattr, fd, t) end

function S.signalfd(set, flags, fd) -- note different order of args, as fd usually empty. See also signalfd_read()
  set = mktype(t.sigset, set)
  if fd then fd = getfd(fd) else fd = -1 end
  return retfd(C.signalfd(fd, set, c.SFD[flags]))
end

-- note that syscall does return timeout remaining but libc does not, due to standard prototype TODO use syscall
-- note this is the only difference with NetBSD pollts, so could merge them
function S.ppoll(fds, timeout, set)
  if timeout then timeout = mktype(t.timespec, timeout) end
  if set then set = mktype(t.sigset, set) end
  return retnum(C.ppoll(fds.pfd, #fds, timeout, set))
end

function S.mount(source, target, fstype, mountflags, data)
  return retbool(C.mount(source or "none", target, fstype, c.MS[mountflags], data))
end

function S.umount(target, flags)
  return retbool(C.umount2(target, c.UMOUNT[flags]))
end

function S.prlimit(pid, resource, new_limit, old_limit)
  if new_limit then new_limit = mktype(t.rlimit, new_limit) end
  old_limit = old_limit or t.rlimit()
  local ret, err = C.prlimit64(pid or 0, c.RLIMIT[resource], new_limit, old_limit)
  if ret == -1 then return nil, t.error(err or errno()) end
  return old_limit
end

function S.epoll_create(flags)
  return retfd(C.epoll_create1(c.EPOLLCREATE[flags]))
end

function S.epoll_ctl(epfd, op, fd, event)
  if type(event) == "string" or type(event) == "number" then event = {events = event, fd = getfd(fd)} end
  event = mktype(t.epoll_event, event)
  return retbool(C.epoll_ctl(getfd(epfd), c.EPOLL_CTL[op], getfd(fd), event))
end

function S.epoll_wait(epfd, events, timeout)
  local ret, err = C.epoll_wait(getfd(epfd), events.ep, #events, timeout or -1)
  return retiter(ret, err, events.ep)
end

function S.epoll_pwait(epfd, events, timeout, sigmask)
  if sigmask then sigmask = mktype(t.sigset, sigmask) end
  local ret, err = C.epoll_pwait(getfd(epfd), events.ep, #events, timeout or -1, sigmask)
  return retiter(ret, err, events.ep)
end

function S.splice(fd_in, off_in, fd_out, off_out, len, flags)
  local offin, offout = off_in, off_out
  if off_in and not ffi.istype(t.off1, off_in) then
    offin = t.off1()
    offin[0] = off_in
  end
  if off_out and not ffi.istype(t.off1, off_out) then
    offout = t.off1()
    offout[0] = off_out
  end
  return retnum(C.splice(getfd(fd_in), offin, getfd(fd_out), offout, len, c.SPLICE_F[flags]))
end

function S.vmsplice(fd, iov, flags)
  iov = mktype(t.iovecs, iov)
  return retnum(C.vmsplice(getfd(fd), iov.iov, #iov, c.SPLICE_F[flags]))
end

function S.tee(fd_in, fd_out, len, flags)
  return retnum(C.tee(getfd(fd_in), getfd(fd_out), len, c.SPLICE_F[flags]))
end

function S.inotify_init(flags) return retfd(C.inotify_init1(c.IN_INIT[flags])) end
function S.inotify_add_watch(fd, pathname, mask) return retnum(C.inotify_add_watch(getfd(fd), pathname, c.IN[mask])) end
function S.inotify_rm_watch(fd, wd) return retbool(C.inotify_rm_watch(getfd(fd), wd)) end

function S.sendfile(out_fd, in_fd, offset, count)
  if type(offset) == "number" then
    offset = t.off1(offset)
  end
  return retnum(C.sendfile(getfd(out_fd), getfd(in_fd), offset, count))
end

function S.eventfd(initval, flags) return retfd(C.eventfd(initval or 0, c.EFD[flags])) end

function S.getitimer(which, value)
  value = value or t.itimerval()
  local ret, err = C.getitimer(c.ITIMER[which], value)
  if ret == -1 then return nil, t.error(err or errno()) end
  return value
end

function S.setitimer(which, it, oldtime)
  oldtime = oldtime or t.itimerval()
  local ret, err = C.setitimer(c.ITIMER[which], mktype(t.itimerval, it), oldtime)
  if ret == -1 then return nil, t.error(err or errno()) end
  return oldtime
end

function S.timerfd_create(clockid, flags)
  return retfd(C.timerfd_create(c.CLOCK[clockid], c.TFD[flags]))
end

function S.timerfd_settime(fd, flags, it, oldtime)
  oldtime = oldtime or t.itimerspec()
  local ret, err = C.timerfd_settime(getfd(fd), c.TFD_TIMER[flags], mktype(t.itimerspec, it), oldtime)
  if ret == -1 then return nil, t.error(err or errno()) end
  return oldtime
end

function S.timerfd_gettime(fd, curr_value)
  curr_value = curr_value or t.itimerspec()
  local ret, err = C.timerfd_gettime(getfd(fd), curr_value)
  if ret == -1 then return nil, t.error(err or errno()) end
  return curr_value
end

function S.pivot_root(new_root, put_old) return retbool(C.pivot_root(new_root, put_old)) end

-- aio functions
function S.io_setup(nr_events)
  local ctx = t.aio_context1()
  local ret, err = C.io_setup(nr_events, ctx)
  if ret == -1 then return nil, t.error(err or errno()) end
  return ctx[0]
end

function S.io_destroy(ctx) return retbool(C.io_destroy(ctx)) end

function S.io_cancel(ctx, iocb, result)
  result = result or t.io_event()
  local ret, err = C.io_cancel(ctx, iocb, result)
  if ret == -1 then return nil, t.error(err or errno()) end
  return result
end

function S.io_getevents(ctx, min, events, timeout)
  if timeout then timeout = mktype(t.timespec, timeout) end
  local ret, err = C.io_getevents(ctx, min or events.count, events.count, events.ev, timeout)
  return retiter(ret, err, events.ev)
end

-- iocb must persist until retrieved (as we get pointer), so cannot be passed as table must take t.iocb_array
function S.io_submit(ctx, iocb)
  return retnum(C.io_submit(ctx, iocb.ptrs, iocb.nr))
end

-- TODO prctl should be in a seperate file like ioctl fnctl (this is a Linux only interface)
-- map for valid options for arg2
local prctlmap = {
  [c.PR.CAPBSET_READ] = c.CAP,
  [c.PR.CAPBSET_DROP] = c.CAP,
  [c.PR.SET_ENDIAN] = c.PR_ENDIAN,
  [c.PR.SET_FPEMU] = c.PR_FPEMU,
  [c.PR.SET_FPEXC] = c.PR_FP_EXC,
  [c.PR.SET_PDEATHSIG] = c.SIG,
  --[c.PR.SET_SECUREBITS] = c.SECBIT, -- TODO not defined yet
  [c.PR.SET_TIMING] = c.PR_TIMING,
  [c.PR.SET_TSC] = c.PR_TSC,
  [c.PR.SET_UNALIGN] = c.PR_UNALIGN,
  [c.PR.MCE_KILL] = c.PR_MCE_KILL,
  [c.PR.SET_SECCOMP] = c.SECCOMP_MODE,
  [c.PR.SET_NO_NEW_PRIVS] = h.booltoc,
}

local prctlrint = { -- returns an integer directly TODO add metatables to set names
  [c.PR.GET_DUMPABLE] = true,
  [c.PR.GET_KEEPCAPS] = true,
  [c.PR.CAPBSET_READ] = true,
  [c.PR.GET_TIMING] = true,
  [c.PR.GET_SECUREBITS] = true,
  [c.PR.MCE_KILL_GET] = true,
  [c.PR.GET_SECCOMP] = true,
  [c.PR.GET_NO_NEW_PRIVS] = true,
}

local prctlpint = { -- returns result in a location pointed to by arg2
  [c.PR.GET_ENDIAN] = true,
  [c.PR.GET_FPEMU] = true,
  [c.PR.GET_FPEXC] = true,
  [c.PR.GET_PDEATHSIG] = true,
  [c.PR.GET_UNALIGN] = true,
}

-- this is messy, TODO clean up, its own file see above
function S.prctl(option, arg2, arg3, arg4, arg5)
  local i, name
  option = c.PR[option]
  local m = prctlmap[option]
  if m then arg2 = m[arg2] end
  if option == c.PR.MCE_KILL and arg2 == c.PR.MCE_KILL_SET then arg3 = c.PR_MCE_KILL_OPT[arg3]
  elseif prctlpint[option] then
    i = t.int1()
    arg2 = ffi.cast(t.ulong, i)
  elseif option == c.PR.GET_NAME then
    name = t.buffer(16)
    arg2 = ffi.cast(t.ulong, name)
  elseif option == c.PR.SET_NAME then
    if type(arg2) == "string" then arg2 = ffi.cast(t.ulong, arg2) end
  elseif option == c.PR.SET_SECCOMP then
    arg3 = t.intptr(arg3 or 0)
  end
  local ret = C.prctl(option, arg2 or 0, arg3 or 0, arg4 or 0, arg5 or 0)
  if ret == -1 then return nil, t.error() end
  if prctlrint[option] then return ret end
  if prctlpint[option] then return i[0] end
  if option == c.PR.GET_NAME then
    if name[15] ~= 0 then return ffi.string(name, 16) end -- actually, 15 bytes seems to be longest, aways 0 terminated
    return ffi.string(name)
  end
  return true
end

function S.syslog(tp, buf, len)
  if not buf and (tp == 2 or tp == 3 or tp == 4) then
    if not len then
      -- this is the glibc name for the syslog syscall
      len = C.klogctl(10, nil, 0) -- get size so we can allocate buffer
      if len == -1 then return nil, t.error() end
    end
    buf = t.buffer(len)
  end
  local ret, err = C.klogctl(tp, buf or nil, len or 0)
  if ret == -1 then return nil, t.error(err or errno()) end
  if tp == 9 or tp == 10 then return tonumber(ret) end
  if tp == 2 or tp == 3 or tp == 4 then return ffi.string(buf, ret) end
  return true
end

function S.adjtimex(a)
  a = mktype(t.timex, a)
  local ret, err = C.adjtimex(a)
  if ret == -1 then return nil, t.error(err or errno()) end
  return t.adjtimex(ret, a)
end

function S.clock_getres(clk_id, ts)
  ts = mktype(t.timespec, ts)
  local ret, err = C.clock_getres(c.CLOCK[clk_id], ts)
  if ret == -1 then return nil, t.error(err or errno()) end
  return ts
end

function S.clock_gettime(clk_id, ts)
  ts = mktype(t.timespec, ts)
  local ret, err = C.clock_gettime(c.CLOCK[clk_id], ts)
  if ret == -1 then return nil, t.error(err or errno()) end
  return ts
end

function S.clock_settime(clk_id, ts)
  ts = mktype(t.timespec, ts)
  return retbool(C.clock_settime(c.CLOCK[clk_id], ts))
end

-- TODO see man page if ABSTIME then remaining time never returned
function S.clock_nanosleep(clk_id, flags, req, rem)
  rem = rem or t.timespec()
  local ret, err = C.clock_nanosleep(c.CLOCK[clk_id], c.TIMER[flags], mktype(t.timespec, req), rem)
  if ret == -1 then
    if (err or errno()) == c.E.INTR then return rem else return nil, t.error(err or errno()) end
  end
  return 0 -- no time remaining
end

function S.alarm(s) return C.alarm(s) end

function S.sigaction(signum, handler, oldact)
  if type(handler) == "string" or type(handler) == "function" then
    handler = {handler = handler, mask = "", flags = c.SA.RESTART} -- simple case like signal
  end
  if handler then handler = mktype(t.sigaction, handler) end
  return retbool(C.sigaction(c.SIG[signum], handler, oldact))
end

function S.setreuid(ruid, euid) return retbool(C.setreuid(ruid, euid)) end
function S.setregid(rgid, egid) return retbool(C.setregid(rgid, egid)) end

function S.getresuid(ruid, euid, suid)
  ruid, euid, suid = ruid or t.uid1(), euid or t.uid1(), suid or t.uid1()
  local ret, err = C.getresuid(ruid, euid, suid)
  if ret == -1 then return nil, t.error(err or errno()) end
  return true, nil, ruid[0], euid[0], suid[0]
end
function S.getresgid(rgid, egid, sgid)
  rgid, egid, sgid = rgid or t.gid1(), egid or t.gid1(), sgid or t.gid1()
  local ret, err = C.getresgid(rgid, egid, sgid)
  if ret == -1 then return nil, t.error(err or errno()) end
  return true, nil, rgid[0], egid[0], sgid[0]
end
function S.setresuid(ruid, euid, suid) return retbool(C.setresuid(ruid, euid, suid)) end
function S.setresgid(rgid, egid, sgid) return retbool(C.setresgid(rgid, egid, sgid)) end

function S.vhangup() return retbool(C.vhangup()) end

function S.swapon(path, swapflags) return retbool(C.swapon(path, c.SWAP_FLAG[swapflags])) end
function S.swapoff(path) return retbool(C.swapoff(path)) end

-- capabilities. Somewhat complex kernel interface due to versioning, Posix requiring malloc in API.
-- only support version 3, should be ok for recent kernels, or pass your own hdr, data in
-- to detect capability API version, pass in hdr with empty version, version will be set
function S.capget(hdr, data) -- normally just leave as nil for get, can pass pid in
  hdr = istype(t.user_cap_header, hdr) or t.user_cap_header(c.LINUX_CAPABILITY_VERSION[3], hdr or 0)
  if not data and hdr.version ~= 0 then data = t.user_cap_data2() end
  local ret, err = C.capget(hdr, data)
  if ret == -1 then return nil, t.error(err or errno()) end
  if not data then return hdr end
  return t.capabilities(hdr, data)
end

function S.capset(hdr, data)
  if ffi.istype(t.capabilities, hdr) then hdr, data = hdr:hdrdata() end
  return retbool(C.capset(hdr, data))
end

function S.getcpu(cpu, node)
  cpu = cpu or t.uint1()
  node = node or t.uint1()
  local ret, err = C.getcpu(cpu, node)
  if ret == -1 then return nil, t.error(err or errno()) end
  return {cpu = cpu[0], node = node[0]}
end

function S.sched_getscheduler(pid) return retnum(C.sched_getscheduler(pid or 0)) end
function S.sched_setscheduler(pid, policy, param)
  param = mktype(t.sched_param, param or 0)
  return retbool(C.sched_setscheduler(pid or 0, c.SCHED[policy], param))
end
function S.sched_yield() return retbool(C.sched_yield()) end

function S.sched_getaffinity(pid, mask, len) -- note len last as rarely used. All parameters optional
  mask = mktype(t.cpu_set, mask)
  local ret, err = C.sched_getaffinity(pid or 0, len or s.cpu_set, mask)
  if ret == -1 then return nil, t.error(err or errno()) end
  return mask
end

function S.sched_setaffinity(pid, mask, len) -- note len last as rarely used
  return retbool(C.sched_setaffinity(pid or 0, len or s.cpu_set, mktype(t.cpu_set, mask)))
end

function S.sched_get_priority_max(policy) return retnum(C.sched_get_priority_max(c.SCHED[policy])) end
function S.sched_get_priority_min(policy) return retnum(C.sched_get_priority_min(c.SCHED[policy])) end

function S.sched_setparam(pid, param)
  return retbool(C.sched_setparam(pid or 0, mktype(t.sched_param, param or 0)))
end
function S.sched_getparam(pid, param)
  param = mktype(t.sched_param, param or 0)
  local ret, err = C.sched_getparam(pid or 0, param)
  if ret == -1 then return nil, t.error(err or errno()) end
  return param.sched_priority -- only one useful parameter
end

function S.sched_rr_get_interval(pid, ts)
  ts = mktype(t.timespec, ts)
  local ret, err = C.sched_rr_get_interval(pid or 0, ts)
  if ret == -1 then return nil, t.error(err or errno()) end
  return ts
end

-- POSIX message queues. Note there is no mq_close as it is just close in Linux
function S.mq_open(name, flags, mode, attr)
  local ret, err = C.mq_open(name, c.O[flags], c.MODE[mode], mktype(t.mq_attr, attr))
  if ret == -1 then return nil, t.error(err or errno()) end
  return t.mqd(ret)
end

function S.mq_unlink(name)
  return retbool(C.mq_unlink(name))
end

function S.mq_getsetattr(mqd, new, old) -- provided for completeness, but use getattr, setattr which are methods
  return retbool(C.mq_getsetattr(getfd(mqd), new, old))
end

function S.mq_timedsend(mqd, msg_ptr, msg_len, msg_prio, abs_timeout)
  if abs_timeout then abs_timeout = mktype(t.timespec, abs_timeout) end
  return retbool(C.mq_timedsend(getfd(mqd), msg_ptr, msg_len or #msg_ptr, msg_prio or 0, abs_timeout))
end

-- like read, return string if buffer not provided. Length required. TODO should we return prio?
function S.mq_timedreceive(mqd, msg_ptr, msg_len, msg_prio, abs_timeout)
  if abs_timeout then abs_timeout = mktype(t.timespec, abs_timeout) end
  if msg_ptr then return retbool(C.mq_timedreceive(getfd(mqd), msg_ptr, msg_len or #msg_ptr, msg_prio, abs_timeout)) end
  msg_ptr = t.buffer(msg_len)
  local ret, err = C.mq_timedreceive(getfd(mqd), msg_ptr, msg_len or #msg_ptr, msg_prio, abs_timeout)
  if ret == -1 then return nil, t.error(err or errno()) end
  return ffi.string(msg_ptr,ret)
end

-- pty functions where not in common code TODO move to linux/libc?
function S.grantpt(fd) return true end -- Linux does not need to do anything here (Musl does not)
function S.unlockpt(fd) return S.ioctl(fd, "TIOCSPTLCK", 0) end
function S.ptsname(fd)
  local pts, err = S.ioctl(fd, "TIOCGPTN")
  if not pts then return nil, err end
  return "/dev/pts/" .. tostring(pts)
end
function S.tcgetattr(fd) return S.ioctl(fd, "TCGETS") end
local tcsets = {
  [c.TCSA.NOW]   = "TCSETS",
  [c.TCSA.DRAIN] = "TCSETSW",
  [c.TCSA.FLUSH] = "TCSETSF",
}
function S.tcsetattr(fd, optional_actions, tio)
  local inc = c.TCSA[optional_actions]
  return S.ioctl(fd, tcsets[inc], tio)
end
function S.tcsendbreak(fd, duration)
  return S.ioctl(fd, "TCSBRK") -- Linux ignores duration
end
function S.tcdrain(fd)
  return S.ioctl(fd, "TCSBRK", t.int(1)) -- note use of literal 1, not pointer
end
function S.tcflush(fd, queue_selector)
  return S.ioctl(fd, "TCFLSH", t.int(c.TCFLUSH[queue_selector]))
end
function S.tcflow(fd, action)
  return S.ioctl(fd, "TCXONC", pt.void(c.TCFLOW[action]))
end
function S.tcgetsid(fd) return S.ioctl(fd, "TIOCGSID") end

return S

end

