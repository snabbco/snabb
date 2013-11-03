-- This sets up the table of C functions, overriding libc where necessary with direct syscalls

-- ffi.C (ie libc) is the default fallback via the metatable, but we override stuff that might be missing, has different semantics
-- or which we cannot detect sanely which ABI is being presented.

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(abi, c, types)

local ffi = require "ffi"

local bit = require "syscall.bit"

local t, pt = types.t, types.pt

local void = pt.void

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

local zeropad = c.syscall.zeropad
local syscall = ffi.C.syscall

-- use 64 bit fileops on 32 bit always. As may be missing will use syscalls directly
if abi.abi32 then
  if zeropad then
    function C.truncate(path, length)
      local len1, len2 = arg64u(length)
      return syscall(c.SYS.truncate64, path, t.int(0), t.long(len1), t.long(len2))
    end
    function C.ftruncate(fd, length)
      local len1, len2 = arg64u(length)
      return syscall(c.SYS.ftruncate64, t.int(fd), t.int(0), t.long(len1), t.long(len2))
    end
    function C.pread(fd, buf, size, offset)
      local off1, off2 = arg64(offset)
      return syscall(c.SYS.pread64, t.int(fd), void(buf), t.size(size), t.int(0), t.long(off1), t.long(off2))
    end
    function C.pwrite(fd, buf, size, offset)
      local off1, off2 = arg64(offset)
      return syscall(c.SYS.pwrite64, t.int(fd), void(buf), t.size(size), t.int(0), t.long(off1), t.long(off2))
    end
  else
    function C.truncate(path, length)
      local len1, len2 = arg64u(length)
      return syscall(c.SYS.truncate64, path, t.long(len1), t.long(len2))
    end
    function C.ftruncate(fd, length)
      local len1, len2 = arg64u(length)
      return syscall(c.SYS.ftruncate64, t.int(fd), t.long(len1), t.long(len2))
    end
    function C.pread(fd, buf, size, offset)
      local off1, off2 = arg64(offset)
      return syscall(c.SYS.pread64, t.int(fd), void(buf), t.size(size), t.long(off1), t.long(off2))
    end
    function C.pwrite(fd, buf, size, offset)
      local off1, off2 = arg64(offset)
      return syscall(c.SYS.pwrite64, t.int(fd), void(buf), t.size(size), t.long(off1), t.long(off2))
    end
  end
  -- note statfs,fstatfs pass size of struct
  function C.statfs(path, buf) return syscall(c.SYS.statfs64, path, t.uint(ffi.sizeof(buf)), void(buf)) end
  function C.fstatfs(fd, buf) return syscall(c.SYS.fstatfs64, t.int(fd), t.uint(ffi.sizeof(buf)), void(buf)) end
  -- Note very odd split 64 bit arguments even on 64 bit platform.
  function C.preadv(fd, iov, iovcnt, offset)
    local off1, off2 = llarg64(offset)
    return syscall(c.SYS.preadv, t.int(fd), void(iov), t.int(iovcnt), t.long(off2), t.long(off1))
  end
  function C.pwritev(fd, iov, iovcnt, offset)
    local off1, off2 = llarg64(offset)
    return syscall(c.SYS.pwritev, t.int(fd), void(iov), t.int(iovcnt), t.long(off2), t.long(off1))
  end
  -- lseek is a mess in 32 bit, use _llseek syscall to get clean result.
  function C.lseek(fd, offset, whence)
    local result = t.off1()
    local off1, off2 = llarg64u(offset)
    local ret = syscall(c.SYS._llseek, t.int(fd), t.ulong(off1), t.ulong(off2), void(result), t.uint(whence))
    if ret == -1 then return err64 end
    return result[0]
  end
  function C.sendfile(outfd, infd, offset, count)
    return syscall(c.SYS.sendfile64, t.int(outfd), t.int(infd), void(offset), t.size(count))
  end
  -- on 32 bit systems mmap uses off_t so we cannot tell what ABI is. Use underlying mmap2 syscall
  function C.mmap(addr, length, prot, flags, fd, offset)
    local pgoffset = bit.rshift(offset, 12)
    return void(syscall(c.SYS.mmap2, void(addr), t.size(length), t.int(prot), t.int(flags), t.int(fd), t.uint32(pgoffset)))
  end
