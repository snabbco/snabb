-- this creates types with methods
-- cannot do this in types as the functions have not been defined yet (as they depend on types)
-- well we could, by passing in the empty table for S, but this is more modular

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(S)

local abi = S.abi

local c = S.c
local types = S.types
local t, s, pt = types.t, types.s, types.pt

local bit = require "syscall.bit"

local ffi = require "ffi"

local h = require "syscall.helpers"

local getfd, istype, mktype = h.getfd, h.istype, h.mktype

local function metatype(tp, mt)
  if abi.rumpfn then tp = abi.rumpfn(tp) end
  return ffi.metatype(tp, mt)
end

-- easier interfaces to some functions that are in common use TODO new fcntl code should make easier
local function nonblock(fd)
  local fl, err = S.fcntl(fd, c.F.GETFL)
  if not fl then return nil, err end
  fl, err = S.fcntl(fd, c.F.SETFL, c.O(fl, "nonblock"))
  if not fl then return nil, err end
  return true
end

local function block(fd)
  local fl, err = S.fcntl(fd, c.F.GETFL)
  if not fl then return nil, err end
  fl, err = S.fcntl(fd, c.F.SETFL, c.O(fl, "~nonblock"))
  if not fl then return nil, err end
  return true
end

local function tell(fd) return S.lseek(fd, 0, c.SEEK.CUR) end

-- somewhat confusing now we have flock too. I think this comes from nixio.
local function lockf(fd, cmd, len)
  cmd = c.LOCKF[cmd]
  if cmd == c.LOCKF.LOCK then
    return S.fcntl(fd, c.F.SETLKW, {l_type = c.FCNTL_LOCK.WRLCK, l_whence = c.SEEK.CUR, l_start = 0, l_len = len})
  elseif cmd == c.LOCKF.TLOCK then
    return S.fcntl(fd, c.F.SETLK, {l_type = c.FCNTL_LOCK.WRLCK, l_whence = c.SEEK.CUR, l_start = 0, l_len = len})
  elseif cmd == c.LOCKF.ULOCK then
    return S.fcntl(fd, c.F.SETLK, {l_type = c.FCNTL_LOCK.UNLCK, l_whence = c.SEEK.CUR, l_start = 0, l_len = len})
  elseif cmd == c.LOCKF.TEST then
    local ret, err = S.fcntl(fd, c.F.GETLK, {l_type = c.FCNTL_LOCK.WRLCK, l_whence = c.SEEK.CUR, l_start = 0, l_len = len})
    if not ret then return nil, err end
    return ret.l_type == c.FCNTL_LOCK.UNLCK
  end
end

-- methods on an fd
-- note could split, so a socket does not have methods only appropriate for a file; sometimes you do not know what type an fd is
local fdmethods = {'dup', 'dup2', 'dup3', 'read', 'write', 'pread', 'pwrite',
                   'lseek', 'fchdir', 'fsync', 'fdatasync', 'fstat', 'fcntl', 'fchmod',
                   'bind', 'listen', 'connect', 'accept', 'getsockname', 'getpeername',
                   'send', 'sendto', 'recv', 'recvfrom', 'readv', 'writev', 'sendmsg',
                   'recvmsg', 'setsockopt', 'epoll_ctl', 'epoll_wait', 'sendfile', 'getdents',
                   'ftruncate', 'shutdown', 'getsockopt',
                   'inotify_add_watch', 'inotify_rm_watch', 'inotify_read', 'flistxattr',
                   'fsetxattr', 'fgetxattr', 'fremovexattr', 'fxattr', 'splice', 'vmsplice', 'tee',
                   'timerfd_gettime', 'timerfd_settime',
                   'fadvise', 'fallocate', 'posix_fallocate', 'readahead',
                   'sync_file_range', 'fstatfs', 'futimens', 'futimes',
                   'fstatat', 'unlinkat', 'mkdirat', 'mknodat', 'faccessat', 'fchmodat', 'fchown',
                   'fchownat', 'readlinkat', 'setns', 'openat', 'accept4',
                   'preadv', 'pwritev', 'epoll_pwait', 'ioctl', 'flock', 'fpathconf',
                   'grantpt', 'unlockpt', 'ptsname', 'tcgetattr', 'tcsetattr', 'isatty',
                   'tcsendbreak', 'tcdrain', 'tcflush', 'tcflow', 'tcgetsid',
                   'sendmmsg', 'recvmmsg', 'syncfs',
                   'fchflags', 'fchroot', 'fsync_range', 'kevent', 'paccept', 'fktrace', -- bsd only
                   'pdgetpid', 'pdkill' -- freebsd only
                   }
