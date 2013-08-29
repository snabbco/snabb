-- This sets up the table of C functions, overriding libc where necessary with direct syscalls

-- ffi.C (ie libc) is the default fallback via the metatable, but we override stuff that might be missing, has different semantics
-- or which we cannot detect sanely which ABI is being presented.

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit

local function init(abi, c, types)

local ffi = require "ffi"

local t, pt, s = types.t, types.pt, types.s

-- TODO clean up when 64 bit bitops available, remove from types
local function u6432(x) return t.u6432(x):to32() end
local function i6432(x) return t.i6432(x):to32() end

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

local function inlibc_fn(k) return ffi.C[k] end

local C = setmetatable({}, {
  __index = function(C, k)
    if pcall(inlibc_fn, k) then
      C[k] = ffi.C[k] -- add to table, so no need for this slow path again
      return C[k]
    else
      return nil
    end
  end
})

-- use 64 bit fileops on 32 bit always. As may be missing will use syscalls directly
if abi.abi32 then
  if c.syscall.zeropad then
    function C.truncate(path, length)
      local len1, len2 = arg64u(length)
      return C.syscall(c.SYS.truncate64, path, t.int(0), t.long(len1), t.long(len2))
    end
    function C.ftruncate(fd, length)
      local len1, len2 = arg64u(length)
      return C.syscall(c.SYS.ftruncate64, t.int(fd), t.int(0), t.long(len1), t.long(len2))
    end
    function C.pread(fd, buf, size, offset)
      local off1, off2 = arg64(offset)
      return C.syscall(c.SYS.pread64, t.int(fd), pt.void(buf), t.size(size), t.int(0), t.long(off1), t.long(off2))
    end
    function C.pwrite(fd, buf, size, offset)
      local off1, off2 = arg64(offset)
      return C.syscall(c.SYS.pwrite64, t.int(fd), pt.void(buf), t.size(size), t.int(0), t.long(off1), t.long(off2))
    end
  else
    function C.truncate(path, length)
      local len1, len2 = arg64u(length)
      return C.syscall(c.SYS.truncate64, path, t.long(len1), t.long(len2))
    end
    function C.ftruncate(fd, length)
      local len1, len2 = arg64u(length)
      return C.syscall(c.SYS.ftruncate64, t.int(fd), t.long(len1), t.long(len2))
    end
    function C.pread(fd, buf, size, offset)
      local off1, off2 = arg64(offset)
      return C.syscall(c.SYS.pread64, t.int(fd), pt.void(buf), t.size(size), t.long(off1), t.long(off2))
    end
    function C.pwrite(fd, buf, size, offset)
      local off1, off2 = arg64(offset)
      return C.syscall(c.SYS.pwrite64, t.int(fd), pt.void(buf), t.size(size), t.long(off1), t.long(off2))
    end
  end
  -- note statfs,fstatfs pass size of struct, we hide that here as on 64 bit we use libc call at present
  function C.statfs(path, buf) return C.syscall(c.SYS.statfs64, path, t.uint(s.statfs), pt.void(buf)) end
  function C.fstatfs(fd, buf) return C.syscall(c.SYS.fstatfs64, t.int(fd), t.uint(s.statfs), pt.void(buf)) end
  -- Note very odd split 64 bit arguments even on 64 bit platform.
  function C.preadv(fd, iov, iovcnt, offset)
    local off1, off2 = llarg64(offset)
    return C.syscall(c.SYS.preadv, t.int(fd), pt.void(iov), t.int(iovcnt), t.long(off2), t.long(off1))
  end
  function C.pwritev(fd, iov, iovcnt, offset)
    local off1, off2 = llarg64(offset)
    return C.syscall(c.SYS.pwritev, t.int(fd), pt.void(iov), t.int(iovcnt), t.long(off2), t.long(off1))
  end
  -- lseek is a mess in 32 bit, use _llseek syscall to get clean result.
  function C.lseek(fd, offset, whence)
    local result = t.off1()
    local off1, off2 = llarg64u(offset)
    local ret = C.syscall(c.SYS._llseek, t.int(fd), t.ulong(off1), t.ulong(off2), pt.void(result), t.uint(whence))
    if ret == -1 then return -1 end
    return result[0]
  end
  function C.sendfile(outfd, infd, offset, count)
    return C.syscall(c.SYS.sendfile64, t.int(outfd), t.int(infd), pt.void(offset), t.size(count))
  end
  -- on 32 bit systems mmap uses off_t so we cannot tell what ABI is. Use underlying mmap2 syscall
  function C.mmap(addr, length, prot, flags, fd, offset)
    local pgoffset = math.floor(offset / 4096)
    return pt.void(C.syscall(c.SYS.mmap2, pt.void(addr), t.size(length), t.int(prot), t.int(flags), t.int(fd), t.uint32(pgoffset)))
  end
