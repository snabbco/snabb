-- this file now does very little, just makes some modifications to syscalls
-- TODO want to try to remove everything from here

local c = require "syscall.constants"
local C = require "syscall.c"
local types = require "syscall.types"
local abi = require "syscall.abi"
local h = require "syscall.helpers"
local S = require "syscall.syscalls".init(C, c, types, abi)

local t, pt, s = types.t, types.pt, types.s

local ffi = require "ffi"

-- TODO these are duplicated, if this code stays here then refactor, but ideally it does not
local function istype(tp, x) if ffi.istype(tp, x) then return x else return false end end
local function mktype(tp, x) if ffi.istype(tp, x) then return x else return tp(x) end end
local function getfd(fd)
  if type(fd) == "number" or ffi.istype(t.int, fd) then return fd end
  return fd:getfd()
end
local zeropointer = pt.void(0)
local function retbool(ret)
  if ret == -1 then return nil, t.error() end
  return true
end

-- 'macros' and helper functions etc
-- TODO from here (approx, some may be in wrong place), move to syscall.util library.

-- handle environment (Lua only provides os.getenv). TODO add metatable to make more Lualike.
function S.environ() -- return whole environment as table
  local environ = ffi.C.environ
  if not environ then return nil end
  local r = {}
  local i = 0
  while environ[i] ~= zeropointer do
    local e = ffi.string(environ[i])
    local eq = e:find('=')
    if eq then
      r[e:sub(1, eq - 1)] = e:sub(eq + 1)
    end
    i = i + 1
  end
  return r
end

function S.getenv(name)
  return S.environ()[name]
end
function S.unsetenv(name) return retbool(ffi.C.unsetenv(name)) end
function S.setenv(name, value, overwrite)
  overwrite = h.booltoc(overwrite) -- allows nil as false/0
  return retbool(ffi.C.setenv(name, value, overwrite))
end
function S.clearenv() return retbool(C.clearenv()) end

function S.nonblock(fd)
  local fl, err = S.fcntl(fd, c.F.GETFL)
  if not fl then return nil, err end
  fl, err = S.fcntl(fd, c.F.SETFL, bit.bor(fl, c.O.NONBLOCK))
  if not fl then return nil, err end
  return true
end

function S.block(fd)
  local fl, err = S.fcntl(fd, c.F.GETFL)
  if not fl then return nil, err end
  fl, err = S.fcntl(fd, c.F.SETFL, bit.band(fl, bit.bnot(c.O.NONBLOCK)))
  if not fl then return nil, err end
  return true
end

-- Nixio compatibility to make porting easier, and useful functions (often man 3). Incomplete.
function S.setblocking(s, b) if b then return S.block(s) else return S.nonblock(s) end end
function S.tell(fd) return S.lseek(fd, 0, c.SEEK.CUR) end

function S.lockf(fd, cmd, len)
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

-- constants TODO move to table
S.INADDR_ANY = t.in_addr()
S.INADDR_LOOPBACK = t.in_addr("127.0.0.1")
S.INADDR_BROADCAST = t.in_addr("255.255.255.255")
-- ipv6 versions
S.in6addr_any = t.in6_addr()
S.in6addr_loopback = t.in6_addr("::1")

-- modified types; we do not really want them here but types cannot set as syscalls not defined TODO fix this

-- methods on an fd
-- note could split, so a socket does not have methods only appropriate for a file
local fdmethods = {'nonblock', 'block', 'setblocking', 'sendfds', 'sendcred',
                   'dup', 'read', 'write', 'pread', 'pwrite', 'tell', 'lockf',
                   'lseek', 'fchdir', 'fsync', 'fdatasync', 'fstat', 'fcntl', 'fchmod',
                   'bind', 'listen', 'connect', 'accept', 'getsockname', 'getpeername',
                   'send', 'sendto', 'recv', 'recvfrom', 'readv', 'writev', 'sendmsg',
                   'recvmsg', 'setsockopt', 'epoll_ctl', 'epoll_wait', 'sendfile', 'getdents',
                   'ftruncate', 'shutdown', 'getsockopt',
                   'inotify_add_watch', 'inotify_rm_watch', 'inotify_read', 'flistxattr',
                   'fsetxattr', 'fgetxattr', 'fremovexattr', 'fxattr', 'splice', 'vmsplice', 'tee',
                   'timerfd_gettime', 'timerfd_settime',
                   'fadvise', 'fallocate', 'posix_fallocate', 'readahead',
                   'sync_file_range', 'fstatfs', 'futimens',
                   'fstatat', 'unlinkat', 'mkdirat', 'mknodat', 'faccessat', 'fchmodat', 'fchown',
                   'fchownat', 'readlinkat', 'setns', 'openat',
                   'preadv', 'pwritev', 'epoll_pwait', 'ioctl'
                   }
