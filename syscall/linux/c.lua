-- This sets up the table of C functions

-- this should be generated ideally, as it is the ABI spec

--[[
Note a fair number are being deprecated, see include/uapi/asm-generic/unistd.h under __ARCH_WANT_SYSCALL_NO_AT, __ARCH_WANT_SYSCALL_NO_FLAGS, and __ARCH_WANT_SYSCALL_DEPRECATED
Some of these we already don't use, but some we do, eg use open not openat etc.
]]

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, select = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, select

local abi = require "syscall.abi"

local ffi = require "ffi"

local bit = require "syscall.bit"

require "syscall.linux.ffi"

local voidp = ffi.typeof("void *")

local function void(x)
  return ffi.cast(voidp, x)
end

-- basically all types passed to syscalls are int or long, so we do not need to use nicely named types, so we can avoid importing t.
local int, long = ffi.typeof("int"), ffi.typeof("long")
local uint, ulong = ffi.typeof("unsigned int"), ffi.typeof("unsigned long")

local h = require "syscall.helpers"
local err64 = h.err64
local errpointer = h.errpointer

local i6432, u6432 = bit.i6432, bit.u6432

local arg64, arg64u
if abi.le then
  arg64 = function(val)
    local v2, v1 = i6432(val)
    return v1, v2
  end
  arg64u = function(val)
    local v2, v1 = u6432(val)
    return v1, v2
  end
else
  arg64 = function(val) return i6432(val) end
  arg64u = function(val) return u6432(val) end
end
-- _llseek very odd, preadv
local function llarg64u(val) return u6432(val) end
local function llarg64(val) return i6432(val) end

local C = {}

local nr = require("syscall.linux.nr")

local zeropad = nr.zeropad
local sys = nr.SYS
local socketcalls = nr.socketcalls

local u64 = ffi.typeof("uint64_t")

-- TODO could make these return errno here, also are these best casts?
local syscall_long = ffi.C.syscall -- returns long
local function syscall(...) return tonumber(syscall_long(...)) end -- int is default as most common
local function syscall_uint(...) return uint(syscall_long(...)) end
local function syscall_void(...) return void(syscall_long(...)) end
local function syscall_off(...) return u64(syscall_long(...)) end -- off_t

local longstype = ffi.typeof("long[?]")

local function longs(...)
  local n = select('#', ...)
  local ll = ffi.new(longstype, n)
  for i = 1, n do
    ll[i - 1] = ffi.cast(long, select(i, ...))
  end
  return ll
end

-- now for the system calls

-- use 64 bit fileops on 32 bit always. As may be missing will use syscalls directly
if abi.abi32 then
  if zeropad then
    function C.truncate(path, length)
      local len1, len2 = arg64u(length)
      return syscall(sys.truncate64, path, int(0), long(len1), long(len2))
    end
    function C.ftruncate(fd, length)
      local len1, len2 = arg64u(length)
      return syscall(sys.ftruncate64, int(fd), int(0), long(len1), long(len2))
    end
    function C.readahead(fd, offset, count)
      local off1, off2 = arg64u(offset)
      return syscall(sys.readahead, int(fd), int(0), long(off1), long(off2), ulong(count))
    end
    function C.pread(fd, buf, size, offset)
      local off1, off2 = arg64(offset)
      return syscall_long(sys.pread64, int(fd), void(buf), ulong(size), int(0), long(off1), long(off2))
    end
    function C.pwrite(fd, buf, size, offset)
      local off1, off2 = arg64(offset)
      return syscall_long(sys.pwrite64, int(fd), void(buf), ulong(size), int(0), long(off1), long(off2))
    end
  else
    function C.truncate(path, length)
      local len1, len2 = arg64u(length)
      return syscall(sys.truncate64, path, long(len1), long(len2))
    end
    function C.ftruncate(fd, length)
      local len1, len2 = arg64u(length)
      return syscall(sys.ftruncate64, int(fd), long(len1), long(len2))
    end
    function C.readahead(fd, offset, count)
      local off1, off2 = arg64u(offset)
      return syscall(sys.readahead, int(fd), long(off1), long(off2), ulong(count))
    end
    function C.pread(fd, buf, size, offset)
      local off1, off2 = arg64(offset)
      return syscall_long(sys.pread64, int(fd), void(buf), ulong(size), long(off1), long(off2))
    end
    function C.pwrite(fd, buf, size, offset)
      local off1, off2 = arg64(offset)
      return syscall_long(sys.pwrite64, int(fd), void(buf), ulong(size), long(off1), long(off2))
    end
  end
  -- note statfs,fstatfs pass size of struct on 32 bit only
  function C.statfs(path, buf) return syscall(sys.statfs64, void(path), uint(ffi.sizeof(buf)), void(buf)) end
  function C.fstatfs(fd, buf) return syscall(sys.fstatfs64, int(fd), uint(ffi.sizeof(buf)), void(buf)) end
  -- Note very odd split 64 bit arguments even on 64 bit platform.
  function C.preadv(fd, iov, iovcnt, offset)
    local off1, off2 = llarg64(offset)
    return syscall_long(sys.preadv, int(fd), void(iov), int(iovcnt), long(off2), long(off1))
  end
  function C.pwritev(fd, iov, iovcnt, offset)
    local off1, off2 = llarg64(offset)
    return syscall_long(sys.pwritev, int(fd), void(iov), int(iovcnt), long(off2), long(off1))
  end
  -- lseek is a mess in 32 bit, use _llseek syscall to get clean result.
  -- TODO move this to syscall.lua
  local off1 = ffi.typeof("uint64_t[1]")
  function C.lseek(fd, offset, whence)
    local result = off1()
    local off1, off2 = llarg64(offset)
    local ret = syscall(sys._llseek, int(fd), long(off1), long(off2), void(result), uint(whence))
    if ret == -1 then return err64 end
    return result[0]
  end
  function C.sendfile(outfd, infd, offset, count)
    return syscall_long(sys.sendfile64, int(outfd), int(infd), void(offset), ulong(count))
  end
  -- on 32 bit systems mmap uses off_t so we cannot tell what ABI is. Use underlying mmap2 syscall
  function C.mmap(addr, length, prot, flags, fd, offset)
    local pgoffset = bit.rshift(offset, 12)
    return syscall_void(sys.mmap2, void(addr), ulong(length), int(prot), int(flags), int(fd), uint(pgoffset))
  end