end

-- glibc caches pid, but this fails to work eg after clone().
function C.getpid()
  return C.syscall(c.SYS.getpid)
end

-- exit_group is the normal syscall but not available
function C.exit_group(status)
  return C.syscall(c.SYS.exit_group, t.int(status or 0))
end

-- clone interface provided is not same as system one, and is less convenient
function C.clone(flags, signal, stack, ptid, tls, ctid)
  return C.syscall(c.SYS.clone, t.int(flags), pt.void(stack), pt.void(ptid), pt.void(tls), pt.void(ctid))
end

-- getdents is not provided by glibc. Musl has weak alias so not visible.
function C.getdents(fd, buf, size)
  return C.syscall(c.SYS.getdents64, t.int(fd), buf, t.uint(size))
end

-- glibc has request as an unsigned long, kernel is unsigned int, other libcs are int, so use syscall directly
function C.ioctl(fd, request, arg)
  return C.syscall(c.SYS.ioctl, t.int(fd), t.uint(request), pt.void(arg))
end

-- getcwd in libc may allocate memory and has inconsistent return value, so use syscall
function C.getcwd(buf, size)
  return C.syscall(c.SYS.getcwd, pt.void(buf), t.ulong(size))
end

-- nice in libc may or may not return old value, syscall never does; however nice syscall may not exist
if c.SYS.nice then
  function C.nice(inc)
    return C.syscall(c.SYS.nice, t.int(inc))
  end
end

-- avoid having to set errno by calling getpriority directly and adjusting return values
function C.getpriority(which, who)
  return C.syscall(c.SYS.getpriority, t.int(which), t.int(who))
end

-- uClibc only provides a version of eventfd without flags, and we cannot detect this
function C.eventfd(initval, flags)
  return C.syscall(c.SYS.eventfd2, t.uint(initval), t.int(flags))
end

-- glibc does not provide getcpu
function C.getcpu(cpu, node, tcache)
  return C.syscall(c.SYS.getcpu, pt.uint(node), pt.uint(node), pt.void(tcache))
end

-- Musl always returns ENOSYS for these
function C.sched_getscheduler(pid)
  return C.syscall(c.SYS.sched_getscheduler, t.pid(pid))
end
function C.sched_setscheduler(pid, policy, param)
  return C.syscall(c.SYS.sched_setscheduler, t.pid(pid), t.int(policy), pt.sched_param(param))
end

-- for stat we use the syscall as libc might have a different struct stat for compatibility
-- similarly fadvise64 is not provided, and posix_fadvise may not have 64 bit args on 32 bit
-- and fallocate seems to have issues in uClibc
local sys_fadvise64 = c.SYS.fadvise64_64 or c.SYS.fadvise64
if abi.abi64 then
  function C.stat(path, buf)
    return C.syscall(c.SYS.stat, path, pt.void(buf))
  end
  function C.lstat(path, buf)
    return C.syscall(c.SYS.lstat, path, pt.void(buf))
  end
  function C.fstat(fd, buf)
    return C.syscall(c.SYS.fstat, t.int(fd), pt.void(buf))
  end
  function C.fstatat(fd, path, buf, flags)
    return C.syscall(c.SYS.fstatat, t.int(fd), path, pt.void(buf), t.int(flags))
  end
  function C.fadvise64(fd, offset, len, advise)
    return C.syscall(sys_fadvise64, t.int(fd), t.off(offset), t.off(len), t.int(advise))
  end
  function C.fallocate(fd, mode, offset, len)
    return C.syscall(c.SYS.fallocate, t.int(fd), t.uint(mode), t.off(offset), t.off(len))
  end