local fmeth = {}
for _, v in ipairs(fdmethods) do fmeth[v] = S[v] end

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
fmeth.utime = S.futimens
fmeth.seek = S.lseek
fmeth.lock = S.lockf
fmeth.chown = S.fchown

local function nogc(d) return ffi.gc(d, nil) end

fmeth.nogc = nogc

-- sequence number used by netlink messages
fmeth.seq = function(fd)
  fd.sequence = fd.sequence + 1
  return fd.sequence
end

function fmeth.close(fd)
  local fileno = getfd(fd)
  if fileno == -1 then return true end -- already closed
  local ok, err = S.close(fileno)
  fd.filenum = -1 -- make sure cannot accidentally close this fd object again
  return ok, err
end

fmeth.getfd = function(fd) return fd.filenum end

t.fd = ffi.metatype("struct {int filenum; int sequence;}", {
  __index = fmeth,
  __gc = fmeth.close,
  __new = function(tp, i)
    return istype(tp, i) or ffi.new(tp, i)
  end,
})

mqmeth = {
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

t.mqd = ffi.metatype("struct {mqd_t filenum;}", {
  __index = mqmeth,
  __gc = mqmeth.close,
  __new = function(tp, i)
    return istype(tp, i) or ffi.new(tp, i)
  end,
})

-- override socketpair to provide methods
local mt_socketpair = {
  __index = {
    close = function(s)
      local ok1, err1 = s[1]:close()
      local ok2, err2 = s[2]:close()
      if not ok1 then return nil, err1 end
      if not ok2 then return nil, err2 end
      return true
    end,
    nonblock = function(s)
      local ok, err = S.nonblock(s[1])
      if not ok then return nil, err end
      local ok, err = S.nonblock(s[2])
      if not ok then return nil, err end
      return true
    end,
    block = function(s)
      local ok, err = S.block(s[1])
      if not ok then return nil, err end
      local ok, err = S.block(s[2])
      if not ok then return nil, err end
      return true
    end,
    setblocking = function(s, b)
      local ok, err = S.setblocking(s[1], b)
      if not ok then return nil, err end
      local ok, err = S.setblocking(s[2], b)
      if not ok then return nil, err end
      return true
    end,
  }
}

t.socketpair = function(s1, s2)
  if ffi.istype(t.int2, s1) then s1, s2 = s1[0], s1[1] end
  return setmetatable({t.fd(s1), t.fd(s2)}, mt_socketpair)
end

-- override pipe to provide methods
local mt_pipe = {
  __index = {
    close = function(p)
      local ok1, err1 = p[1]:close()
      local ok2, err2 = p[2]:close()
      if not ok1 then return nil, err1 end
      if not ok2 then return nil, err2 end
      return true
    end,
    read = function(p, ...) return S.read(p[1], ...) end,
    write = function(p, ...) return S.write(p[2], ...) end,
    nonblock = function(p)
      local ok, err = p[1]:nonblock()
      if not ok then return nil, err end
      local ok, err = p[2]:nonblock()
      if not ok then return nil, err end
      return true
    end,
    block = function(p)
      local ok, err = p[1]:block()
      if not ok then return nil, err end
      local ok, err = p[2]:block()
      if not ok then return nil, err end
      return true
    end,
    setblocking = function(p, b)
      local ok, err = p[1]:setblocking(b)
      if not ok then return nil, err end
      local ok, err = p[2]:setblocking(b)
      if not ok then return nil, err end
      return true
    end,
    -- TODO many useful methods still missing
  }
}

t.pipe = function(s1, s2)
  if ffi.istype(t.int2, s1) then s1, s2 = s1[0], s1[1] end
  return setmetatable({t.fd(s1), t.fd(s2)}, mt_pipe)
end

S.stdin = t.fd(c.STD.IN):nogc()
S.stdout = t.fd(c.STD.OUT):nogc()
S.stderr = t.fd(c.STD.ERR):nogc()

-- TODO reinstate this, more like fd is, hence changes to destroy
--[[
t.aio_context = ffi.metatype("struct {aio_context_t ctx;}", {
  __index = {destroy = S.io_destroy, submit = S.io_submit, getevents = S.io_getevents, cancel = S.io_cancel, nogc = nogc},
  __gc = S.io_destroy
})
]]

return S