else -- 64 bit
  function C.truncate(path, length) return syscall(sys.truncate, void(path), ulong(length)) end
  function C.ftruncate(fd, length) return syscall(sys.ftruncate, int(fd), ulong(length)) end
  function C.readahead(fd, offset, count) return syscall(sys.readahead, int(fd), ulong(offset), ulong(count)) end
  function C.pread(fd, buf, count, offset) return syscall_long(sys.pread64, int(fd), void(buf), ulong(count), ulong(offset)) end
  function C.pwrite(fd, buf, count, offset) return syscall_long(sys.pwrite64, int(fd), void(buf), ulong(count), ulong(offset)) end
  function C.statfs(path, buf) return syscall(sys.statfs, void(path), void(buf)) end
  function C.fstatfs(fd, buf) return syscall(sys.fstatfs, int(fd), void(buf)) end
  function C.preadv(fd, iov, iovcnt, offset) return syscall_long(sys.preadv, int(fd), void(iov), long(iovcnt), ulong(offset)) end
  function C.pwritev(fd, iov, iovcnt, offset) return syscall_long(sys.pwritev, int(fd), void(iov), long(iovcnt), ulong(offset)) end
  function C.lseek(fd, offset, whence) return syscall_off(sys.lseek, int(fd), ulong(offset), int(whence)) end
  function C.sendfile(outfd, infd, offset, count)
    return syscall_long(sys.sendfile, int(outfd), int(infd), void(offset), ulong(count))
  end
  function C.mmap(addr, length, prot, flags, fd, offset)
    return syscall_void(sys.mmap, void(addr), ulong(length), int(prot), int(flags), int(fd), ulong(offset))
  end
end

-- glibc caches pid, but this fails to work eg after clone().
function C.getpid() return syscall(sys.getpid) end

-- underlying syscalls
function C.exit_group(status) return syscall(sys.exit_group, int(status)) end -- void return really
function C.exit(status) return syscall(sys.exit, int(status)) end -- void return really

C._exit = C.exit_group -- standard method

-- clone interface provided is not same as system one, and is less convenient
function C.clone(flags, signal, stack, ptid, tls, ctid)
  return syscall(sys.clone, int(flags), void(stack), void(ptid), void(tls), void(ctid)) -- technically long
end

-- getdents is not provided by glibc. Musl has weak alias so not visible.
function C.getdents(fd, buf, size)
  return syscall(sys.getdents64, int(fd), buf, uint(size))
end

-- glibc has request as an unsigned long, kernel is unsigned int, other libcs are int, so use syscall directly
function C.ioctl(fd, request, arg)
  return syscall(sys.ioctl, int(fd), uint(request), void(arg))
end

-- getcwd in libc may allocate memory and has inconsistent return value, so use syscall
function C.getcwd(buf, size) return syscall(sys.getcwd, void(buf), ulong(size)) end

-- nice in libc may or may not return old value, syscall never does; however nice syscall may not exist
if sys.nice then
  function C.nice(inc) return syscall(sys.nice, int(inc)) end
end

-- avoid having to set errno by calling getpriority directly and adjusting return values
function C.getpriority(which, who) return syscall(sys.getpriority, int(which), int(who)) end

-- uClibc only provides a version of eventfd without flags, and we cannot detect this
function C.eventfd(initval, flags) return syscall(sys.eventfd2, uint(initval), int(flags)) end

-- Musl always returns ENOSYS for these
function C.sched_getscheduler(pid) return syscall(sys.sched_getscheduler, int(pid)) end
function C.sched_setscheduler(pid, policy, param)
  return syscall(sys.sched_setscheduler, int(pid), int(policy), void(param))
end

-- for stat we use the syscall as libc might have a different struct stat for compatibility
-- similarly fadvise64 is not provided, and posix_fadvise may not have 64 bit args on 32 bit
-- and fallocate seems to have issues in uClibc
local sys_fadvise64 = sys.fadvise64_64 or sys.fadvise64
if abi.abi64 then
  function C.stat(path, buf)
    return syscall(sys.stat, path, void(buf))
  end
  function C.lstat(path, buf)
    return syscall(sys.lstat, path, void(buf))
  end
  function C.fstat(fd, buf)
    return syscall(sys.fstat, int(fd), void(buf))
  end
  function C.fstatat(fd, path, buf, flags)
    return syscall(sys.fstatat, int(fd), path, void(buf), int(flags))
  end
  function C.fadvise64(fd, offset, len, advise)
    return syscall(sys_fadvise64, int(fd), ulong(offset), ulong(len), int(advise))
  end
  function C.fallocate(fd, mode, offset, len)
    return syscall(sys.fallocate, int(fd), uint(mode), ulong(offset), ulong(len))
  end