local fmeth = {}
for _, v in ipairs(fdmethods) do fmeth[v] = S[v] end

-- defined above
fmeth.block = block
fmeth.nonblock = nonblock
fmeth.tell = tell
fmeth.lockf = lockf

-- fd not first argument
fmeth.mmap = function(fd, addr, length, prot, flags, offset) return S.mmap(addr, length, prot, flags, fd, offset) end
if S.bindat then fmeth.bindat = function(s, dirfd, addr, addrlen) return S.bindat(dirfd, s, addr, addrlen) end end
if S.connectat then fmeth.connectat = function(s, dirfd, addr, addrlen) return S.connectat(dirfd, s, addr, addrlen) end end

-- allow calling without leading f
fmeth.stat = S.fstat
fmeth.chdir = S.fchdir
fmeth.sync = S.fsync
fmeth.datasync = S.fdatasync
fmeth.chmod = S.fchmod
fmeth.setxattr = S.fsetxattr
fmeth.getxattr = S.gsetxattr
fmeth.truncate = S.ftruncate
fmeth.statfs = S.fstatfs
fmeth.utimens = S.futimens
fmeth.utimes = S.futimes
fmeth.seek = S.lseek
fmeth.chown = S.fchown
fmeth.lock = S.flock
fmeth.pathconf = S.fpathconf
-- netbsd only
fmeth.chflags = S.fchflags
fmeth.chroot = S.fchroot
fmeth.sync_range = S.fsync_range
fmeth.ktrace = S.fktrace
-- no point having fd in name - bsd only
fmeth.extattr_get = S.extattr_get_fd
fmeth.extattr_set = S.extattr_set_fd
fmeth.extattr_delete = S.extattr_delete_fd
fmeth.extattr_list = S.extattr_list_fd

local function nogc(d) return ffi.gc(d, nil) end

fmeth.nogc = nogc

-- sequence number used by netlink messages
fmeth.seq = function(fd)
  fd.sequence = fd.sequence + 1
  return fd.sequence
end

-- TODO note this is not very friendly to user, as will just get EBADF from all calls
function fmeth.close(fd)
  local fileno = getfd(fd)
  if fileno == -1 then return true end -- already closed
  local ok, err = S.close(fileno)
  fd.filenum = -1 -- make sure cannot accidentally close this fd object again
  return ok, err
end

fmeth.getfd = function(fd) return fd.filenum end

t.fd = metatype("struct {int filenum; int sequence;}", {
  __index = fmeth,
  __gc = fmeth.close,
  __new = function(tp, i)
    return istype(tp, i) or ffi.new(tp, i or -1)
  end,
})

S.stdin = t.fd(c.STD.IN):nogc()
S.stdout = t.fd(c.STD.OUT):nogc()
S.stderr = t.fd(c.STD.ERR):nogc()

if S.mq_open then -- TODO better test. TODO support in BSD
local mqmeth = {
  close = fmeth.close,
  nogc = nogc,
  getfd = function(fd) return fd.filenum end,
  getattr = function(mqd, attr)
    attr = attr or t.mq_attr()
    local ok, err = S.mq_getsetattr(mqd, nil, attr)
    if not ok then return nil, err end
    return attr
  end,
  setattr = function(mqd, attr)
    if type(attr) == "number" or type(attr) == "string" then attr = {flags = attr} end -- only flags can be set so allow this
    attr = mktype(t.mq_attr, attr)
    return S.mq_getsetattr(mqd, attr, nil)
  end,
  timedsend = S.mq_timedsend,
  send = function(mqd, msg_ptr, msg_len, msg_prio) return S.mq_timedsend(mqd, msg_ptr, msg_len, msg_prio) end,
  timedreceive = S.mq_timedreceive,
  receive = function(mqd, msg_ptr, msg_len, msg_prio) return S.mq_timedreceive(mqd, msg_ptr, msg_len, msg_prio) end,
}

t.mqd = metatype("struct {mqd_t filenum;}", {
  __index = mqmeth,
  __gc = mqmeth.close,
  __new = function(tp, i)
    return istype(tp, i) or ffi.new(tp, i or -1)
  end,
})
end