end

-- glibc caches pid, but this fails to work eg after clone().
function C.getpid() return syscall(c.SYS.getpid) end

-- exit_group is the normal syscall but not available
function C.exit_group(status) return syscall(c.SYS.exit_group, t.int(status)) end

-- clone interface provided is not same as system one, and is less convenient
function C.clone(flags, signal, stack, ptid, tls, ctid)
  return syscall(c.SYS.clone, t.int(flags), void(stack), void(ptid), void(tls), void(ctid))
end

-- getdents is not provided by glibc. Musl has weak alias so not visible.
function C.getdents(fd, buf, size)
  return syscall(c.SYS.getdents64, t.int(fd), buf, t.uint(size))
end

-- glibc has request as an unsigned long, kernel is unsigned int, other libcs are int, so use syscall directly
function C.ioctl(fd, request, arg)
  return syscall(c.SYS.ioctl, t.int(fd), t.uint(request), void(arg))
end

-- getcwd in libc may allocate memory and has inconsistent return value, so use syscall
function C.getcwd(buf, size) return syscall(c.SYS.getcwd, void(buf), t.ulong(size)) end

-- nice in libc may or may not return old value, syscall never does; however nice syscall may not exist
if c.SYS.nice then
  function C.nice(inc) return syscall(c.SYS.nice, t.int(inc)) end
end

-- avoid having to set errno by calling getpriority directly and adjusting return values
function C.getpriority(which, who)
  return syscall(c.SYS.getpriority, t.int(which), t.int(who))
end

-- uClibc only provides a version of eventfd without flags, and we cannot detect this
function C.eventfd(initval, flags)
  return syscall(c.SYS.eventfd2, t.uint(initval), t.int(flags))
end

-- glibc does not provide getcpu
function C.getcpu(cpu, node, tcache)
  return syscall(c.SYS.getcpu, pt.uint(node), pt.uint(node), void(tcache))
end

-- Musl always returns ENOSYS for these
function C.sched_getscheduler(pid)
  return syscall(c.SYS.sched_getscheduler, t.pid(pid))
end
function C.sched_setscheduler(pid, policy, param)
  return syscall(c.SYS.sched_setscheduler, t.pid(pid), t.int(policy), pt.sched_param(param))
end

-- for stat we use the syscall as libc might have a different struct stat for compatibility
-- similarly fadvise64 is not provided, and posix_fadvise may not have 64 bit args on 32 bit
-- and fallocate seems to have issues in uClibc
local sys_fadvise64 = c.SYS.fadvise64_64 or c.SYS.fadvise64
if abi.abi64 then
  function C.stat(path, buf)
    return syscall(c.SYS.stat, path, void(buf))
  end
  function C.lstat(path, buf)
    return syscall(c.SYS.lstat, path, void(buf))
  end
  function C.fstat(fd, buf)
    return syscall(c.SYS.fstat, t.int(fd), void(buf))
  end
  function C.fstatat(fd, path, buf, flags)
    return syscall(c.SYS.fstatat, t.int(fd), path, void(buf), t.int(flags))
  end
  function C.fadvise64(fd, offset, len, advise)
    return syscall(sys_fadvise64, t.int(fd), t.off(offset), t.off(len), t.int(advise))
  end
  function C.fallocate(fd, mode, offset, len)
    return syscall(c.SYS.fallocate, t.int(fd), t.uint(mode), t.off(offset), t.off(len))
  end