else
  function C.stat(path, buf)
    return syscall(sys.stat64, path, void(buf))
  end
  function C.lstat(path, buf)
    return syscall(sys.lstat64, path, void(buf))
  end
  function C.fstat(fd, buf)
    return syscall(sys.fstat64, int(fd), void(buf))
  end
  function C.fstatat(fd, path, buf, flags)
    return syscall(sys.fstatat64, int(fd), path, void(buf), int(flags))
  end
  if zeropad then
    function C.fadvise64(fd, offset, len, advise)
      local off1, off2 = arg64u(offset)
      local len1, len2 = arg64u(len)
      return syscall(sys_fadvise64, int(fd), 0, uint(off1), uint(off2), uint(len1), uint(len2), int(advise))
    end
  else
    function C.fadvise64(fd, offset, len, advise)
      local off1, off2 = arg64u(offset)
      local len1, len2 = arg64u(len)
      return syscall(sys_fadvise64, int(fd), uint(off1), uint(off2), uint(len1), uint(len2), int(advise))
    end
  end
  function C.fallocate(fd, mode, offset, len)
    local off1, off2 = arg64u(offset)
    local len1, len2 = arg64u(len)
    return syscall(sys.fallocate, int(fd), uint(mode), uint(off1), uint(off2), uint(len1), uint(len2))
  end
end

-- native Linux aio not generally supported by libc, only posix API
function C.io_setup(nr_events, ctx)
  return syscall(sys.io_setup, uint(nr_events), void(ctx))
end
function C.io_destroy(ctx)
  return syscall(sys.io_destroy, ulong(ctx))
end
function C.io_cancel(ctx, iocb, result)
  return syscall(sys.io_cancel, ulong(ctx), void(iocb), void(result))
end
function C.io_getevents(ctx, min, nr, events, timeout)
  return syscall(sys.io_getevents, ulong(ctx), long(min), long(nr), void(events), void(timeout))
end
function C.io_submit(ctx, iocb, nr)
  return syscall(sys.io_submit, ulong(ctx), long(nr), void(iocb))
end

-- mq functions in -rt for glibc, plus syscalls differ slightly
function C.mq_open(name, flags, mode, attr)
  return syscall(sys.mq_open, void(name), int(flags), uint(mode), void(attr))
end
function C.mq_unlink(name) return syscall(sys.mq_unlink, void(name)) end
function C.mq_getsetattr(mqd, new, old)
  return syscall(sys.mq_getsetattr, int(mqd), void(new), void(old))
end
function C.mq_timedsend(mqd, msg_ptr, msg_len, msg_prio, abs_timeout)
  return syscall(sys.mq_timedsend, int(mqd), void(msg_ptr), ulong(msg_len), uint(msg_prio), void(abs_timeout))
end
function C.mq_timedreceive(mqd, msg_ptr, msg_len, msg_prio, abs_timeout)
  return syscall(sys.mq_timedreceive, int(mqd), void(msg_ptr), ulong(msg_len), void(msg_prio), void(abs_timeout))
end

-- note kernel dev_t is 32 bits, use syscall so we can ignore glibc using 64 bit dev_t
function C.mknod(pathname, mode, dev)
  return syscall(sys.mknod, pathname, uint(mode), uint(dev))
end
function C.mknodat(fd, pathname, mode, dev)
  return syscall(sys.mknodat, int(fd), pathname, uint(mode), uint(dev))
end
-- pivot_root is not provided by glibc, is provided by Musl
function C.pivot_root(new_root, put_old)
  return syscall(sys.pivot_root, new_root, put_old)
end
-- setns not in some glibc versions
function C.setns(fd, nstype)
  return syscall(sys.setns, int(fd), int(nstype))
end
-- prlimit64 not in my ARM glibc
function C.prlimit64(pid, resource, new_limit, old_limit)
  return syscall(sys.prlimit64, int(pid), int(resource), void(new_limit), void(old_limit))
end

-- sched_setaffinity and sched_getaffinity not in Musl at the moment, use syscalls. Could test instead.
function C.sched_getaffinity(pid, len, mask)
  return syscall(sys.sched_getaffinity, int(pid), uint(len), void(mask))
end
function C.sched_setaffinity(pid, len, mask)
  return syscall(sys.sched_setaffinity, int(pid), uint(len), void(mask))
end
-- sched_setparam and sched_getparam in Musl return ENOSYS, probably as they work on threads not processes.
function C.sched_getparam(pid, param)
  return syscall(sys.sched_getparam, int(pid), void(param))
end
function C.sched_setparam(pid, param)
  return syscall(sys.sched_setparam, int(pid), void(param))
end

-- in librt for glibc but use syscalls instead of loading another library
function C.clock_nanosleep(clk_id, flags, req, rem)
  return syscall(sys.clock_nanosleep, int(clk_id), int(flags), void(req), void(rem))
end
function C.clock_getres(clk_id, ts)
  return syscall(sys.clock_getres, int(clk_id), void(ts))
end
function C.clock_settime(clk_id, ts)
  return syscall(sys.clock_settime, int(clk_id), void(ts))
end

-- glibc will not call this with a null path, which is needed to implement futimens in Linux
function C.utimensat(fd, path, times, flags)
  return syscall(sys.utimensat, int(fd), void(path), void(times), int(flags))
end

-- not in Android Bionic
function C.linkat(olddirfd, oldpath, newdirfd, newpath, flags)
  return syscall(sys.linkat, int(olddirfd), void(oldpath), int(newdirfd), void(newpath), int(flags))
end
function C.symlinkat(oldpath, newdirfd, newpath)
  return syscall(sys.symlinkat, void(oldpath), int(newdirfd), void(newpath))
