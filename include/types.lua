-- Linux kernel types
-- these are either simple ffi types or ffi metatypes for the kernel types
-- plus some Lua metatables for types that cannot be sensibly done as Lua types eg arrays, integers

-- TODO this currently requires being called with S from syscall which breaks modularity
-- TODO should fix this, should just need constants (which it could return)

-- note that some types will be overridden, eg default fd type will have metamethods added TODO document and test

local ffi = require "ffi"
local bit = require "bit"

require "include.headers"

local c = require "include.constants"

local C = ffi.C -- for inet_pton etc, due to be replaced with Lua

local types = {}

local t, pt, s, ctypes = {}, {}, {}, {} -- types, pointer types and sizes tables
types.t, types.pt, types.s, types.ctypes = t, pt, s, ctypes

local mt = {} -- metatables
local meth = {}

-- use 64 bit stat type always
local stattypename = "struct stat"
if ffi.abi("32bit") then
  stattypename = "struct stat64"
end

-- makes code tidier
local function istype(tp, x)
  if ffi.istype(tp, x) then return x else return false end
end

-- TODO cleanup this (what should provide this?)
local signal_reasons_gen = {}
local signal_reasons = {}

for k, v in pairs(c.SI) do
  signal_reasons_gen[v] = k
end

signal_reasons[c.SIG.ILL] = {}
for k, v in pairs(c.SIGILL) do
  signal_reasons[c.SIG.ILL][v] = k
end

signal_reasons[c.SIG.FPE] = {}
for k, v in pairs(c.SIGFPE) do
  signal_reasons[c.SIG.FPE][v] = k
end

signal_reasons[c.SIG.SEGV] = {}
for k, v in pairs(c.SIGSEGV) do
  signal_reasons[c.SIG.SEGV][v] = k
end

signal_reasons[c.SIG.BUS] = {}
for k, v in pairs(c.SIGBUS) do
  signal_reasons[c.SIG.BUS][v] = k
end

signal_reasons[c.SIG.TRAP] = {}
for k, v in pairs(c.SIGTRAP) do
  signal_reasons[c.SIG.TRAP][v] = k
end

signal_reasons[c.SIG.CHLD] = {}
for k, v in pairs(c.SIGCLD) do
  signal_reasons[c.SIG.CHLD][v] = k
end

signal_reasons[c.SIG.POLL] = {}
for k, v in pairs(c.SIGPOLL) do
  signal_reasons[c.SIG.POLL][v] = k
end

-- endian conversion
-- TODO add tests eg for signs.
local htonl, htons
if ffi.abi("be") then -- nothing to do
  function htonl(b) return b end
else
  function htonl(b) return bit.bswap(b) end
  function htons(b) return bit.rshift(bit.bswap(b), 16) end
end
local ntohl = htonl -- reverse is the same
local ntohs = htons -- reverse is the same

-- functions we use from man(3)

local function strerror(errno) return ffi.string(ffi.C.strerror(errno)) end

-- Lua type constructors corresponding to defined types
-- basic types

-- cast to pointer to a type. could generate for all types.
local function ptt(tp)
  local ptp = ffi.typeof("$ *", tp)
  return function(x) return ffi.cast(ptp, x) end
end

local function addtype(name, tp, mt)
  if mt then t[name] = ffi.metatype(tp, mt) else t[name] = ffi.typeof(tp) end
  ctypes[tp] = t[name]
  pt[name] = ptt(t[name])
  s[name] = ffi.sizeof(t[name])
end

local metatype = addtype