else
  function C.stat(path, buf)
    return syscall(c.SYS.stat64, path, void(buf))
  end
  function C.lstat(path, buf)
    return syscall(c.SYS.lstat64, path, void(buf))
  end
  function C.fstat(fd, buf)
    return syscall(c.SYS.fstat64, t.int(fd), void(buf))
  end
  function C.fstatat(fd, path, buf, flags)
    return syscall(c.SYS.fstatat64, t.int(fd), path, void(buf), t.int(flags))
  end
  if zeropad then
    function C.fadvise64(fd, offset, len, advise)
      local off1, off2 = arg64u(offset)
      local len1, len2 = arg64u(len)
      return syscall(sys_fadvise64, t.int(fd), 0, t.uint32(off1), t.uint32(off2), t.uint32(len1), t.uint32(len2), t.int(advise))
    end
  else
    function C.fadvise64(fd, offset, len, advise)
      local off1, off2 = arg64u(offset)
      local len1, len2 = arg64u(len)
      return syscall(sys_fadvise64, t.int(fd), t.uint32(off1), t.uint32(off2), t.uint32(len1), t.uint32(len2), t.int(advise))
    end
  end
  function C.fallocate(fd, mode, offset, len)
    local off1, off2 = arg64u(offset)
    local len1, len2 = arg64u(len)
    return syscall(c.SYS.fallocate, t.int(fd), t.uint(mode), t.uint32(off1), t.uint32(off2), t.uint32(len1), t.uint32(len2))
  end
end

-- native Linux aio not generally supported by libc, only posix API
function C.io_setup(nr_events, ctx)
  return syscall(c.SYS.io_setup, t.uint(nr_events), void(ctx))
end
function C.io_destroy(ctx)
  return syscall(c.SYS.io_destroy, t.aio_context(ctx))
end
function C.io_cancel(ctx, iocb, result)
  return syscall(c.SYS.io_cancel, t.aio_context(ctx), void(iocb), void(result))
end
function C.io_getevents(ctx, min, nr, events, timeout)
  return syscall(c.SYS.io_getevents, t.aio_context(ctx), t.long(min), t.long(nr), void(events), void(timeout))
end
function C.io_submit(ctx, iocb, nr)
  return syscall(c.SYS.io_submit, t.aio_context(ctx), t.long(nr), void(iocb))
end

-- mq functions in -rt for glibc, plus syscalls differ slightly
function C.mq_open(name, flags, mode, attr)
  return syscall(c.SYS.mq_open, void(name), t.int(flags), t.mode(mode), void(attr))
end
function C.mq_unlink(name) return syscall(c.SYS.mq_unlink, void(name)) end
function C.mq_getsetattr(mqd, new, old)
  return syscall(c.SYS.mq_getsetattr, t.int(mqd), void(new), void(old))
end
function C.mq_timedsend(mqd, msg_ptr, msg_len, msg_prio, abs_timeout)
  return syscall(c.SYS.mq_timedsend, t.int(mqd), void(msg_ptr), t.size(msg_len), t.uint(msg_prio), void(abs_timeout))
end
function C.mq_timedreceive(mqd, msg_ptr, msg_len, msg_prio, abs_timeout)
  return syscall(c.SYS.mq_timedreceive, t.int(mqd), void(msg_ptr), t.size(msg_len), void(msg_prio), void(abs_timeout))
end

-- note kernel dev_t is 32 bits, use syscall so we can ignore glibc using 64 bit dev_t
function C.mknod(pathname, mode, dev)
  return syscall(c.SYS.mknod, pathname, t.mode(mode), t.uint(dev))
end
function C.mknodat(fd, pathname, mode, dev)
  return syscall(c.SYS.mknodat, t.int(fd), pathname, t.mode(mode), t.uint(dev))
end
-- pivot_root is not provided by glibc, is provided by Musl
function C.pivot_root(new_root, put_old)
  return syscall(c.SYS.pivot_root, new_root, put_old)
end
-- setns not in some glibc versions
function C.setns(fd, nstype)
  return syscall(c.SYS.setns, t.int(fd), t.int(nstype))
