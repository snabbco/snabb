-- This sets up the table of C functions, overriding libc where necessary with direct syscalls

-- ffi.C (ie libc) is the default fallback via the metatable, but we override stuff that might be missing, has different semantics
-- or which we cannot detect sanely which ABI is being presented.

local ffi = require "ffi"

local c = require "syscall.constants"
local abi = require "syscall.abi"

local types = require "syscall.types"
local t, pt, s = types.t, types.pt, types.s

local function u6432(x) return t.u6432(x):to32() end
local function i6432(x) return t.i6432(x):to32() end

local C = setmetatable({}, {__index = ffi.C})

local CC = {} -- functions that might not be in C, may use syscalls

-- use 64 bit fileops on 32 bit always
if abi.abi32 then
  C.truncate = ffi.C.truncate64
  C.ftruncate = ffi.C.ftruncate64
  C.statfs = ffi.C.statfs64
  C.fstatfs = ffi.C.fstatfs64
  C.pread = ffi.C.pread64
  C.pwrite = ffi.C.pwrite64
  C.preadv = ffi.C.preadv64
  C.pwritev = ffi.C.pwritev64
end

-- test if function in libc
local function inlibc_fn(f) return ffi.C[f] end
local function inlibc(f) return pcall(inlibc_fn, f) end

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

-- getcwd in libc will allocate memory, so use syscall
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
      local off2, off1 = u6432(offset)
      local len2, len1 = u6432(len)
      return C.syscall(sys_fadvise64, t.int(fd), 0, t.uint32(off1), t.uint32(off2), t.uint32(len1), t.uint32(len2), t.int(advise))
    end
  else
    function C.fadvise64(fd, offset, len, advise)
      local off2, off1 = u6432(offset)
      local len2, len1 = u6432(len)
      return C.syscall(sys_fadvise64, t.int(fd), t.uint32(off1), t.uint32(off2), t.uint32(len1), t.uint32(len2), t.int(advise))
    end
  end
  if c.syscall.fallocate then
    function C.fallocate(fd, mode, offset, len)
      local off2, off1 = u6432(offset)
      local len2, len1 = u6432(len)
      return C.syscall(c.SYS.fallocate, t.int(fd), t.uint(mode), t.uint32(off2), t.uint32(off1), t.uint32(len2), t.uint32(len1))
    end
  else
    function C.fallocate(fd, mode, offset, len)
      local off2, off1 = u6432(offset)
      local len2, len1 = u6432(len)
      return C.syscall(c.SYS.fallocate, t.int(fd), t.uint(mode), t.uint32(off1), t.uint32(off2), t.uint32(len1), t.uint32(len2))
    end
  end
end

-- lseek is a mess in 32 bit, use _llseek syscall to get clean result
if abi.abi32 then
  function C.lseek(fd, offset, whence)
    local result = t.off1()
    local off1, off2 = u6432(offset)
    local ret = C.syscall(c.SYS._llseek, t.int(fd), t.ulong(off1), t.ulong(off2), pt.void(result), t.uint(whence))
    if ret == -1 then return -1 end
    return result[0]
  end
end

-- on 32 bit systems mmap uses off_t so we cannot tell what ABI is. Use underlying mmap2 syscall
if abi.abi32 then
  function C.mmap(addr, length, prot, flags, fd, offset)
    local pgoffset = math.floor(offset / 4096)
    return pt.void(C.syscall(c.SYS.mmap2, pt.void(addr), t.size(length), t.int(prot), t.int(flags), t.int(fd), t.uint32(pgoffset)))
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

-- note dev_t not passed as 64 bits to this syscall
function CC.mknod(pathname, mode, dev)
  return C.syscall(c.SYS.mknod, pathname, t.mode(mode), t.long(dev))
end
function CC.mknodat(fd, pathname, mode, dev)
  return C.syscall(c.SYS.mknodat, t.int(fd), pathname, t.mode(mode), t.long(dev))
end
-- pivot_root is not provided by glibc, is provided by Musl
function CC.pivot_root(new_root, put_old)
  return C.syscall(c.SYS.pivot_root, new_root, put_old)
end
-- setns not in some glibc versions
function CC.setns(fd, nstype)
  return C.syscall(c.SYS.setns, t.int(fd), t.int(nstype))
end
-- prlimit64 not in my ARM glibc
function CC.prlimit64(pid, resource, new_limit, old_limit)
  return C.syscall(c.SYS.prlimit64, t.pid(pid), t.int(resource), pt.void(new_limit), pt.void(old_limit))
end

-- you can get these functions from ffi.load "rt" in glibc but this upsets valgrind so get from syscalls
function CC.clock_nanosleep(clk_id, flags, req, rem)
  return C.syscall(c.SYS.clock_nanosleep, t.clockid(clk_id), t.int(flags), pt.void(req), pt.void(rem))
end
function CC.clock_getres(clk_id, ts)
  return C.syscall(c.SYS.clock_getres, t.clockid(clk_id), pt.void(ts))
end
function CC.clock_gettime(clk_id, ts)
  return C.syscall(c.SYS.clock_gettime, t.clockid(clk_id), pt.void(ts))
end
function CC.clock_settime(clk_id, ts)
  return C.syscall(c.SYS.clock_settime, t.clockid(clk_id), pt.void(ts))
end

-- missing in uClibc. Note very odd split 64 bit arguments even on 64 bit platform.
function CC.preadv64(fd, iov, iovcnt, offset)
  local off2, off1 = i6432(offset)
  return C.syscall(c.SYS.preadv, t.int(fd), pt.void(iov), t.int(iovcnt), t.long(off1), t.long(off2))
end
function CC.pwritev64(fd, iov, iovcnt, offset)
  local off2, off1 = i6432(offset)
  return C.syscall(c.SYS.pwritev, t.int(fd), pt.void(iov), t.int(iovcnt), t.long(off1), t.long(off2))
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

-- if not in libc replace

-- in librt for glibc but use syscalls instead
if not inlibc("clock_getres") then C.clock_getres = CC.clock_getres end
if not inlibc("clock_settime") then C.clock_settime = CC.clock_settime end
if not inlibc("clock_gettime") then C.clock_gettime = CC.clock_gettime end
if not inlibc("clock_nanosleep") then C.clock_nanosleep = CC.clock_nanosleep end

-- not in glibc
if not inlibc("mknod") then C.mknod = CC.mknod end
if not inlibc("mknodat") then C.mknodat = CC.mknodat end
if not inlibc("pivot_root") then C.pivot_root = CC.pivot_root end

-- not in glibc on my dev ARM box
if not inlibc("setns") then C.setns = CC.setns end
if not inlibc("prlimit64") then C.prlimit64 = CC.prlimit64 end

-- not in uClibc
if abi.abi32 then
  if not inlibc("preadv64") then C.preadv = CC.preadv64 end
  if not inlibc("pwritev64") then C.pwritev = CC.pwritev64 end
end

return C