local addtypes = {
  char = "char",
  uchar = "unsigned char",
  int = "int",
  uint = "unsigned int",
  uint16 = "uint16_t",
  int32 = "int32_t",
  uint32 = "uint32_t",
  int64 = "int64_t",
  uint64 = "uint64_t",
  long = "long",
  ulong = "unsigned long",
  uintptr = "uintptr_t",
  size = "size_t",
  mode = "mode_t",
  dev = "dev_t",
  loff = "loff_t",
  sa_family = "sa_family_t",
  fdset = "fd_set",
  msghdr = "struct msghdr",
  cmsghdr = "struct cmsghdr",
  ucred = "struct ucred",
  sysinfo = "struct sysinfo",
  epoll_event = "struct epoll_event",
  nlmsghdr = "struct nlmsghdr",
  rtgenmsg = "struct rtgenmsg",
  rtmsg = "struct rtmsg",
  ifinfomsg = "struct ifinfomsg",
  ifaddrmsg = "struct ifaddrmsg",
  rtattr = "struct rtattr",
  rta_cacheinfo = "struct rta_cacheinfo",
  nlmsgerr = "struct nlmsgerr",
  timex = "struct timex",
  utsname = "struct utsname",
  fdb_entry = "struct fdb_entry",
  iocb = "struct iocb",
  sighandler = "sighandler_t",
  sigaction = "struct sigaction",
  clockid = "clockid_t",
  io_event = "struct io_event",
  seccomp_data = "struct seccomp_data",
  iovec = "struct iovec",
  rtnl_link_stats = "struct rtnl_link_stats",
  statfs = "struct statfs64",
  ifreq = "struct ifreq",
  dirent = "struct linux_dirent64",
  ifa_cacheinfo = "struct ifa_cacheinfo",
  flock = "struct flock64",
  mqattr = "struct mq_attr",
}

for k, v in pairs(addtypes) do addtype(k, v) end

-- these ones not in table as not helpful with vararg or arrays
t.inotify_event = ffi.typeof("struct inotify_event")
t.epoll_events = ffi.typeof("struct epoll_event[?]") -- TODO add metatable, like pollfds
t.io_events = ffi.typeof("struct io_event[?]")
t.iocbs = ffi.typeof("struct iocb[?]")

t.iocb_ptrs = ffi.typeof("struct iocb *[?]")
t.string_array = ffi.typeof("const char *[?]")

t.ints = ffi.typeof("int[?]")
t.buffer = ffi.typeof("char[?]")

t.int1 = ffi.typeof("int[1]")
t.int64_1 = ffi.typeof("int64_t[1]")
t.uint64_1 = ffi.typeof("uint64_t[1]")
t.socklen1 = ffi.typeof("socklen_t[1]")
t.off1 = ffi.typeof("off_t[1]")
t.loff1 = ffi.typeof("loff_t[1]")
t.uid1 = ffi.typeof("uid_t[1]")
t.gid1 = ffi.typeof("gid_t[1]")
t.int2 = ffi.typeof("int[2]")
t.timespec2 = ffi.typeof("struct timespec[2]")

-- still need pointers to these
pt.inotify_event = ptt(t.inotify_event)

-- types with metatypes

-- fd type. This will be overridden by syscall as it adds methods
-- so this is the minimal one necessary to provide the interface eg does not gc file
-- TODO add tests once types is standalone

--[[
mt.fd = {
  __index = {
    getfd = function(fd) return fd.fileno end,
  },
  __new = function(tp, i)
    return istype(tp, i) or ffi.new(tp, i)
  end
}

metatype("fd", "struct {int fileno;}", mt.fd)
]]
-- even simpler version, just pass numbers
t.fd = function(fd) return tonumber(fd) end

-- can replace with a different t.fd function
local function getfd(fd)
  if type(fd) == "number" or ffi.istype(t.int, fd) then return fd end
  return fd:getfd()
end

metatype("error", "struct {int errno;}", {
  __tostring = function(e) return strerror(e.errno) end,
  __index = function(t, k)
    if k == 'sym' then return errsyms[t.errno] end
    if k == 'lsym' then return errsyms[t.errno]:sub(2):lower() end
    if c.E[k] then return c.E[k] == t.errno end
    local uk = c.E['E' .. k:upper()]
    if uk then return uk == t.errno end
  end,
  __new = function(tp, errno)
    if not errno then errno = ffi.errno() end
    return ffi.new(tp, errno)
  end
})

-- cast socket address to actual type based on family
local samap, samap2 = {}, {}

meth.sockaddr = {
  index = {
    family = function(sa) return sa.sa_family end,
  }
}

metatype("sockaddr", "struct sockaddr", {
  __index = function(sa, k) if meth.sockaddr.index[k] then return meth.sockaddr.index[k](sa) end end,
})

meth.sockaddr_storage = {
  index = {
    family = function(sa) return sa.ss_family end,
  },
  newindex = {
    family = function(sa, v) sa.ss_family = c.AF[v] end,
  }
}