end
function C.readlinkat(dirfd, pathname, buf, bufsiz)
  return syscall(sys.readlinkat, int(dirfd), void(pathname), void(buf), ulong(bufsiz))
end
function C.inotify_init1(flags)
  return syscall(sys.inotify_init1, int(flags))
end
function C.adjtimex(buf)
  return syscall(sys.adjtimex, void(buf))
end
function C.epoll_create1(flags)
  return syscall(sys.epoll_create1, int(flags))
end
function C.epoll_wait(epfd, events, maxevents, timeout)
  return syscall(sys.epoll_wait, int(epfd), void(events), int(maxevents), int(timeout))
end
function C.swapon(path, swapflags)
  return syscall(sys.swapon, void(path), int(swapflags))
end
function C.swapoff(path)
  return syscall(sys.swapoff, void(path))
end
function C.timerfd_create(clockid, flags)
  return syscall(sys.timerfd_create, int(clockid), int(flags))
end
function C.timerfd_settime(fd, flags, new_value, old_value)
  return syscall(sys.timerfd_settime, int(fd), int(flags), void(new_value), void(old_value))
end
function C.timerfd_gettime(fd, curr_value)
  return syscall(sys.timerfd_gettime, int(fd), void(curr_value))
end
function C.splice(fd_in, off_in, fd_out, off_out, len, flags)
  return syscall(sys.splice, int(fd_in), void(off_in), int(fd_out), void(off_out), ulong(len), uint(flags))
end
function C.tee(src, dest, len, flags)
  return syscall(sys.tee, int(src), int(dest), ulong(len), uint(flags))
end
function C.vmsplice(fd, iovec, cnt, flags)
  return syscall(sys.vmsplice, int(fd), void(iovec), ulong(cnt), uint(flags))
end
-- TODO note that I think these may be incorrect on 32 bit platforms, and strace is buggy
if sys.sync_file_range then
  if abi.abi64 then
    function C.sync_file_range(fd, pos, len, flags)
      return syscall(sys.sync_file_range, int(fd), long(pos), long(len), uint(flags))
    end
  else
    if zeropad then -- only on mips
      function C.sync_file_range(fd, pos, len, flags)
        local pos1, pos2 = arg64(pos)
        local len1, len2 = arg64(len)
        -- TODO these args appear to be reversed but is this mistaken/endianness/also true elsewhere? strace broken...
        return syscall(sys.sync_file_range, int(fd), 0, long(pos2), long(pos1), long(len2), long(len1), uint(flags))
      end
    else
      function C.sync_file_range(fd, pos, len, flags)
       local pos1, pos2 = arg64(pos)
       local len1, len2 = arg64(len)
        return syscall(sys.sync_file_range, int(fd), long(pos1), long(pos2), long(len1), long(len2), uint(flags))
      end
    end
  end
elseif sys.sync_file_range2 then -- only on 32 bit platforms
  function C.sync_file_range(fd, pos, len, flags)
    local pos1, pos2 = arg64(pos)
    local len1, len2 = arg64(len)
    return syscall(sys.sync_file_range2, int(fd), uint(flags), long(pos1), long(pos2), long(len1), long(len2))
  end
end

-- TODO this should be got from somewhere more generic
-- started moving into linux/syscall.lua som explicit (see signalfd) but needs some more cleanups
local sigset_size = 8
if abi.arch == "mips" then
  sigset_size = 16
end

local function sigmasksize(sigmask)
  local size = 0
  if sigmask then size = sigset_size end
  return ulong(size)
end

function C.epoll_pwait(epfd, events, maxevents, timeout, sigmask)
  return syscall(sys.epoll_pwait, int(epfd), void(events), int(maxevents), int(timeout), void(sigmask), sigmasksize(sigmask))
end

function C.ppoll(fds, nfds, timeout_ts, sigmask)
  return syscall(sys.ppoll, void(fds), ulong(nfds), void(timeout_ts), void(sigmask), sigmasksize(sigmask))
end
function C.signalfd(fd, mask, size, flags)
  return syscall(sys.signalfd4, int(fd), void(mask), ulong(size), int(flags))
end

