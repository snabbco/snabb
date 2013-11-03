-- This sets up the table of C functions, overriding libc where necessary with direct syscalls

-- ffi.C (ie libc) is the default fallback via the metatable, but we override stuff that might be missing, has different semantics
-- or which we cannot detect sanely which ABI is being presented.

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(abi, c)

local ffi = require "ffi"

local bit = require "syscall.bit"

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
local sys = c.SYS

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
    function C.pread(fd, buf, size, offset)
      local off1, off2 = arg64(offset)
      return syscall(sys.pread64, int(fd), void(buf), ulong(size), int(0), long(off1), long(off2))
    end
    function C.pwrite(fd, buf, size, offset)
      local off1, off2 = arg64(offset)
      return syscall(sys.pwrite64, int(fd), void(buf), ulong(size), int(0), long(off1), long(off2))
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
    function C.pread(fd, buf, size, offset)
      local off1, off2 = arg64(offset)
      return syscall(sys.pread64, int(fd), void(buf), ulong(size), long(off1), long(off2))
    end
    function C.pwrite(fd, buf, size, offset)
      local off1, off2 = arg64(offset)
      return syscall(sys.pwrite64, int(fd), void(buf), ulong(size), long(off1), long(off2))
    end
  end
  -- note statfs,fstatfs pass size of struct
  function C.statfs(path, buf) return syscall(sys.statfs64, path, uint(ffi.sizeof(buf)), void(buf)) end
  function C.fstatfs(fd, buf) return syscall(sys.fstatfs64, int(fd), uint(ffi.sizeof(buf)), void(buf)) end
  -- Note very odd split 64 bit arguments even on 64 bit platform.
  function C.preadv(fd, iov, iovcnt, offset)
    local off1, off2 = llarg64(offset)
    return syscall(sys.preadv, int(fd), void(iov), int(iovcnt), long(off2), long(off1))
  end
  function C.pwritev(fd, iov, iovcnt, offset)
    local off1, off2 = llarg64(offset)
    return syscall(sys.pwritev, int(fd), void(iov), int(iovcnt), long(off2), long(off1))
  end
  -- lseek is a mess in 32 bit, use _llseek syscall to get clean result.
  -- TODO move this to syscall.lua
  local off1 = ffi.typeof("uint64_t[1]")
  function C.lseek(fd, offset, whence)
    local result = off1()
    local off1, off2 = llarg64u(offset)
    local ret = syscall(sys._llseek, int(fd), ulong(off1), ulong(off2), void(result), uint(whence))
    if ret == -1 then return err64 end
    return result[0]
  end
  function C.sendfile(outfd, infd, offset, count)
    return syscall(sys.sendfile64, int(outfd), int(infd), void(offset), ulong(count))
  end
  -- on 32 bit systems mmap uses off_t so we cannot tell what ABI is. Use underlying mmap2 syscall
  function C.mmap(addr, length, prot, flags, fd, offset)
    local pgoffset = bit.rshift(offset, 12)
    return void(syscall(sys.mmap2, void(addr), ulong(length), int(prot), int(flags), int(fd), uint(pgoffset)))
  end
end

-- glibc caches pid, but this fails to work eg after clone().
function C.getpid() return syscall(sys.getpid) end

-- exit_group is the normal syscall but not available
function C.exit_group(status) return syscall(sys.exit_group, int(status)) end

-- clone interface provided is not same as system one, and is less convenient
function C.clone(flags, signal, stack, ptid, tls, ctid)
  return syscall(sys.clone, int(flags), void(stack), void(ptid), void(tls), void(ctid))
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
function C.getpriority(which, who)
  return syscall(sys.getpriority, int(which), int(who))
end

-- uClibc only provides a version of eventfd without flags, and we cannot detect this
function C.eventfd(initval, flags)
  return syscall(sys.eventfd2, uint(initval), int(flags))
end

-- glibc does not provide getcpu
function C.getcpu(cpu, node, tcache)
  return syscall(sys.getcpu, void(node), void(node), void(tcache))
end

-- Musl always returns ENOSYS for these
function C.sched_getscheduler(pid)
  return syscall(sys.sched_getscheduler, int(pid))
end
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
function C.clock_gettime(clk_id, ts)
  return syscall(sys.clock_gettime, int(clk_id), void(ts))
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
-- note that I think these are correct on 32 bit platforms, but strace is buggy
if sys.sync_file_range then
  if abi.abi64 then
    function C.sync_file_range(fd, pos, len, flags)
      return syscall(sys.sync_file_range, int(fd), 0, long(pos), long(len), uint(flags))
    end
  else
    if zeropad then
      function C.sync_file_range(fd, pos, len, flags)
        local pos1, pos2 = arg64(pos)
        local len1, len2 = arg64(len)
        return syscall(sys.sync_file_range, int(fd), 0, long(pos1), long(pos2), long(len1), long(len2), uint(flags))
      end
    else
      function C.sync_file_range(fd, pos, len, flags)
       local pos1, pos2 = arg64(pos)
       local len1, len2 = arg64(len)
        return syscall(sys.sync_file_range, int(fd), long(pos1), long(pos2), long(len1), long(len2), uint(flags))
      end
    end
  end
elseif sys.sync_file_range2 then -- only on 32 bit platforms I believe
  function C.sync_file_range(fd, pos, len, flags)
    local pos1, pos2 = arg64(pos)
    local len1, len2 = arg64(len)
    return syscall(sys.sync_file_range2, int(fd), uint(flags), long(pos1), long(pos2), long(len1), long(len2))
  end
end

local sigset_size = 8 -- TODO should be s.sigset once switched to kernel sigset not glibc size

-- now failing on Travis, was ok... TODO work out why
if not C.epoll_pwait then
function C.epoll_pwait(epfd, events, maxevents, timeout, sigmask)
  local size = 0
  if sigmask then size = sigset_size end
  return syscall(sys.epoll_pwait, int(epfd), void(events), int(maxevents), int(timeout), void(sigmask), int(size))
end
end

function C.ppoll(fds, nfds, timeout_ts, sigmask)
  local size = 0
  if sigmask then size = sigset_size end
  -- TODO luaffi gets the wrong value for the last param if it is int not long. See #87.
  return syscall(sys.ppoll, void(fds), ulong(nfds), void(timeout_ts), void(sigmask), long(size))
end
function C.signalfd(fd, mask, flags)
  return syscall(sys.signalfd4, int(fd), void(mask), int(sigset_size), int(flags))
end

-- adding more
function C.dup(oldfd) return syscall(sys.dup, int(oldfd)) end
function C.dup2(oldfd, newfd) return syscall(sys.dup2, int(oldfd), int(newfd)) end
function C.dup3(oldfd, newfd, flags) return syscall(sys.dup3, int(oldfd), int(newfd), int(flags)) end

-- kernel sigaction structures actually rather different in Linux from libc ones
function C.sigaction(signum, act, oldact)
  return syscall(sys.rt_sigaction, int(signum), void(act), void(oldact), int(8)) -- size is size of mask field
end

-- socketcall related
if sys.accept4 then -- on x86 this is a socketcall, which we have not implemented yet, other archs is a syscall
  function C.accept4(sockfd, addr, addrlen, flags)
    return syscall(sys.accept4, int(sockfd), void(addr), void(addrlen), int(flags))
  end
end

return C

end

return {init = init}