-- experiment, see if we can use this as generic type, to avoid allocations.
metatype("sockaddr_storage", "struct sockaddr_storage", {
  __index = function(sa, k)
    if meth.sockaddr_storage.index[k] then return meth.sockaddr_storage.index[k](sa) end
    local st = samap2[sa.ss_family]
    if st then
      local cs = st(sa)
      return cs[k]
    end
  end,
  __newindex = function(sa, k, v)
    if meth.sockaddr_storage.newindex[k] then
      meth.sockaddr_storage.newindex[k](sa, v)
      return
    end
    local st = samap2[sa.ss_family]
    if st then
      local cs = st(sa)
      cs[k] = v
    end
  end,
  __new = function(tp, init)
    local ss = ffi.new(tp)
    local family
    if init and init.family then family = c.AF[init.family] end
    local st
    if family then
      st = samap2[family]
      ss.ss_family = family
      init.family = nil
    end
    if st then
      local cs = st(ss)
      for k, v in pairs(init) do
        cs[k] = v
      end
    end
    return ss
  end,
})

meth.sockaddr_in = {
  index = {
    family = function(sa) return sa.sin_family end,
    port = function(sa) return ntohs(sa.sin_port) end,
    addr = function(sa) return sa.sin_addr end,
  },
  newindex = {
    port = function(sa, v) sa.sin_port = htons(v) end
  }
}

metatype("sockaddr_in", "struct sockaddr_in", {
  __index = function(sa, k) if meth.sockaddr_in.index[k] then return meth.sockaddr_in.index[k](sa) end end,
  __newindex = function(sa, k, v) if meth.sockaddr_in.newindex[k] then meth.sockaddr_in.newindex[k](sa, v) end end,
  __new = function(tp, port, addr) -- TODO allow table init
    if not ffi.istype(t.in_addr, addr) then
      addr = t.in_addr(addr)
      if not addr then return end
    end
    return ffi.new(tp, c.AF.INET, htons(port or 0), addr)
  end
})

meth.sockaddr_in6 = {
  index = {
    family = function(sa) return sa.sin6_family end,
    port = function(sa) return ntohs(sa.sin6_port) end,
    addr = function(sa) return sa.sin6_addr end,
  },
  newindex = {
    port = function(sa, v) sa.sin6_port = htons(v) end
  }
}

metatype("sockaddr_in6", "struct sockaddr_in6", {
  __index = function(sa, k) if meth.sockaddr_in6.index[k] then return meth.sockaddr_in6.index[k](sa) end end,
  __newindex = function(sa, k, v) if meth.sockaddr_in6.newindex[k] then meth.sockaddr_in6.newindex[k](sa, v) end end,
  __new = function(tp, port, addr, flowinfo, scope_id) -- reordered initialisers. TODO allow table init
    if not ffi.istype(t.in6_addr, addr) then
      addr = t.in6_addr(addr)
      if not addr then return end
    end
    return ffi.new(tp, c.AF.INET6, htons(port or 0), flowinfo or 0, addr, scope_id or 0)
  end
})

meth.sockaddr_un = {
  index = {
    family = function(sa) return sa.un_family end,
  },
}

metatype("sockaddr_un", "struct sockaddr_un", {
  __index = function(sa, k) if meth.sockaddr_un.index[k] then return meth.sockaddr_un.index[k](sa) end end,
  __new = function(tp) return ffi.new(tp, c.AF.UNIX) end,
})

local nlgroupmap = { -- map from netlink socket type to group names. Note there are two forms of name though, bits and shifts.
  [c.NETLINK.ROUTE] = c.RTMGRP, -- or RTNLGRP_ and shift not mask TODO make shiftflags function
  -- add rest of these
--  [c.NETLINK.SELINUX] = c.SELNLGRP,
}

meth.sockaddr_nl = {
  index = {
    family = function(sa) return sa.nl_family end,
    pid = function(sa) return sa.nl_pid end,
    groups = function(sa) return sa.nl_groups end,
  },
  newindex = {
    pid = function(sa, v) sa.nl_pid = v end,
    groups = function(sa, v) sa.nl_groups = v end,
  }
}