-- adding more
function C.dup(oldfd) return syscall(sys.dup, int(oldfd)) end
function C.dup2(oldfd, newfd) return syscall(sys.dup2, int(oldfd), int(newfd)) end
function C.dup3(oldfd, newfd, flags) return syscall(sys.dup3, int(oldfd), int(newfd), int(flags)) end
function C.chmod(path, mode) return syscall(sys.chmod, void(path), uint(mode)) end
function C.fchmod(fd, mode) return syscall(sys.fchmod, int(fd), uint(mode)) end
function C.umask(mode) return syscall(sys.umask, uint(mode)) end
function C.access(path, mode) return syscall(sys.access, void(path), uint(mode)) end
function C.getppid() return syscall(sys.getppid) end
function C.getuid() return syscall(sys.getuid) end
function C.geteuid() return syscall(sys.geteuid) end
function C.getgid() return syscall(sys.getgid) end
function C.getegid() return syscall(sys.getegid) end
function C.getresuid(ruid, euid, suid) return syscall(sys.getresuid, void(ruid), void(euid), void(suid)) end
function C.getresgid(rgid, egid, sgid) return syscall(sys.getresgid, void(rgid), void(egid), void(sgid)) end
function C.setuid(id) return syscall(sys.setuid, uint(id)) end
function C.setgid(id) return syscall(sys.setgid, uint(id)) end
function C.setresuid(ruid, euid, suid) return syscall(sys.setresuid, uint(ruid), uint(euid), uint(suid)) end
function C.setresgid(rgid, egid, sgid) return syscall(sys.setresgid, uint(rgid), uint(egid), uint(sgid)) end
function C.setreuid(uid, euid) return syscall(sys.setreuid, uint(uid), uint(euid)) end
function C.setregid(gid, egid) return syscall(sys.setregid, uint(gid), uint(egid)) end
function C.flock(fd, operation) return syscall(sys.flock, int(fd), int(operation)) end
function C.getrusage(who, usage) return syscall(sys.getrusage, int(who), void(usage)) end
function C.rmdir(path) return syscall(sys.rmdir, void(path)) end
function C.chdir(path) return syscall(sys.chdir, void(path)) end
function C.fchdir(fd) return syscall(sys.fchdir, int(fd)) end
function C.chown(path, owner, group) return syscall(sys.chown, void(path), uint(owner), uint(group)) end
function C.fchown(fd, owner, group) return syscall(sys.fchown, int(fd), uint(owner), uint(group)) end
function C.lchown(path, owner, group) return syscall(sys.lchown, void(path), uint(owner), uint(group)) end
function C.open(pathname, flags, mode) return syscall(sys.open, void(pathname), int(flags), uint(mode)) end
function C.openat(dirfd, pathname, flags, mode) return syscall(sys.openat, int(dirfd), void(pathname), int(flags), uint(mode)) end
function C.creat(pathname, mode) return syscall(sys.creat, void(pathname), uint(mode)) end
function C.close(fd) return syscall(sys.close, int(fd)) end
function C.read(fd, buf, count) return syscall_long(sys.read, int(fd), void(buf), ulong(count)) end
function C.write(fd, buf, count) return syscall_long(sys.write, int(fd), void(buf), ulong(count)) end
function C.readv(fd, iov, iovcnt) return syscall_long(sys.readv, int(fd), void(iov), long(iovcnt)) end
function C.writev(fd, iov, iovcnt) return syscall_long(sys.writev, int(fd), void(iov), long(iovcnt)) end
function C.readlink(path, buf, bufsiz) return syscall_long(sys.readlink, void(path), void(buf), ulong(bufsiz)) end
function C.rename(oldpath, newpath) return syscall(sys.rename, void(oldpath), void(newpath)) end
function C.renameat(olddirfd, oldpath, newdirfd, newpath)
  return syscall(sys.renameat, int(olddirfd), void(oldpath), int(newdirfd), void(newpath))
end
function C.unlink(pathname) return syscall(sys.unlink, void(pathname)) end
function C.unlinkat(dirfd, pathname, flags) return syscall(sys.unlinkat, int(dirfd), void(pathname), int(flags)) end
function C.prctl(option, arg2, arg3, arg4, arg5)
  return syscall(sys.prctl, int(option), ulong(arg2), ulong(arg3), ulong(arg4), ulong(arg5))
end
if abi.arch == "mips" then -- mips uses old style dual register return calling convention that we caanot use
  function C.pipe(pipefd) return syscall(sys.pipe2, void(pipefd), 0) end
else
  function C.pipe(pipefd) return syscall(sys.pipe, void(pipefd)) end
end
function C.pipe2(pipefd, flags) return syscall(sys.pipe2, void(pipefd), int(flags)) end
function C.mknod(path, mode, dev) return syscall(sys.mknod, void(path), uint(mode), uint(dev)) end
function C.pause() return syscall(sys.pause) end
function C.remap_file_pages(addr, size, prot, pgoff, flags)
  return syscall(sys.remap_file_pages, void(addr), ulong(size), int(prot), long(pgoff), int(flags))
end
function C.fork() return syscall(sys.fork) end
function C.kill(pid, sig) return syscall(sys.kill, int(pid), int(sig)) end
function C.mkdir(pathname, mode) return syscall(sys.mkdir, void(pathname), uint(mode)) end
function C.fsync(fd) return syscall(sys.fsync, int(fd)) end
function C.fdatasync(fd) return syscall(sys.fdatasync, int(fd)) end
function C.sync() return syscall(sys.sync) end
function C.syncfs(fd) return syscall(sys.syncfs, int(fd)) end
function C.link(oldpath, newpath) return syscall(sys.link, void(oldpath), void(newpath)) end
function C.symlink(oldpath, newpath) return syscall(sys.symlink, void(oldpath), void(newpath)) end
function C.epoll_ctl(epfd, op, fd, event) return syscall(sys.epoll_ctl, int(epfd), int(op), int(fd), void(event)) end
function C.uname(buf) return syscall(sys.uname, void(buf)) end
function C.getsid(pid) return syscall(sys.getsid, int(pid)) end
function C.getpgid(pid) return syscall(sys.getpgid, int(pid)) end
function C.setpgid(pid, pgid) return syscall(sys.setpgid, int(pid), int(pgid)) end
function C.getpgrp() return syscall(sys.getpgrp) end
function C.setsid() return syscall(sys.setsid) end
function C.chroot(path) return syscall(sys.chroot, void(path)) end
function C.mount(source, target, filesystemtype, mountflags, data)
  return syscall(sys.mount, void(source), void(target), void(filesystemtype), ulong(mountflags), void(data))