end
-- prlimit64 not in my ARM glibc
function C.prlimit64(pid, resource, new_limit, old_limit)
  return syscall(c.SYS.prlimit64, t.pid(pid), t.int(resource), void(new_limit), void(old_limit))
end

-- sched_setaffinity and sched_getaffinity not in Musl at the moment, use syscalls. Could test instead.
function C.sched_getaffinity(pid, len, mask)
  return syscall(c.SYS.sched_getaffinity, t.pid(pid), t.uint(len), void(mask))
end
function C.sched_setaffinity(pid, len, mask)
  return syscall(c.SYS.sched_setaffinity, t.pid(pid), t.uint(len), void(mask))
end
-- sched_setparam and sched_getparam in Musl return ENOSYS, probably as they work on threads not processes.
function C.sched_getparam(pid, param)
  return syscall(c.SYS.sched_getparam, t.pid(pid), void(param))
end
function C.sched_setparam(pid, param)
  return syscall(c.SYS.sched_setparam, t.pid(pid), void(param))
end

-- in librt for glibc but use syscalls instead of loading another library
function C.clock_nanosleep(clk_id, flags, req, rem)
  return syscall(c.SYS.clock_nanosleep, t.clockid(clk_id), t.int(flags), void(req), void(rem))
end
function C.clock_getres(clk_id, ts)
  return syscall(c.SYS.clock_getres, t.clockid(clk_id), void(ts))
end
function C.clock_gettime(clk_id, ts)
  return syscall(c.SYS.clock_gettime, t.clockid(clk_id), void(ts))
end
function C.clock_settime(clk_id, ts)
  return syscall(c.SYS.clock_settime, t.clockid(clk_id), void(ts))
end

-- glibc will not call this with a null path, which is needed to implement futimens in Linux
function C.utimensat(fd, path, times, flags)
  return syscall(c.SYS.utimensat, t.int(fd), void(path), void(times), t.int(flags))
end

-- not in Android Bionic
function C.linkat(olddirfd, oldpath, newdirfd, newpath, flags)
  return syscall(c.SYS.linkat, t.int(olddirfd), void(oldpath), t.int(newdirfd), void(newpath), t.int(flags))
end
function C.symlinkat(oldpath, newdirfd, newpath)
  return syscall(c.SYS.symlinkat, void(oldpath), t.int(newdirfd), void(newpath))
end
function C.readlinkat(dirfd, pathname, buf, bufsiz)
  return syscall(c.SYS.readlinkat, t.int(dirfd), void(pathname), void(buf), t.size(bufsiz))
end
function C.inotify_init1(flags)
  return syscall(c.SYS.inotify_init1, t.int(flags))
end
function C.adjtimex(buf)
  return syscall(c.SYS.adjtimex, void(buf))
end
function C.epoll_create1(flags)
  return syscall(c.SYS.epoll_create1, t.int(flags))
end
function C.epoll_wait(epfd, events, maxevents, timeout)
  return syscall(c.SYS.epoll_wait, t.int(epfd), void(events), t.int(maxevents), t.int(timeout))
end
function C.swapon(path, swapflags)
  return syscall(c.SYS.swapon, void(path), t.int(swapflags))
end
function C.swapoff(path)
  return syscall(c.SYS.swapoff, void(path))
end
function C.timerfd_create(clockid, flags)
  return syscall(c.SYS.timerfd_create, t.int(clockid), t.int(flags))
end
function C.timerfd_settime(fd, flags, new_value, old_value)
  return syscall(c.SYS.timerfd_settime, t.int(fd), t.int(flags), void(new_value), void(old_value))
end
function C.timerfd_gettime(fd, curr_value)
  return syscall(c.SYS.timerfd_gettime, t.int(fd), void(curr_value))
end
function C.splice(fd_in, off_in, fd_out, off_out, len, flags)
  return syscall(c.SYS.splice, t.int(fd_in), void(off_in), t.int(fd_out), void(off_out), t.size(len), t.uint(flags))