metatype("sockaddr_nl", "struct sockaddr_nl", {
  __index = function(sa, k) if meth.sockaddr_nl.index[k] then return meth.sockaddr_nl.index[k](sa) end end,
  __newindex = function(sa, k, v) if meth.sockaddr_nl.newindex[k] then meth.sockaddr_nl.newindex[k](sa, v) end end,
  __new = function(tp, pid, groups, nltype)
    if type(pid) == "table" then
      local tb = pid
      pid, groups, nltype = tb.nl_pid or tb.pid, tb.nl_groups or tb.groups, tb.type
    end
    if nltype and nlgroupmap[nltype] then groups = nlgroupmap[nltype][groups] end -- see note about shiftflags
    return ffi.new(tp, {nl_family = c.AF.NETLINK, nl_pid = pid, nl_groups = groups})
  end,
})

samap = {
  [c.AF.UNIX] = t.sockaddr_un,
  [c.AF.INET] = t.sockaddr_in,
  [c.AF.INET6] = t.sockaddr_in6,
  [c.AF.NETLINK] = t.sockaddr_nl,
}

-- 64 to 32 bit conversions via unions TODO use meth not object?

if ffi.abi("le") then
mt.i6432 = {
  __index = {
    to32 = function(u) return u.i32[1], u.i32[0] end,
  }
}
else
mt.i6432 = {
  __index = {
    to32 = function(u) return u.i32[0], u.i32[1] end,
  }
}
end

t.i6432 = ffi.metatype("union {int64_t i64; int32_t i32[2];}", mt.i6432)
t.u6432 = ffi.metatype("union {uint64_t i64; uint32_t i32[2];}", mt.i6432)

-- Lua metatables where we cannot return an ffi type eg value is an array or integer or otherwise problematic

-- TODO should we change to meth
mt.device = {
  __index = {
    major = function(dev)
      local h, l = t.i6432(dev.dev):to32()
      return bit.bor(bit.band(bit.rshift(l, 8), 0xfff), bit.band(h, bit.bnot(0xfff)));
    end,
    minor = function(dev)
      local h, l = t.i6432(dev.dev):to32()
      return bit.bor(bit.band(l, 0xff), bit.band(bit.rshift(l, 12), bit.bnot(0xff)));
    end,
    device = function(dev) return tonumber(dev.dev) end,
  },
}

t.device = function(major, minor)
    local dev = major
    if minor then dev = bit.bor(bit.band(minor, 0xff), bit.lshift(bit.band(major, 0xfff), 8), bit.lshift(bit.band(minor, bit.bnot(0xff)), 12)) + 0x100000000 * bit.band(major, bit.bnot(0xfff)) end
    return setmetatable({dev = t.dev(dev)}, mt.device)
  end

meth.stat = {
  index = {
    dev = function(st) return t.device(st.st_dev) end,
    ino = function(st) return tonumber(st.st_ino) end,
    mode = function(st) return st.st_mode end,
    nlink = function(st) return st.st_nlink end,
    uid = function(st) return st.st_uid end,
    gid = function(st) return st.st_gid end,
    rdev = function(st) return tonumber(st.st_rdev) end,
    size = function(st) return tonumber(st.st_size) end,
    blksize = function(st) return tonumber(st.st_blksize) end,
    blocks = function(st) return tonumber(st.st_blocks) end,
    atime = function(st) return tonumber(st.st_atime) end,
    ctime = function(st) return tonumber(st.st_ctime) end,
    mtime = function(st) return tonumber(st.st_mtime) end,
    rdev = function(st) return t.device(st.st_rdev) end,
    isreg = function(st) return bit.band(st.st_mode, c.S.IFMT) == c.S.IFREG end,
    isdir = function(st) return bit.band(st.st_mode, c.S.IFMT) == c.S.IFDIR end,
    ischr = function(st) return bit.band(st.st_mode, c.S.IFMT) == c.S.IFCHR end,
    isblk = function(st) return bit.band(st.st_mode, c.S.IFMT) == c.S.IFBLK end,
    isfifo = function(st) return bit.band(st.st_mode, c.S.IFMT) == c.S.IFIFO end,
    islnk = function(st) return bit.band(st.st_mode, c.S.IFMT) == c.S.IFLNK end,
    issock = function(st) return bit.band(st.st_mode, c.S.IFMT) == c.S.IFSOCK end,
  }
}