-- TODO deal with delete twice issue with delete and gc
t.timer = metatype("struct {timer_t timerid[1];}", {
  __index = {
    gettimerp = function(self) return self.timerid end,
    gettimer = function(self) return self.timerid[0] end,
    settime = S.timer_settime,
    gettime = S.timer_gettime,
    delete = S.timer_delete,
    getoverrun = S.timer_getoverrun,
  },
--__gc = S.timer_delete,
})

if abi.os == "linux" then
  -- Linux performance monitoring reader
  t.perf_reader = metatype("struct {int fd; char *map; size_t map_pages; }", {
    __new = function (ct, fd)
      if not fd then return ffi.new(ct) end
      if istype(t.fd, fd) then fd = fd:nogc():getfd() end
      return ffi.new(ct, fd)
    end,
    __len = function(t) return ffi.sizeof(t) end,
    __gc = function (t) t:close() end,
    __index = {
      close = function(t)
        t:munmap()
        if t.fd > 0 then S.close(t.fd) end
      end,
      munmap = function (t)
        if t.map_pages > 0 then
          S.munmap(t.map, (t.map_pages + 1) * S.getpagesize())
          t.map_pages = 0
        end
      end,
      -- read(2) interface, see `perf_attr.read_format`
      -- @return u64 or an array of u64
      read = function (t, len)
        local rvals = ffi.new('uint64_t [4]')
        local nb, err = S.read(t.fd, rvals, len or ffi.sizeof(rvals))
        if not nb then return nil, err end
        return nb == 8 and rvals[0] or rvals
      end,
      -- mmap(2) interface, see sampling interface (`perf_attr.sample_type` and `perf_attr.mmap`)
      -- first page is metadata page, the others are sample_type dependent
      mmap = function (t, pages)
        t:munmap()
        pages = pages or 8
        local map, err = S.mmap(nil, (pages + 1) * S.getpagesize(), "read, write", "shared", t.fd, 0)
        if not map then return nil, err end
        t.map = map
        t.map_pages = pages
        return pages
      end,
      meta = function (t)
        return t.map_pages > 0 and ffi.cast("struct perf_event_mmap_page *", t.map) or nil
      end,
      -- next() function for __ipairs returning (len, event) pairs
      -- it only retires read events when current event length is passed
      next = function (t, curlen)
        local buffer_size = S.getpagesize() * t.map_pages
        local base = t.map + S.getpagesize()
        local meta = t:meta()
        -- Retire last read event or start iterating
        if curlen then
          meta.data_tail = meta.data_tail + curlen
        end
        -- End of ring buffer, yield
        -- TODO: <insert memory barrier here>
        if meta.data_head == meta.data_tail then
          return
        end
        local e = pt.perf_event_header(base + (meta.data_tail % buffer_size))
        local e_end = base + (meta.data_tail + e.size) % buffer_size;
        -- If the perf event wraps around the ring, we need to make a contiguous copy
        if ffi.cast("uintptr_t", e_end) < ffi.cast("uintptr_t", e) then
          local tmp_e = ffi.new("char [?]", e.size)
          local len = (base + buffer_size) - ffi.cast('char *', e)
          ffi.copy(tmp_e, e, len)
          ffi.copy(tmp_e + len, base, e.size - len)
          e = ffi.cast(ffi.typeof(e), tmp_e)
        end
        return e.size, e
      end,
      -- Various ioctl() wrappers
      ioctl = function(t, cmd, val) return S.ioctl(t.fd, cmd, val or 0) end,
      start = function(t) return t:ioctl("PERF_EVENT_IOC_ENABLE") end,
      stop = function(t) return t:ioctl("PERF_EVENT_IOC_DISABLE") end,
      refresh = function(t) return t:ioctl("PERF_EVENT_IOC_REFRESH") end,
      reset = function(t) return t:ioctl("PERF_EVENT_IOC_RESET") end,
      setfilter = function(t, val) return t:ioctl("PERF_EVENT_IOC_SET_FILTER", val) end,
      setbpf = function(t, fd) return t:ioctl("PERF_EVENT_IOC_SET_BPF", pt.void(fd)) end,
    },
    __ipairs = function(t) return t.next, t, nil end
  })
end

-- TODO reinstate this, more like fd is, hence changes to destroy
--[[
t.aio_context = metatype("struct {aio_context_t ctx;}", {
  __index = {destroy = S.io_destroy, submit = S.io_submit, getevents = S.io_getevents, cancel = S.io_cancel, nogc = nogc},
  __gc = S.io_destroy
})
]]

return S

end

return {init = init}