end
function C.tee(src, dest, len, flags)
  return syscall(c.SYS.tee, t.int(src), t.int(dest), t.size(len), t.uint(flags))
end
function C.vmsplice(fd, iovec, cnt, flags)
  return syscall(c.SYS.vmsplice, t.int(fd), void(iovec), t.size(cnt), t.uint(flags))
end
-- note that I think these are correct on 32 bit platforms, but strace is buggy
if c.SYS.sync_file_range then
  if abi.abi64 then
    function C.sync_file_range(fd, pos, len, flags)
      return syscall(c.SYS.sync_file_range, t.int(fd), 0, t.long(pos), t.long(len), t.uint(flags))
    end
  else
    if zeropad then
      function C.sync_file_range(fd, pos, len, flags)
        local pos1, pos2 = arg64(pos)
        local len1, len2 = arg64(len)
        return syscall(c.SYS.sync_file_range, t.int(fd), 0, t.long(pos1), t.long(pos2), t.long(len1), t.long(len2), t.uint(flags))
      end
    else
      function C.sync_file_range(fd, pos, len, flags)
       local pos1, pos2 = arg64(pos)
       local len1, len2 = arg64(len)
        return syscall(c.SYS.sync_file_range, t.int(fd), t.long(pos1), t.long(pos2), t.long(len1), t.long(len2), t.uint(flags))
      end
    end
  end
elseif c.SYS.sync_file_range2 then -- only on 32 bit platforms I believe
  function C.sync_file_range(fd, pos, len, flags)
    local pos1, pos2 = arg64(pos)
    local len1, len2 = arg64(len)
    return syscall(c.SYS.sync_file_range2, t.int(fd), t.uint(flags), t.long(pos1), t.long(pos2), t.long(len1), t.long(len2))
  end
end

local sigset_size = 8 -- TODO should be s.sigset once switched to kernel sigset not glibc size

-- now failing on Travis, was ok... TODO work out why
if not C.epoll_pwait then
function C.epoll_pwait(epfd, events, maxevents, timeout, sigmask)
  local size = 0
  if sigmask then size = sigset_size end
  return syscall(c.SYS.epoll_pwait, t.int(epfd), void(events), t.int(maxevents), t.int(timeout), void(sigmask), t.int(size))
end
end

function C.ppoll(fds, nfds, timeout_ts, sigmask)
  local size = 0
  if sigmask then size = sigset_size end
  -- TODO luaffi gets the wrong value for the last param if it is t.int not t.long. See #87.
  return syscall(c.SYS.ppoll, void(fds), t.nfds(nfds), void(timeout_ts), void(sigmask), t.long(size))
end
function C.signalfd(fd, mask, flags)
  return syscall(c.SYS.signalfd4, t.int(fd), void(mask), t.int(sigset_size), t.int(flags))
end

-- adding more
function C.dup(oldfd) return syscall(c.SYS.dup, t.int(oldfd)) end
function C.dup2(oldfd, newfd) return syscall(c.SYS.dup2, t.int(oldfd), t.int(newfd)) end
function C.dup3(oldfd, newfd, flags) return syscall(c.SYS.dup3, t.int(oldfd), t.int(newfd), t.int(flags)) end

-- kernel sigaction structures actually rather different in Linux from libc ones
function C.sigaction(signum, act, oldact)
  return syscall(c.SYS.rt_sigaction, t.int(signum), void(act), void(oldact), t.int(8)) -- size is size of mask field
end

-- socketcall related
if c.SYS.accept4 then -- on x86 this is a socketcall, which we have not implemented yet, other archs is a syscall
  function C.accept4(sockfd, addr, addrlen, flags)
    return syscall(c.SYS.accept4, t.int(sockfd), void(addr), void(addrlen), t.int(flags))
  end
end

return C

end

return {init = init}