metatype("stat", stattypename, { -- either struct stat on 64 bit or struct stat64 on 32 bit
  __index = function(st, k) if meth.stat.index[k] then return meth.stat.index[k](st) end end,
})

meth.siginfo = {
  index = {
    si_pid     = function(s) return s.sifields.kill.si_pid end,
    si_uid     = function(s) return s.sifields.kill.si_uid end,
    si_timerid = function(s) return s.sifields.timer.si_tid end,
    si_overrun = function(s) return s.sifields.timer.si_overrun end,
    si_status  = function(s) return s.sifields.sigchld.si_status end,
    si_utime   = function(s) return s.sifields.sigchld.si_utime end,
    si_stime   = function(s) return s.sifields.sigchld.si_stime end,
    si_value   = function(s) return s.sifields.rt.si_sigval end,
    si_int     = function(s) return s.sifields.rt.si_sigval.sival_int end,
    si_ptr     = function(s) return s.sifields.rt.si_sigval.sival_ptr end,
    si_addr    = function(s) return s.sifields.sigfault.si_addr end,
    si_band    = function(s) return s.sifields.sigpoll.si_band end,
    si_fd      = function(s) return s.sifields.sigpoll.si_fd end,
  },
  newindex = {
    si_pid     = function(s, v) s.sifields.kill.si_pid = v end,
    si_uid     = function(s, v) s.sifields.kill.si_uid = v end,
    si_timerid = function(s, v) s.sifields.timer.si_tid = v end,
    si_overrun = function(s, v) s.sifields.timer.si_overrun = v end,
    si_status  = function(s, v) s.sifields.sigchld.si_status = v end,
    si_utime   = function(s, v) s.sifields.sigchld.si_utime = v end,
    si_stime   = function(s, v) s.sifields.sigchld.si_stime = v end,
    si_value   = function(s, v) s.sifields.rt.si_sigval = v end,
    si_int     = function(s, v) s.sifields.rt.si_sigval.sival_int = v end,
    si_ptr     = function(s, v) s.sifields.rt.si_sigval.sival_ptr = v end,
    si_addr    = function(s, v) s.sifields.sigfault.si_addr = v end,
    si_band    = function(s, v) s.sifields.sigpoll.si_band = v end,
    si_fd      = function(s, v) s.sifields.sigpoll.si_fd = v end,
  }
}

metatype("siginfo", "struct siginfo", {
  __index = function(t, k) if meth.siginfo.index[k] then return meth.siginfo.index[k](t) end end,
  __newindex = function(t, k, v) if meth.siginfo.newindex[k] then meth.siginfo.newindex[k](t, v) end end,
})

metatype("macaddr", "struct {uint8_t mac_addr[6];}", {
  __tostring = function(m)
    local hex = {}
    for i = 1, 6 do
      hex[i] = string.format("%02x", m.mac_addr[i - 1])
    end
    return table.concat(hex, ":")
  end,
  __new = function(tp, str)
    local mac = ffi.new(tp)
    if str then
      for i = 1, 6 do
        local n = tonumber(str:sub(i * 3 - 2, i * 3 - 1), 16) -- TODO more checks on syntax
        mac.mac_addr[i - 1] = n
      end
    end
    return mac
  end,
})

meth.timeval = {
  index = {
    time = function(tv) return tonumber(tv.tv_sec) + tonumber(tv.tv_usec) / 1000000 end,
    sec = function(tv) return tonumber(tv.tv_sec) end,
    usec = function(tv) return tonumber(tv.tv_usec) end,
  },
  newindex = {
    time = function(tv, v)
      local i, f = math.modf(v)
      tv.tv_sec, tv.tv_usec = i, math.floor(f * 1000000)
    end,
    sec = function(tv, v) tv.tv_sec = v end,
    usec = function(tv, v) tv.tv_usec = v end,
  }
}

meth.rlimit = {
  index = {
    cur = function(r) return tonumber(r.rlim_cur) end,
    max = function(r) return tonumber(r.rlim_max) end,
  }
}

metatype("rlimit", "struct rlimit64", {
  __index = function(r, k) if meth.rlimit.index[k] then return meth.rlimit.index[k](r) end end,
})