end
function C.umount(target) return syscall(sys.umount, void(target)) end
function C.umount2(target, flags) return syscall(sys.umount2, void(target), int(flags)) end
function C.listxattr(path, list, size) return syscall_long(sys.listxattr, void(path), void(list), ulong(size)) end
function C.llistxattr(path, list, size) return syscall_long(sys.llistxattr, void(path), void(list), ulong(size)) end
function C.flistxattr(fd, list, size) return syscall_long(sys.flistxattr, int(fd), void(list), ulong(size)) end
function C.setxattr(path, name, value, size, flags)
  return syscall(sys.setxattr, void(path), void(name), void(value), ulong(size), int(flags))
end
function C.lsetxattr(path, name, value, size, flags)
  return syscall(sys.lsetxattr, void(path), void(name), void(value), ulong(size), int(flags))
end
function C.fsetxattr(fd, name, value, size, flags)
  return syscall(sys.fsetxattr, int(fd), void(name), void(value), ulong(size), int(flags))
end
function C.getxattr(path, name, value, size)
  return syscall_long(sys.getxattr, void(path), void(name), void(value), ulong(size))
end
function C.lgetxattr(path, name, value, size)
  return syscall_long(sys.lgetxattr, void(path), void(name), void(value), ulong(size))
end
function C.fgetxattr(fd, name, value, size)
  return syscall_long(sys.fgetxattr, int(fd), void(name), void(value), ulong(size))
end
function C.removexattr(path, name) return syscall(sys.removexattr, void(path), void(name)) end
function C.lremovexattr(path, name) return syscall(sys.lremovexattr, void(path), void(name)) end
function C.fremovexattr(fd, name) return syscall(sys.fremovexattr, int(fd), void(name)) end
function C.inotify_add_watch(fd, pathname, mask) return syscall(sys.inotify_add_watch, int(fd), void(pathname), uint(mask)) end
function C.inotify_rm_watch(fd, wd) return syscall(sys.inotify_rm_watch, int(fd), int(wd)) end
function C.unshare(flags) return syscall(sys.unshare, int(flags)) end
function C.reboot(magic, magic2, cmd) return syscall(sys.reboot, int(magic), int(magic2), int(cmd)) end
function C.sethostname(name, len) return syscall(sys.sethostname, void(name), ulong(len)) end
function C.setdomainname(name, len) return syscall(sys.setdomainname, void(name), ulong(len)) end
function C.getitimer(which, curr_value) return syscall(sys.getitimer, int(which), void(curr_value)) end
function C.setitimer(which, new_value, old_value) return syscall(sys.setitimer, int(which), void(new_value), void(old_value)) end
function C.sched_yield() return syscall(sys.sched_yield) end
function C.acct(filename) return syscall(sys.acct, void(filename)) end
function C.munmap(addr, length) return syscall(sys.munmap, void(addr), ulong(length)) end
function C.faccessat(dirfd, path, mode, flags) return syscall(sys.faccessat, int(dirfd), void(path), uint(mode), int(flags)) end
function C.fchmodat(dirfd, path, mode, flags) return syscall(sys.fchmodat, int(dirfd), void(path), uint(mode), int(flags)) end
function C.mkdirat(dirfd, pathname, mode) return syscall(sys.mkdirat, int(dirfd), void(pathname), uint(mode)) end
function C.fchownat(dirfd, pathname, owner, group, flags)
  return syscall(sys.fchownat, int(dirfd), void(pathname), uint(owner), uint(group), int(flags))
end
function C.setpriority(which, who, prio) return syscall(sys.setpriority, int(which), int(who), int(prio)) end
function C.sched_get_priority_min(policy) return syscall(sys.sched_get_priority_min, int(policy)) end
function C.sched_get_priority_max(policy) return syscall(sys.sched_get_priority_max, int(policy)) end
function C.sched_rr_get_interval(pid, tp) return syscall(sys.sched_rr_get_interval, int(pid), void(tp)) end
function C.poll(fds, nfds, timeout) return syscall(sys.poll, void(fds), int(nfds), int(timeout)) end
function C.msync(addr, length, flags) return syscall(sys.msync, void(addr), ulong(length), int(flags)) end
function C.madvise(addr, length, advice) return syscall(sys.madvise, void(addr), ulong(length), int(advice)) end
function C.mlock(addr, len) return syscall(sys.mlock, void(addr), ulong(len)) end
function C.munlock(addr, len) return syscall(sys.munlock, void(addr), ulong(len)) end
function C.mlockall(flags) return syscall(sys.mlockall, int(flags)) end
function C.munlockall() return syscall(sys.munlockall) end
function C.capget(hdrp, datap) return syscall(sys.capget, void(hdrp), void(datap)) end
function C.capset(hdrp, datap) return syscall(sys.capset, void(hdrp), void(datap)) end
function C.sysinfo(info) return syscall(sys.sysinfo, void(info)) end
function C.execve(filename, argv, envp) return syscall(sys.execve, void(filename), void(argv), void(envp)) end
function C.getgroups(size, list) return syscall(sys.getgroups, int(size), void(list)) end
function C.setgroups(size, list) return syscall(sys.setgroups, int(size), void(list)) end
function C.klogctl(tp, bufp, len) return syscall(sys.syslog, int(tp), void(bufp), int(len)) end
function C.sigprocmask(how, set, oldset)
  return syscall(sys.rt_sigprocmask, int(how), void(set), void(oldset), sigmasksize(set or oldset))
end
function C.sigpending(set) return syscall(sys.rt_sigpending, void(set), sigmasksize(set)) end
function C.mremap(old_address, old_size, new_size, flags, new_address)
  return syscall_void(sys.mremap, void(old_address), ulong(old_size), ulong(new_size), int(flags), void(new_address))