else
  function C.stat(path, buf)
    return C.syscall(c.SYS.stat64, path, pt.void(buf))
  end
  function C.lstat(path, buf)
    return C.syscall(c.SYS.lstat64, path, pt.void(buf))
  end
  function C.fstat(fd, buf)
    return C.syscall(c.SYS.fstat64, t.int(fd), pt.void(buf))
  end
  function C.fstatat(fd, path, buf, flags)
    return C.syscall(c.SYS.fstatat64, t.int(fd), path, pt.void(buf), t.int(flags))
  end
  if c.syscall.zeropad then
    function C.fadvise64(fd, offset, len, advise)
      local off1, off2 = arg64u(offset)
      local len1, len2 = arg64u(len)
      return C.syscall(sys_fadvise64, t.int(fd), 0, t.uint32(off1), t.uint32(off2), t.uint32(len1), t.uint32(len2), t.int(advise))
    end
  else
    function C.fadvise64(fd, offset, len, advise)
      local off1, off2 = arg64u(offset)
      local len1, len2 = arg64u(len)
      return C.syscall(sys_fadvise64, t.int(fd), t.uint32(off1), t.uint32(off2), t.uint32(len1), t.uint32(len2), t.int(advise))
    end
  end
  function C.fallocate(fd, mode, offset, len)
    local off1, off2 = arg64u(offset)
    local len1, len2 = arg64u(len)
    return C.syscall(c.SYS.fallocate, t.int(fd), t.uint(mode), t.uint32(off1), t.uint32(off2), t.uint32(len1), t.uint32(len2))
  end
end

-- native Linux aio not generally supported by libc, only posix API
function C.io_setup(nr_events, ctx)
  return C.syscall(c.SYS.io_setup, t.uint(nr_events), pt.void(ctx))
end
function C.io_destroy(ctx)
  return C.syscall(c.SYS.io_destroy, t.aio_context(ctx))
end
function C.io_cancel(ctx, iocb, result)
  return C.syscall(c.SYS.io_cancel, t.aio_context(ctx), pt.void(iocb), pt.void(result))
end
function C.io_getevents(ctx, min, nr, events, timeout)
  return C.syscall(c.SYS.io_getevents, t.aio_context(ctx), t.long(min), t.long(nr), pt.void(events), pt.void(timeout))
end
function C.io_submit(ctx, iocb, nr)
  return C.syscall(c.SYS.io_submit, t.aio_context(ctx), t.long(nr), pt.void(iocb))
end

-- mq functions in -rt for glibc, plus syscalls differ slightly
function C.mq_open(name, flags, mode, attr)
  return C.syscall(c.SYS.mq_open, pt.void(name), t.int(flags), t.mode(mode), pt.void(attr))
end

function C.mq_unlink(name)
  return C.syscall(c.SYS.mq_unlink, pt.void(name))
end

function C.mq_getsetattr(mqd, new, old)
  return C.syscall(c.SYS.mq_getsetattr, t.int(mqd), pt.void(new), pt.void(old))
end

function C.mq_timedsend(mqd, msg_ptr, msg_len, msg_prio, abs_timeout)
  return C.syscall(c.SYS.mq_timedsend, t.int(mqd), pt.void(msg_ptr), t.size(msg_len), t.uint(msg_prio), pt.void(abs_timeout))
end

function C.mq_timedreceive(mqd, msg_ptr, msg_len, msg_prio, abs_timeout)
  return C.syscall(c.SYS.mq_timedreceive, t.int(mqd), pt.void(msg_ptr), t.size(msg_len), pt.void(msg_prio), pt.void(abs_timeout))
end

-- note kernel dev_t is 32 bits, use syscall so we can ignore glibc using 64 bit dev_t
function C.mknod(pathname, mode, dev)
  return C.syscall(c.SYS.mknod, pathname, t.mode(mode), t.uint(dev))
end
function C.mknodat(fd, pathname, mode, dev)
  return C.syscall(c.SYS.mknodat, t.int(fd), pathname, t.mode(mode), t.uint(dev))
end
-- pivot_root is not provided by glibc, is provided by Musl
function C.pivot_root(new_root, put_old)
  return C.syscall(c.SYS.pivot_root, new_root, put_old)
end
-- setns not in some glibc versions
function C.setns(fd, nstype)
  return C.syscall(c.SYS.setns, t.int(fd), t.int(nstype))
end
-- prlimit64 not in my ARM glibc
function C.prlimit64(pid, resource, new_limit, old_limit)
  return C.syscall(c.SYS.prlimit64, t.pid(pid), t.int(resource), pt.void(new_limit), pt.void(old_limit))
end

-- sched_setaffinity and sched_getaffinity not in Musl at the moment, use syscalls. Could test instead.
function C.sched_getaffinity(pid, len, mask)
  return C.syscall(c.SYS.sched_getaffinity, t.pid(pid), t.uint(len), pt.void(mask))
end
function C.sched_setaffinity(pid, len, mask)
  return C.syscall(c.SYS.sched_setaffinity, t.pid(pid), t.uint(len), pt.void(mask))