metatype("timeval", "struct timeval", {
  __index = function(tv, k) if meth.timeval.index[k] then return meth.timeval.index[k](tv) end end,
  __newindex = function(tv, k, v) if meth.timeval.newindex[k] then meth.timeval.newindex[k](tv, v) end end,
  __new = function(tp, v)
    if not v then v = {0, 0} end
    if type(v) ~= "number" then return ffi.new(tp, v) end
    local ts = ffi.new(tp)
    ts.time = v
    return ts
  end
})

meth.timespec = {
  index = {
    time = function(tv) return tonumber(tv.tv_sec) + tonumber(tv.tv_nsec) / 1000000000 end,
    sec = function(tv) return tonumber(tv.tv_sec) end,
    nsec = function(tv) return tonumber(tv.tv_nsec) end,
  },
  newindex = {
    time = function(tv, v)
      local i, f = math.modf(v)
      tv.tv_sec, tv.tv_nsec = i, math.floor(f * 1000000000)
    end,
    sec = function(tv, v) tv.tv_sec = v end,
    nsec = function(tv, v) tv.tv_nsec = v end,
  }
}

metatype("timespec", "struct timespec", {
  __index = function(tv, k) if meth.timespec.index[k] then return meth.timespec.index[k](tv) end end,
  __newindex = function(tv, k, v) if meth.timespec.newindex[k] then meth.timespec.newindex[k](tv, v) end end,
  __new = function(tp, v)
    if not v then v = {0, 0} end
    if type(v) ~= "number" then return ffi.new(tp, v) end
    local ts = ffi.new(tp)
    ts.time = v
    return ts
  end
})

local function itnormal(v)
  if not v then v = {{0, 0}, {0, 0}} end
  if v.interval then
    v.it_interval = v.interval
    v.interval = nil
  end
  if v.value then
    v.it_value = v.value
    v.value = nil
  end
  if not v.it_interval then
    v.it_interval = v[1]
    v[1] = nil
  end
  if not v.it_value then
    v.it_value = v[2]
    v[2] = nil
  end
  return v
end

meth.itimerspec = {
  index = {
    interval = function(it) return it.it_interval end,
    value = function(it) return it.it_value end,
  }
}

metatype("itimerspec", "struct itimerspec", {
  __index = function(it, k) if meth.itimerspec.index[k] then return meth.itimerspec.index[k](it) end end,
  __new = function(tp, v)
    v = itnormal(v)
    v.it_interval = istype(t.timespec, v.it_interval) or t.timespec(v.it_interval)
    v.it_value = istype(t.timespec, v.it_value) or t.timespec(v.it_value)
    return ffi.new(tp, v)
  end
})

metatype("itimerval", "struct itimerval", {
  __index = function(it, k) if meth.itimerspec.index[k] then return meth.itimerspec.index[k](it) end end, -- can use same meth
  __new = function(tp, v)
    v = itnormal(v)
    v.it_interval = istype(t.timeval, v.it_interval) or t.timeval(v.it_interval)
    v.it_value = istype(t.timeval, v.it_value) or t.timeval(v.it_value)
    return ffi.new(tp, v)
  end
})