end
function C.nanosleep(req, rem) return syscall(sys.nanosleep, void(req), void(rem)) end
function C.wait4(pid, status, options, rusage) return syscall(sys.wait4, int(pid), void(status), int(options), void(rusage)) end
function C.waitid(idtype, id, infop, options, rusage)
  return syscall(sys.waitid, int(idtype), uint(id), void(infop), int(options), void(rusage))
end
function C.settimeofday(tv, tz)
  return syscall(sys.settimeofday, void(tv), void(tz))
end
function C.timer_create(clockid, sevp, timerid) return syscall(sys.timer_create, int(clockid), void(sevp), void(timerid)) end
function C.timer_settime(timerid, flags, new_value, old_value)
  return syscall(sys.timer_settime, int(timerid), int(flags), void(new_value), void(old_value))
end
function C.timer_gettime(timerid, curr_value) return syscall(sys.timer_gettime, int(timerid), void(curr_value)) end
function C.timer_delete(timerid) return syscall(sys.timer_delete, int(timerid)) end
function C.timer_getoverrun(timerid) return syscall(sys.timer_getoverrun, int(timerid)) end

-- only on some architectures
if sys.waitpid then
  function C.waitpid(pid, status, options) return syscall(sys.waitpid, int(pid), void(status), int(options)) end
end

-- fcntl needs a cast as last argument may be int or pointer
local fcntl = sys.fcntl64 or sys.fcntl
function C.fcntl(fd, cmd, arg) return syscall(fcntl, int(fd), int(cmd), ffi.cast(long, arg)) end

function C.pselect(nfds, readfds, writefds, exceptfds, timeout, sigmask)
  local size = 0
  if sigmask then size = sigset_size end
  local data = longs(void(sigmask), size)
  return syscall(sys.pselect6, int(nfds), void(readfds), void(writefds), void(exceptfds), void(timeout), void(data))
end

-- need _newselect syscall on some platforms
local select = sys._newselect or sys.select
function C.select(nfds, readfds, writefds, exceptfds, timeout)
  return syscall(select, int(nfds), void(readfds), void(writefds), void(exceptfds), void(timeout))
end

-- missing on some platforms eg ARM
if sys.alarm then
  function C.alarm(seconds) return syscall(sys.alarm, uint(seconds)) end
end

-- new system calls, may be missing TODO fix so is not
if sys.getrandom then
  function C.getrandom(buf, count, flags) return syscall(sys.getrandom, void(buf), uint(count), uint(flags)) end
end
if sys.memfd_create then
  function C.memfd_create(name, flags) return syscall(sys.memfd_create, void(name), uint(flags)) end
end

-- kernel sigaction structures actually rather different in Linux from libc ones
function C.sigaction(signum, act, oldact)
  return syscall(sys.rt_sigaction, int(signum), void(act), void(oldact), ulong(sigset_size)) -- size is size of sigset field
end

-- in VDSO for many archs, so use ffi for speed; TODO read VDSO to find functions there, needs elf reader
if pcall(function(k) return ffi.C[k] end, "clock_gettime") then
  C.clock_gettime = ffi.C.clock_gettime
else
  function C.clock_gettime(clk_id, ts) return syscall(sys.clock_gettime, int(clk_id), void(ts)) end
end

C.gettimeofday = ffi.C.gettimeofday
--function C.gettimeofday(tv, tz) return syscall(sys.gettimeofday, void(tv), void(tz)) end

-- glibc does not provide getcpu; it is however VDSO
function C.getcpu(cpu, node, tcache) return syscall(sys.getcpu, void(node), void(node), void(tcache)) end
-- time is VDSO but not really performance critical; does not exist for some architectures
if sys.time then
  function C.time(t) return syscall(sys.time, void(t)) end
end

-- socketcalls
if not sys.socketcall then
  function C.socket(domain, tp, protocol) return syscall(sys.socket, int(domain), int(tp), int(protocol)) end
  function C.bind(sockfd, addr, addrlen) return syscall(sys.bind, int(sockfd), void(addr), uint(addrlen)) end
  function C.connect(sockfd, addr, addrlen) return syscall(sys.connect, int(sockfd), void(addr), uint(addrlen)) end
  function C.listen(sockfd, backlog) return syscall(sys.listen, int(sockfd), int(backlog)) end
  function C.accept(sockfd, addr, addrlen)
    return syscall(sys.accept, int(sockfd), void(addr), void(addrlen))
  end
  function C.getsockname(sockfd, addr, addrlen) return syscall(sys.getsockname, int(sockfd), void(addr), void(addrlen)) end
  function C.getpeername(sockfd, addr, addrlen) return syscall(sys.getpeername, int(sockfd), void(addr), void(addrlen)) end
  function C.socketpair(domain, tp, protocol, sv) return syscall(sys.socketpair, int(domain), int(tp), int(protocol), void(sv)) end
  function C.send(sockfd, buf, len, flags) return syscall_long(sys.send, int(sockfd), void(buf), ulong(len), int(flags)) end
  function C.recv(sockfd, buf, len, flags) return syscall_long(sys.recv, int(sockfd), void(buf), ulong(len), int(flags)) end
  function C.sendto(sockfd, buf, len, flags, dest_addr, addrlen)
    return syscall_long(sys.sendto, int(sockfd), void(buf), ulong(len), int(flags), void(dest_addr), uint(addrlen))
  end
  function C.recvfrom(sockfd, buf, len, flags, src_addr, addrlen)
    return syscall_long(sys.recvfrom, int(sockfd), void(buf), ulong(len), int(flags), void(src_addr), void(addrlen))
  end
  function C.shutdown(sockfd, how) return syscall(sys.shutdown, int(sockfd), int(how)) end
  function C.setsockopt(sockfd, level, optname, optval, optlen)
    return syscall(sys.setsockopt, int(sockfd), int(level), int(optname), void(optval), uint(optlen))
  end
  function C.getsockopt(sockfd, level, optname, optval, optlen)
    return syscall(sys.getsockopt, int(sockfd), int(level), int(optname), void(optval), void(optlen))
  end
  function C.sendmsg(sockfd, msg, flags) return syscall_long(sys.sendmsg, int(sockfd), void(msg), int(flags)) end
  function C.recvmsg(sockfd, msg, flags) return syscall_long(sys.recvmsg, int(sockfd), void(msg), int(flags)) end
  function C.accept4(sockfd, addr, addrlen, flags)
    return syscall(sys.accept4, int(sockfd), void(addr), void(addrlen), int(flags))
  end
  function C.recvmmsg(sockfd, msgvec, vlen, flags, timeout)
    return syscall(sys.recvmmsg, int(sockfd), void(msgvec), uint(vlen), int(flags), void(timeout))
  end
  function C.sendmmsg(sockfd, msgvec, vlen, flags)
    return syscall(sys.sendmmsg, int(sockfd), void(msgvec), uint(vlen), int(flags))
  end