end
-- sched_setparam and sched_getparam in Musl return ENOSYS, probably as they work on threads not processes.
function C.sched_getparam(pid, param)
  return C.syscall(c.SYS.sched_getparam, t.pid(pid), pt.void(param))
end
function C.sched_setparam(pid, param)
  return C.syscall(c.SYS.sched_setparam, t.pid(pid), pt.void(param))
end

-- in librt for glibc but use syscalls instead of loading another library
function C.clock_nanosleep(clk_id, flags, req, rem)
  return C.syscall(c.SYS.clock_nanosleep, t.clockid(clk_id), t.int(flags), pt.void(req), pt.void(rem))
end
function C.clock_getres(clk_id, ts)
  return C.syscall(c.SYS.clock_getres, t.clockid(clk_id), pt.void(ts))
end
function C.clock_gettime(clk_id, ts)
  return C.syscall(c.SYS.clock_gettime, t.clockid(clk_id), pt.void(ts))
end
function C.clock_settime(clk_id, ts)
  return C.syscall(c.SYS.clock_settime, t.clockid(clk_id), pt.void(ts))
end

-- glibc will not call this with a null path, which is needed to implement futimens in Linux
function C.utimensat(fd, path, times, flags)
  return C.syscall(c.SYS.utimensat, t.int(fd), pt.void(path), pt.void(times), t.int(flags))
end

-- not in Android Bionic
function C.linkat(olddirfd, oldpath, newdirfd, newpath, flags)
  return C.syscall(c.SYS.linkat, t.int(olddirfd), pt.void(oldpath), t.int(newdirfd), pt.void(newpath), t.int(flags))
end
function C.symlinkat(oldpath, newdirfd, newpath)
  return C.syscall(c.SYS.symlinkat, pt.void(oldpath), t.int(newdirfd), pt.void(newpath))
end
function C.readlinkat(dirfd, pathname, buf, bufsiz)
  return C.syscall(c.SYS.readlinkat, t.int(dirfd), pt.void(pathname), pt.void(buf), t.size(bufsiz))
end
function C.inotify_init1(flags)
  return C.syscall(c.SYS.inotify_init1, t.int(flags))
end
function C.adjtimex(buf)
  return C.syscall(c.SYS.adjtimex, pt.void(buf))
end
function C.epoll_create1(flags)
  return C.syscall(c.SYS.epoll_create1, t.int(flags))
end
function C.epoll_wait(epfd, events, maxevents, timeout)
  return C.syscall(c.SYS.epoll_wait, t.int(epfd), pt.void(events), t.int(maxevents), t.int(timeout))
end
function C.epoll_pwait(epfd, events, maxevents, timeout, sigmask)
  local size = 0
  if sigmask then size = 8 end -- should be s.sigset once switched to kernel sigset not glibc size
  return C.syscall(c.SYS.epoll_pwait, t.int(epfd), pt.void(events), t.int(maxevents), t.int(timeout), pt.void(sigmask), t.int(size))
end
function C.ppoll(fds, nfds, timeout_ts, sigmask)
  local size = 0
  if sigmask then size = 8 end -- should be s.sigset once switched to kernel sigset not glibc size
  return C.syscall(c.SYS.ppoll, pt.void(fds), t.nfds(nfds), pt.void(timeout_ts), pt.void(sigmask), t.int(size))
end
function C.swapon(path, swapflags)
  return C.syscall(c.SYS.swapon, pt.void(path), t.int(swapflags))
end
function C.swapoff(path)
  return C.syscall(c.SYS.swapoff, pt.void(path))
end
function C.timerfd_create(clockid, flags)
  return C.syscall(c.SYS.timerfd_create, t.int(clockid), t.int(flags))
end
function C.timerfd_settime(fd, flags, new_value, old_value)
  return C.syscall(c.SYS.timerfd_settime, t.int(fd), t.int(flags), pt.void(new_value), pt.void(old_value))
end
function C.timerfd_gettime(fd, curr_value)
  return C.syscall(c.SYS.timerfd_gettime, t.int(fd), pt.void(curr_value))
end
-- TODO add sync_file_range, splice here, need 64 bit fixups

if c.SYS.accept4 then -- on x86 this is a socketcall, which we have not implemented yet, other archs is a syscall
  function C.accept4(sockfd, addr, addrlen, flags)
    return C.syscall(c.SYS.accept4, t.int(sockfd), pt.void(addr), pt.void(addrlen), t.int(flags))
  end
end

return C

end

return {init = init}