mt.iovecs = {
  __index = function(io, k)
    return io.iov[k - 1]
  end,
  __newindex = function(io, k, v)
    v = istype(t.iovec, v) or t.iovec(v)
    ffi.copy(io.iov[k - 1], v, s.iovec)
  end,
  __len = function(io) return io.count end,
  __new = function(tp, is)
    if type(is) == 'number' then return ffi.new(tp, is, is) end
    local count = #is
    local iov = ffi.new(tp, count, count)
    for n = 1, count do
      local i = is[n]
      if type(i) == 'string' then
        local buf = t.buffer(#i)
        ffi.copy(buf, i, #i)
        iov[n].iov_base = buf
        iov[n].iov_len = #i
      elseif type(i) == 'number' then
        iov[n].iov_base = t.buffer(i)
        iov[n].iov_len = i
      elseif ffi.istype(t.iovec, i) then
        ffi.copy(iov[n], i, s.iovec)
      elseif type(i) == 'cdata' then -- eg buffer or other structure
        iov[n].iov_base = i
        iov[n].iov_len = ffi.sizeof(i)
      else -- eg table
        iov[n] = i
      end
    end
    return iov
  end
}

t.iovecs = ffi.metatype("struct { int count; struct iovec iov[?];}", mt.iovecs) -- do not use metatype helper as variable size

metatype("pollfd", "struct pollfd", {
  __index = function(t, k)
    if k == 'getfd' then return t.fd end -- TODO use meth
    return bit.band(t.revents, c.POLL[k]) ~= 0
  end
})

mt.pollfds = {
  __index = function(p, k)
    return p.pfd[k - 1]
  end,
  __newindex = function(p, k, v)
    v = istype(t.pollfd, v) or t.pollfd(v)
    ffi.copy(p.pfd[k - 1], v, s.pollfd)
  end,
  __len = function(p) return p.count end,
  __new = function(tp, ps)
    if type(ps) == 'number' then return ffi.new(tp, ps, ps) end
    local count = #ps
    local fds = ffi.new(tp, count, count)
    for n = 1, count do
      fds[n].fd = ps[n].fd:getfd()
      fds[n].events = c.POLL[ps[n].events]
      fds[n].revents = 0
    end
    return fds
  end,
}

t.pollfds = ffi.metatype("struct {int count; struct pollfd pfd[?];}", mt.pollfds)

meth.signalfd = {
  index = {
    signo = function(ss) return tonumber(ss.ssi_signo) end,
    code = function(ss) return tonumber(ss.ssi_code) end,
    pid = function(ss) return tonumber(ss.ssi_pid) end,
    uid = function(ss) return tonumber(ss.ssi_uid) end,
    fd = function(ss) return tonumber(ss.ssi_fd) end,
    tid = function(ss) return tonumber(ss.ssi_tid) end,
    band = function(ss) return tonumber(ss.ssi_band) end,
    overrun = function(ss) return tonumber(ss.ssi_overrun) end,
    trapno = function(ss) return tonumber(ss.ssi_trapno) end,
    status = function(ss) return tonumber(ss.ssi_status) end,
    int = function(ss) return tonumber(ss.ssi_int) end,
    ptr = function(ss) return ss.ss_ptr end,
    utime = function(ss) return tonumber(ss.ssi_utime) end,
    stime = function(ss) return tonumber(ss.ssi_stime) end,
    addr = function(ss) return ss.ss_addr end,
  },
}

metatype("signalfd_siginfo", "struct signalfd_siginfo", {
  __index = function(ss, k)
    if ss.ssi_signo == c.SIG(k) then return true end
    local rname = signal_reasons_gen[ss.ssi_code]
    if not rname and signal_reasons[ss.ssi_signo] then rname = signal_reasons[ss.ssi_signo][ss.ssi_code] end
    if rname == k then return true end
    if rname == k:upper() then return true end -- TODO use some metatable to hide this?
    if meth.signalfd.index[k] then return meth.signalfd.index[k](ss) end
  end,
})

mt.siginfos = {
  __index = function(ss, k)
    return ss.sfd[k - 1]
  end,
  __len = function(p) return p.count end,
  __new = function(tp, ss)
    return ffi.new(tp, ss, ss, ss * s.signalfd_siginfo)
  end,
}

t.siginfos = ffi.metatype("struct {int count, bytes; struct signalfd_siginfo sfd[?];}", mt.siginfos)

local INET6_ADDRSTRLEN = 46

local function inet_ntop(af, src)
  af = c.AF[af] -- TODO do not need, in fact could split into two functions if no need to export.
  if af == c.AF.INET then
    local b = pt.uchar(src)
    return tonumber(b[0]) .. "." .. tonumber(b[1]) .. "." .. tonumber(b[2]) .. "." .. tonumber(b[3])
  end
  local len = INET6_ADDRSTRLEN
  local dst = t.buffer(len)
  local ret = C.inet_ntop(af, src, dst, len) -- TODO replace with pure Lua
  if ret == nil then return nil, t.error() end
  return ffi.string(dst)
end

local function inet_pton(af, src, addr)
  af = c.AF[af]
  if not addr then addr = t.addrtype[af]() end
  local ret = C.inet_pton(af, src, addr) -- TODO redo in pure Lua
  if ret == -1 then return nil, t.error() end
  if ret == 0 then return nil end -- maybe return string
  return addr
end

-- TODO add generic address type that works out which to take? basically inet_name, except without netmask

metatype("in_addr", "struct in_addr", {
  __tostring = function(a) return inet_ntop(c.AF.INET, a) end,
  __new = function(tp, s)
    local addr = ffi.new(tp)
    if s then addr = inet_pton(c.AF.INET, s, addr) end
    return addr
  end
})

metatype("in6_addr", "struct in6_addr", {
  __tostring = function(a) return inet_ntop(c.AF.INET6, a) end,
  __new = function(tp, s)
    local addr = ffi.new(tp)
    if s then addr = inet_pton(c.AF.INET6, s, addr) end
    return addr
  end
})

t.addrtype = {
  [c.AF.INET] = t.in_addr,
  [c.AF.INET6] = t.in6_addr,
}

-- signal set handlers TODO replace with metatypes, reuse code from stringflags

local function sigismember(set, sig)
  local d = bit.rshift(sig - 1, 5) -- always 32 bits
  return bit.band(set.val[d], bit.lshift(1, (sig - 1) % 32)) ~= 0
end

local function sigemptyset(set)
  for i = 0, s.sigset / 4 - 1 do
    if set.val[i] ~= 0 then return false end
  end
  return true
end

local function sigaddset(set, sig)
  set = t.sigset(set)
  local d = bit.rshift(sig - 1, 5)
  set.val[d] = bit.bor(set.val[d], bit.lshift(1, (sig - 1) % 32))
  return set
end

local function sigdelset(set, sig)
  set = t.sigset(set)
  local d = bit.rshift(sig - 1, 5)
  set.val[d] = bit.band(set.val[d], bit.bnot(bit.lshift(1, (sig - 1) % 32)))
  return set
end

-- TODO remove duplication of split and trim as this should all be in constants, metatypes
local function split(delimiter, text)
  if delimiter == "" then return {text} end
  if #text == 0 then return {} end
  local list = {}
  local pos = 1
  while true do
    local first, last = text:find(delimiter, pos)
    if first then
      list[#list + 1] = text:sub(pos, first - 1)
      pos = last + 1
    else
      list[#list + 1] = text:sub(pos)
      break
    end
  end
  return list
end

local function trim(s) -- TODO should replace underscore with space
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function sigaddsets(set, sigs) -- allow multiple
  if type(sigs) ~= "string" then return sigaddset(set, sigs) end
  set = t.sigset(set)
  local a = split(",", sigs)
  for i, v in ipairs(a) do
    local s = trim(v)
    local sig = c.SIG[s]
    if not sig then error("invalid signal: " .. v) end -- don't use this format if you don't want exceptions, better than silent ignore
    sigaddset(set, sig)
  end
  return set
end

local function sigdelsets(set, sigs) -- allow multiple
  if type(sigs) ~= "string" then return sigdelset(set, sigs) end
  set = t.sigset(set)
  local a = split(",", sigs)
  for i, v in ipairs(a) do
    local s = trim(v)
    local sig = c.SIG[s]
    if not sig then error("invalid signal: " .. v) end -- don't use this format if you don't want exceptions, better than silent ignore
    sigdelset(set, sig)
  end
  return set
end

metatype("sigset", "sigset_t", {
  __index = function(set, k)
    if k == 'add' then return sigaddsets end
    if k == 'del' then return sigdelsets end
    if k == 'isemptyset' then return sigemptyset(set) end
    local sig = c.SIG[k]
    if sig then return sigismember(set, sig) end
  end,
  __new = function(tp, str)
    if ffi.istype(tp, str) then return str end
    if not str then return ffi.new(tp) end
    local f = ffi.new(tp)
    local a = split(",", str)
    for i, v in ipairs(a) do
      local st = trim(v)
      local sig = c.SIG[st]
      if not sig then error("invalid signal: " .. v) end -- don't use this format if you don't want exceptions, better than silent ignore
      local d = bit.rshift(sig - 1, 5) -- always 32 bits
      f.val[d] = bit.bor(f.val[d], bit.lshift(1, (sig - 1) % 32))
    end
    return f
  end,
})

local voidp = ffi.typeof("void *")

pt.void = function(x)
  return ffi.cast(voidp, x)
end

samap2 = {
  [c.AF.UNIX] = pt.sockaddr_un,
  [c.AF.INET] = pt.sockaddr_in,
  [c.AF.INET6] = pt.sockaddr_in6,
  [c.AF.NETLINK] = pt.sockaddr_nl,
}

return types