else
  function C.socket(domain, tp, protocol)
    local args = longs(domain, tp, protocol)
    return syscall(sys.socketcall, int(socketcalls.SOCKET), void(args))
  end
  function C.bind(sockfd, addr, addrlen)
    local args = longs(sockfd, void(addr), addrlen)
    return syscall(sys.socketcall, int(socketcalls.BIND), void(args))
  end
  function C.connect(sockfd, addr, addrlen)
    local args = longs(sockfd, void(addr), addrlen)
    return syscall(sys.socketcall, int(socketcalls.CONNECT), void(args))
  end
  function C.listen(sockfd, backlog)
    local args = longs(sockfd, backlog)
    return syscall(sys.socketcall, int(socketcalls.LISTEN), void(args))
  end
  function C.accept(sockfd, addr, addrlen)
    local args = longs(sockfd, void(addr), void(addrlen))
    return syscall(sys.socketcall, int(socketcalls.ACCEPT), void(args))
  end
  function C.getsockname(sockfd, addr, addrlen)
    local args = longs(sockfd, void(addr), void(addrlen))
    return syscall(sys.socketcall, int(socketcalls.GETSOCKNAME), void(args))
  end
  function C.getpeername(sockfd, addr, addrlen)
    local args = longs(sockfd, void(addr), void(addrlen))
    return syscall(sys.socketcall, int(socketcalls.GETPEERNAME), void(args))
  end
  function C.socketpair(domain, tp, protocol, sv)
    local args = longs(domain, tp, protocol, void(sv))
    return syscall(sys.socketcall, int(socketcalls.SOCKETPAIR), void(args))
  end
  function C.send(sockfd, buf, len, flags)
    local args = longs(sockfd, void(buf), len, flags)
    return syscall_long(sys.socketcall, int(socketcalls.SEND), void(args))
  end
  function C.recv(sockfd, buf, len, flags)
    local args = longs(sockfd, void(buf), len, flags)
    return syscall_long(sys.socketcall, int(socketcalls.RECV), void(args))
  end
  function C.sendto(sockfd, buf, len, flags, dest_addr, addrlen)
    local args = longs(sockfd, void(buf), len, flags, void(dest_addr), addrlen)
    return syscall_long(sys.socketcall, int(socketcalls.SENDTO), void(args))
  end
  function C.recvfrom(sockfd, buf, len, flags, src_addr, addrlen)
    local args = longs(sockfd, void(buf), len, flags, void(src_addr), void(addrlen))
    return syscall_long(sys.socketcall, int(socketcalls.RECVFROM), void(args))
  end
  function C.shutdown(sockfd, how)
    local args = longs(sockfd, how)
    return syscall(sys.socketcall, int(socketcalls.SHUTDOWN), void(args))
  end
  function C.setsockopt(sockfd, level, optname, optval, optlen)
    local args = longs(sockfd, level, optname, void(optval), optlen)
    return syscall(sys.socketcall, int(socketcalls.SETSOCKOPT), void(args))
  end
  function C.getsockopt(sockfd, level, optname, optval, optlen)
    local args = longs(sockfd, level, optname, void(optval), void(optlen))
    return syscall(sys.socketcall, int(socketcalls.GETSOCKOPT), void(args))
  end
  function C.sendmsg(sockfd, msg, flags)
    local args = longs(sockfd, void(msg), flags)
    return syscall_long(sys.socketcall, int(socketcalls.SENDMSG), void(args))
  end
  function C.recvmsg(sockfd, msg, flags)
    local args = longs(sockfd, void(msg), flags)
    return syscall_long(sys.socketcall, int(socketcalls.RECVMSG), void(args))
  end
  function C.accept4(sockfd, addr, addrlen, flags)
    local args = longs(sockfd, void(addr), void(addrlen), flags)
    return syscall(sys.socketcall, int(socketcalls.ACCEPT4), void(args))
  end
  function C.recvmmsg(sockfd, msgvec, vlen, flags, timeout)
    local args = longs(sockfd, void(msgvec), vlen, flags, void(timeout))
    return syscall(sys.socketcall, int(socketcalls.RECVMMSG), void(args))
  end
  function C.sendmmsg(sockfd, msgvec, vlen, flags)
    local args = longs(sockfd, void(msgvec), vlen, flags)
    return syscall(sys.socketcall, int(socketcalls.SENDMMSG), void(args))
  end
end

return C


