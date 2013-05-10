-- Linux kernel types

return function(types, hh)

local t, pt, s, ctypes = types.t, types.pt, types.s, types.ctypes

local ptt, addtype, lenfn, lenmt, newfn, istype = hh.ptt, hh.addtype, hh.lenfn, hh.lenmt, hh.newfn, hh.istype

local ffi = require "ffi"
local bit = require "bit"

require "syscall.ffitypes"

local h = require "syscall.helpers"

local ntohl, ntohl, ntohs, htons = h.ntohl, h.ntohl, h.ntohs, h.htons

local c = require "syscall.constants"

local abi = require "syscall.abi"

local C = ffi.C -- for inet_pton, TODO due to be replaced with Lua
ffi.cdef[[
int inet_pton(int af, const char *src, void *dst);
]]

local mt = {} -- metatables
local meth = {}

-- use 64 bit stat type always
local stattypename = "struct stat"
if abi.abi32 then
  stattypename = "struct stat64"
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

local addtypes = {
  fdset = "fd_set",
  clockid = "clockid_t",
  sighandler = "sighandler_t",
  aio_context = "aio_context_t",
}

-- as an experiment, see https://github.com/justincormack/ljsyscall/issues/28 trying adding a __len method
-- however initially only for the ones with no extra metatype.
local addstructs = {
  msghdr = "struct msghdr",
  cmsghdr = "struct cmsghdr",
  ucred = "struct ucred",
  sysinfo = "struct sysinfo",
  nlmsghdr = "struct nlmsghdr",
  rtgenmsg = "struct rtgenmsg",
  rtmsg = "struct rtmsg",
  ifinfomsg = "struct ifinfomsg",
  ifaddrmsg = "struct ifaddrmsg",
  rtattr = "struct rtattr",
  rta_cacheinfo = "struct rta_cacheinfo",
  nlmsgerr = "struct nlmsgerr",
  utsname = "struct utsname",
  fdb_entry = "struct fdb_entry",
  io_event = "struct io_event",
  seccomp_data = "struct seccomp_data",
  iovec = "struct iovec",
  rtnl_link_stats = "struct rtnl_link_stats",
  statfs = "struct statfs64",
  dirent = "struct linux_dirent64",
  ifa_cacheinfo = "struct ifa_cacheinfo",
  flock = "struct flock64",
  input_event = "struct input_event",
  input_id = "struct input_id",
  input_absinfo = "struct input_absinfo",
  input_keymap_entry = "struct input_keymap_entry",
  ff_replay = "struct ff_replay",
  ff_trigger = "struct ff_trigger",
  ff_envelope = "struct ff_envelope",
  ff_constant_effect = "struct ff_constant_effect",
  ff_ramp_effect = "struct ff_ramp_effect",
  ff_condition_effect = "struct ff_condition_effect",
  ff_periodic_effect = "struct ff_periodic_effect",
  ff_rumble_effect = "struct ff_rumble_effect",
  ff_effect = "struct ff_effect",
  winsize = "struct winsize",
  termio = "struct termio",
  sock_fprog = "struct sock_fprog",
  user_cap_header = "struct user_cap_header",
  user_cap_data = "struct user_cap_data",
  xt_get_revision = "struct xt_get_revision",
  vfs_cap_data = "struct vfs_cap_data",
  sched_param = "struct sched_param",
  ucontext = "ucontext_t",
  mcontext = "mcontext_t",
  tun_pi = "struct tun_pi",
  tun_filter = "struct tun_filter",
}

for k, v in pairs(addtypes) do addtype(k, v) end
for k, v in pairs(addstructs) do addtype(k, v, lenmt) end

-- these ones not in table as not helpful with vararg or arrays
t.inotify_event = ffi.typeof("struct inotify_event")
pt.inotify_event = ptt("struct inotify_event") -- still need pointer to this

t.epoll_events = ffi.typeof("struct epoll_event[?]") -- TODO add metatable, like pollfds
t.io_events = ffi.typeof("struct io_event[?]")
t.iocbs = ffi.typeof("struct iocb[?]")
t.sock_filters = ffi.typeof("struct sock_filter[?]")

t.iocb_ptrs = ffi.typeof("struct iocb *[?]")
t.string_array = ffi.typeof("const char *[?]")

t.ints = ffi.typeof("int[?]")
t.buffer = ffi.typeof("char[?]") -- TODO rename as chars?

t.int1 = ffi.typeof("int[1]")
t.uint1 = ffi.typeof("unsigned int[1]")
t.int16_1 = ffi.typeof("int16_t[1]")
t.uint16_1 = ffi.typeof("uint16_t[1]")
t.int32_1 = ffi.typeof("int32_t[1]")
t.uint32_1 = ffi.typeof("uint32_t[1]")
t.int64_1 = ffi.typeof("int64_t[1]")
t.uint64_1 = ffi.typeof("uint64_t[1]")
t.socklen1 = ffi.typeof("socklen_t[1]")
t.off1 = ffi.typeof("off_t[1]")
t.loff1 = ffi.typeof("loff_t[1]")
t.uid1 = ffi.typeof("uid_t[1]")
t.gid1 = ffi.typeof("gid_t[1]")
t.aio_context1 = ffi.typeof("aio_context_t[1]")
t.sock_fprog1 = ffi.typeof("struct sock_fprog[1]")

t.char2 = ffi.typeof("char[2]")
t.int2 = ffi.typeof("int[2]")
t.uint2 = ffi.typeof("unsigned int[2]")
t.user_cap_data2 = ffi.typeof("struct user_cap_data[2]")

-- still need sizes for these, for ioctls
s.uint2 = ffi.sizeof(t.uint2)

-- types with metatypes

-- fd type. This will be overridden by syscall as it adds methods
-- so this is the minimal one necessary to provide the interface eg does not gc file
-- TODO add tests once types is standalone

-- even simpler version, just pass numbers
t.fd = function(fd) return tonumber(fd) end
t.mqd = t.fd -- basically an fd, but will have different metamethods

-- can replace with a different t.fd function
local function getfd(fd)
  if type(fd) == "number" or ffi.istype(t.int, fd) then return fd end
  return fd:getfd()
end

local errsyms = {} -- reverse lookup
for k, v in pairs(c.E) do
  errsyms[v] = k
end

t.error = ffi.metatype("struct {int errno;}", {
  __tostring = function(e) return require("syscall.errors")[e.errno] end,
  __index = function(t, k)
    if k == 'sym' then return errsyms[t.errno] end
    if k == 'lsym' then return errsyms[t.errno]:lower() end
    if c.E[k] then return c.E[k] == t.errno end
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

addtype("sockaddr", "struct sockaddr", {
  __index = function(sa, k) if meth.sockaddr.index[k] then return meth.sockaddr.index[k](sa) end end,
  __len = lenfn,
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
addtype("sockaddr_storage", "struct sockaddr_storage", {
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
  __len = lenfn,
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

addtype("sockaddr_in", "struct sockaddr_in", {
  __index = function(sa, k) if meth.sockaddr_in.index[k] then return meth.sockaddr_in.index[k](sa) end end,
  __newindex = function(sa, k, v) if meth.sockaddr_in.newindex[k] then meth.sockaddr_in.newindex[k](sa, v) end end,
  __new = function(tp, port, addr) -- TODO allow table init
    if not ffi.istype(t.in_addr, addr) then
      addr = t.in_addr(addr)
      if not addr then return end
    end
    return ffi.new(tp, c.AF.INET, htons(port or 0), addr)
  end,
  __len = lenfn,
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

addtype("sockaddr_in6", "struct sockaddr_in6", {
  __index = function(sa, k) if meth.sockaddr_in6.index[k] then return meth.sockaddr_in6.index[k](sa) end end,
  __newindex = function(sa, k, v) if meth.sockaddr_in6.newindex[k] then meth.sockaddr_in6.newindex[k](sa, v) end end,
  __new = function(tp, port, addr, flowinfo, scope_id) -- reordered initialisers. TODO allow table init
    if not ffi.istype(t.in6_addr, addr) then
      addr = t.in6_addr(addr)
      if not addr then return end
    end
    return ffi.new(tp, c.AF.INET6, htons(port or 0), flowinfo or 0, addr, scope_id or 0)
  end,
  __len = lenfn,
})

meth.sockaddr_un = {
  index = {
    family = function(sa) return sa.un_family end,
  },
}

addtype("sockaddr_un", "struct sockaddr_un", {
  __index = function(sa, k) if meth.sockaddr_un.index[k] then return meth.sockaddr_un.index[k](sa) end end,
  __new = function(tp) return ffi.new(tp, c.AF.UNIX) end,
  __len = lenfn,
})

-- this is a bit odd, but we actually use Lua metatables for sockaddr_un, and use t.sa to multiplex
-- basically a unix socket structure is not possible to interpret without size
mt.sockaddr_un = {
  __index = function(un, k)
    local sa = un.addr
    if k == 'family' then return tonumber(sa.sun_family) end
    local namelen = un.addrlen - s.sun_family
    if namelen > 0 then
      if sa.sun_path[0] == 0 then
        if k == 'abstract' then return true end
        if k == 'name' then return ffi.string(rets.addr.sun_path, namelen) end -- should we also remove leading \0?
      else
        if k == 'name' then return ffi.string(rets.addr.sun_path) end
      end
    else
      if k == 'unnamed' then return true end
    end
  end,
}

function t.sa(addr, addrlen)
  local family = addr.family
  if family == c.AF.UNIX then -- we return Lua metatable not metatype, as need length to decode
    local sa = t.sockaddr_un()
    ffi.copy(sa, addr, addrlen)
    return setmetatable({addr = sa, addrlen = addrlen}, mt.sockaddr_un)
  end
  return addr
end

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

addtype("sockaddr_nl", "struct sockaddr_nl", {
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
  __len = lenfn,
})

meth.sockaddr_ll = {
  index = {
    family = function(sa) return sa.sll_family end,
    protocol = function(sa) return ntohs(sa.sll_protocol) end,
    ifindex = function(sa) return sa.sll_ifindex end,
    hatype = function(sa) return sa.sll_hatype end,
    pkttype = function(sa) return sa.sll_pkttype end,
    halen = function(sa) return sa.sll_halen end,
    addr = function(sa)
      if sa.sll_halen == 6 then return pt.macaddr(sa.sll_addr) else return ffi.string(sa.sll_addr, sa.sll_halen) end
    end,
  },
  newindex = {
    protocol = function(sa, v) sa.sll_protocol = htons(c.ETH_P[v]) end,
    ifindex = function(sa, v) sa.sll_ifindex = v end,
    hatype = function(sa, v) sa.sll_hatype = v end,
    pkttype = function(sa, v) sa.sll_pkttype = v end,
    halen = function(sa, v) sa.sll_halen = v end,
    addr = function(sa, v)
      if ffi.istype(t.macaddr, v) then
        sa.sll_halen = 6
        ffi.copy(sa.sll_addr, v, 6)
      else sa.sll_addr = v end
    end,
  }
}

addtype("sockaddr_ll", "struct sockaddr_ll", {
  __index = function(sa, k) if meth.sockaddr_ll.index[k] then return meth.sockaddr_ll.index[k](sa) end end,
  __newindex = function(sa, k, v) if meth.sockaddr_ll.newindex[k] then meth.sockaddr_ll.newindex[k](sa, v) end end,
  __new = function(tp, tb)
    local sa = ffi.new(tp, {sll_family = c.AF.PACKET})
    for k, v in pairs(tb or {}) do sa[k] = v end
    return sa
  end,
  __len = lenfn,
})

-- 64 to 32 bit conversions via unions TODO use meth not object?
if abi.le then
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
    isreg = function(st) return bit.band(st.st_mode, c.S_I.FMT) == c.S_I.FREG end,
    isdir = function(st) return bit.band(st.st_mode, c.S_I.FMT) == c.S_I.FDIR end,
    ischr = function(st) return bit.band(st.st_mode, c.S_I.FMT) == c.S_I.FCHR end,
    isblk = function(st) return bit.band(st.st_mode, c.S_I.FMT) == c.S_I.FBLK end,
    isfifo = function(st) return bit.band(st.st_mode, c.S_I.FMT) == c.S_I.FIFO end,
    islnk = function(st) return bit.band(st.st_mode, c.S_I.FMT) == c.S_I.FLNK end,
    issock = function(st) return bit.band(st.st_mode, c.S_I.FMT) == c.S_I.FSOCK end,
  }
}

addtype("stat", stattypename, { -- either struct stat on 64 bit or struct stat64 on 32 bit
  __index = function(st, k) if meth.stat.index[k] then return meth.stat.index[k](st) end end,
})

meth.siginfo = {
  index = {
    signo   = function(s) return s.si_signo end,
    errno   = function(s) return s.si_errno end,
    code    = function(s) return s.si_code end,
    pid     = function(s) return s.sifields.kill.si_pid end,
    uid     = function(s) return s.sifields.kill.si_uid end,
    timerid = function(s) return s.sifields.timer.si_tid end,
    overrun = function(s) return s.sifields.timer.si_overrun end,
    status  = function(s) return s.sifields.sigchld.si_status end,
    utime   = function(s) return s.sifields.sigchld.si_utime end,
    stime   = function(s) return s.sifields.sigchld.si_stime end,
    value   = function(s) return s.sifields.rt.si_sigval end,
    int     = function(s) return s.sifields.rt.si_sigval.sival_int end,
    ptr     = function(s) return s.sifields.rt.si_sigval.sival_ptr end,
    addr    = function(s) return s.sifields.sigfault.si_addr end,
    band    = function(s) return s.sifields.sigpoll.si_band end,
    fd      = function(s) return s.sifields.sigpoll.si_fd end,
  },
  newindex = {
    signo   = function(s, v) s.si_signo = v end,
    errno   = function(s, v) s.si_errno = v end,
    code    = function(s, v) s.si_code = v end,
    pid     = function(s, v) s.sifields.kill.si_pid = v end,
    uid     = function(s, v) s.sifields.kill.si_uid = v end,
    timerid = function(s, v) s.sifields.timer.si_tid = v end,
    overrun = function(s, v) s.sifields.timer.si_overrun = v end,
    status  = function(s, v) s.sifields.sigchld.si_status = v end,
    utime   = function(s, v) s.sifields.sigchld.si_utime = v end,
    stime   = function(s, v) s.sifields.sigchld.si_stime = v end,
    value   = function(s, v) s.sifields.rt.si_sigval = v end,
    int     = function(s, v) s.sifields.rt.si_sigval.sival_int = v end,
    ptr     = function(s, v) s.sifields.rt.si_sigval.sival_ptr = v end,
    addr    = function(s, v) s.sifields.sigfault.si_addr = v end,
    band    = function(s, v) s.sifields.sigpoll.si_band = v end,
    fd      = function(s, v) s.sifields.sigpoll.si_fd = v end,
  }
}

addtype("siginfo", "struct siginfo", {
  __index = function(t, k) if meth.siginfo.index[k] then return meth.siginfo.index[k](t) end end,
  __newindex = function(t, k, v) if meth.siginfo.newindex[k] then meth.siginfo.newindex[k](t, v) end end,
})

addtype("macaddr", "struct {uint8_t mac_addr[6];}", {
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
  },
  newindex = {
    cur = function(r, v) r.rlim_cur = c.RLIM[v] end, -- allows use of "infinity"
    max = function(r, v) r.rlim_max = c.RLIM[v] end,
  },
}

addtype("rlimit", "struct rlimit64", {
  __index = function(r, k) if meth.rlimit.index[k] then return meth.rlimit.index[k](r) end end,
  __newindex = function(r, k, v) if meth.rlimit.newindex[k] then meth.rlimit.newindex[k](r, v) end end,
  __new = function(tp, tab)
    if tab then for k, v in pairs(tab) do tab[k] = c.RLIM[v] end end
    return newfn(tp, tab)
  end,
})

addtype("timeval", "struct timeval", {
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

addtype("timespec", "struct timespec", {
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

-- array so cannot just add metamethods
t.timespec2_raw = ffi.typeof("struct timespec[2]")
t.timespec2 = function(ts1, ts2)
  if ffi.istype(t.timespec2_raw, ts1) then return ts1 end
  if type(ts1) == "table" then ts1, ts2 = ts1[1], ts1[2] end
  local ts = t.timespec2_raw()
  if ts1 then if type(ts1) == 'string' then ts[0].tv_nsec = c.UTIME[ts1] else ts[0] = t.timespec(ts1) end end
  if ts2 then if type(ts2) == 'string' then ts[1].tv_nsec = c.UTIME[ts2] else ts[1] = t.timespec(ts2) end end
  return ts
end

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

addtype("itimerspec", "struct itimerspec", {
  __index = function(it, k) if meth.itimerspec.index[k] then return meth.itimerspec.index[k](it) end end,
  __new = function(tp, v)
    v = itnormal(v)
    v.it_interval = istype(t.timespec, v.it_interval) or t.timespec(v.it_interval)
    v.it_value = istype(t.timespec, v.it_value) or t.timespec(v.it_value)
    return ffi.new(tp, v)
  end
})

addtype("itimerval", "struct itimerval", {
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

addtype("pollfd", "struct pollfd", {
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

addtype("signalfd_siginfo", "struct signalfd_siginfo", {
  __index = function(ss, k)
    if ss.ssi_signo == c.SIG(k) then return true end
    local rname = signal_reasons_gen[ss.ssi_code]
    if not rname and signal_reasons[ss.ssi_signo] then rname = signal_reasons[ss.ssi_signo][ss.ssi_code] end
    if rname == k then return true end
    if rname == k:upper() then return true end -- TODO use some metatable to hide this?
    if meth.signalfd.index[k] then return meth.signalfd.index[k](ss) end
  end,
  __len = lenfn,
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

addtype("sigset", "sigset_t", {
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

-- these are declared above
samap = {
  [c.AF.UNIX] = t.sockaddr_un,
  [c.AF.INET] = t.sockaddr_in,
  [c.AF.INET6] = t.sockaddr_in6,
  [c.AF.NETLINK] = t.sockaddr_nl,
  [c.AF.PACKET] = t.sockaddr_ll,
}

samap2 = {
  [c.AF.UNIX] = pt.sockaddr_un,
  [c.AF.INET] = pt.sockaddr_in,
  [c.AF.INET6] = pt.sockaddr_in6,
  [c.AF.NETLINK] = pt.sockaddr_nl,
  [c.AF.PACKET] = pt.sockaddr_ll,
}

-- slightly miscellaneous types, eg need to use Lua metatables

-- TODO convert to use constants? note missing some macros eg WCOREDUMP(). Allow lower case.
mt.wait = {
  __index = function(w, k)
    local WTERMSIG = bit.band(w.status, 0x7f)
    local EXITSTATUS = bit.rshift(bit.band(w.status, 0xff00), 8)
    local WIFEXITED = (WTERMSIG == 0)
    local tab = {
      WIFEXITED = WIFEXITED,
      WIFSTOPPED = bit.band(w.status, 0xff) == 0x7f,
      WIFSIGNALED = not WIFEXITED and bit.band(w.status, 0x7f) ~= 0x7f -- I think this is right????? TODO recheck, cleanup
    }
    if tab.WIFEXITED then tab.EXITSTATUS = EXITSTATUS end
    if tab.WIFSTOPPED then tab.WSTOPSIG = EXITSTATUS end
    if tab.WIFSIGNALED then tab.WTERMSIG = WTERMSIG end
    if tab[k] then return tab[k] end
    local uc = 'W' .. k:upper()
    if tab[uc] then return tab[uc] end
  end
}

-- cannot really use metatype here, as status is just an int, and we need to pass pid
function t.wait(pid, status)
  return setmetatable({pid = pid, status = status}, mt.wait)
end

-- termios

local bits_to_speed = {}
for k, v in pairs(c.B) do
  bits_to_speed[v] = tonumber(k)
end

meth.termios = {
  index = {
    cfmakeraw = function(termios)
      termios.c_iflag = bit.band(termios.c_iflag, bit.bnot(c.IFLAG["IGNBRK,BRKINT,PARMRK,ISTRIP,INLCR,IGNCR,ICRNL,IXON"]))
      termios.c_oflag = bit.band(termios.c_oflag, bit.bnot(c.OFLAG["OPOST"]))
      termios.c_lflag = bit.band(termios.c_lflag, bit.bnot(c.LFLAG["ECHO,ECHONL,ICANON,ISIG,IEXTEN"]))
      termios.c_cflag = bit.bor(bit.band(termios.c_cflag, bit.bnot(c.CFLAG["CSIZE,PARENB"])), c.CFLAG.CS8)
      termios.c_cc[c.CC.VMIN] = 1
      termios.c_cc[c.CC.VTIME] = 0
      return true
    end,
    cfgetospeed = function(termios)
      local bits = bit.band(termios.c_cflag, c.CBAUD)
      return bits_to_speed[bits]
    end,
    -- TODO move to __newindex?
    cfsetospeed = function(termios, speed)
      local speed = c.B[speed]
      if bit.band(speed, bit.bnot(c.CBAUD)) ~= 0 then return nil end
      termios.c_cflag = bit.bor(bit.band(termios.c_cflag, bit.bnot(c.CBAUD)), speed)
      return true
    end,
  },
}

meth.termios.index.cfsetspeed = meth.termios.index.cfsetospeed -- also shorter names eg ospeed?
meth.termios.index.cfgetspeed = meth.termios.index.cfgetospeed
meth.termios.index.cfsetispeed = meth.termios.index.cfsetospeed
meth.termios.index.cfgetispeed = meth.termios.index.cfgetospeed

mt.termios = {
  __index = function(termios, k)
    if meth.termios.index[k] then return meth.termios.index[k] end -- note these are called as objects, could use meta metatable
    if c.CC[k] then return termios.c_cc[c.CC[k]] end
  end,
  __newindex = function(termios, k, v)
    if meth.termios.newindex[k] then return meth.termios.newindex[k](termios, v) end
    if c.CC[k] then termios.c_cc[c.CC[k]] = v end
  end,
}

addtype("termios", "struct termios", mt.termios)
addtype("termios2", "struct termios2", mt.termios)

meth.iocb = {
  index = {
    opcode = function(iocb) return iocb.aio_lio_opcode end,
    data = function(iocb) return tonumber(iocb.aio_data) end,
    reqprio = function(iocb) return iocb.aio_reqprio end,
    fildes = function(iocb) return iocb.aio_fildes end, -- do not convert to fd as will already be open, don't want to gc
    buf = function(iocb) return iocb.aio_buf end,
    nbytes = function(iocb) return tonumber(iocb.aio_nbytes) end,
    offset = function(iocb) return tonumber(iocb.aio_offset) end,
    resfd = function(iocb) return iocb.aio_resfd end,
    flags = function(iocb) return iocb.aio_flags end,
  },
  newindex = {
    opcode = function(iocb, v) iocb.aio_lio_opcode = c.IOCB_CMD[v] end,
    data = function(iocb, v) iocb.aio_data = v end,
    reqprio = function(iocb, v) iocb.aio_reqprio = v end,
    fildes = function(iocb, v) iocb.aio_fildes = getfd(v) end,
    buf = function(iocb, v) iocb.aio_buf = ffi.cast(t.int64, pt.void(v)) end,
    nbytes = function(iocb, v) iocb.aio_nbytes = v end,
    offset = function(iocb, v) iocb.aio_offset = v end,
    flags = function(iocb, v) iocb.aio_flags = c.IOCB_FLAG[v] end,
    resfd = function(iocb, v)
      iocb.aio_flags = bit.bor(iocb.aio_flags, c.IOCB_FLAG.RESFD)
      iocb.aio_resfd = getfd(v)
    end,
  },
}

mt.iocb = {
  __index = function(iocb, k) if meth.iocb.index[k] then return meth.iocb.index[k](iocb) end end,
  __newindex = function(iocb, k, v) if meth.iocb.newindex[k] then meth.iocb.newindex[k](iocb, v) end end,
  __new = function(tp, ioi)
    local iocb = ffi.new(tp)
    if ioi then for k, v in pairs(ioi) do iocb[k] = v end end
    return iocb
  end,
}

addtype("iocb", "struct iocb", mt.iocb)

-- aio operations want an array of pointers to struct iocb. To make sure no gc, we provide a table with array and pointers
-- easiest to do as Lua table not ffi type. 
-- expects Lua table of either tables or iocb as input. can provide ptr table too
-- TODO check maybe the implementation actually copies these? only the posix aio says you need to keep.

t.iocb_array = function(tab, ptrs)
  local nr = #tab
  local a = {nr = nr, iocbs = {}, ptrs = ptrs or t.iocb_ptrs(nr)}
  for i = 1, nr do
    local iocb = tab[i]
    a.iocbs[i] = istype(t.iocb, iocb) or t.iocb(iocb)
    a.ptrs[i - 1] = a.iocbs[i]
  end
  return a
end

-- ip, udp types. Need endian conversions

local function ip_checksum(buf, size, c, notfinal)
  c = c or 0
  local b8 = pt.char(buf)
  local i16 = t.uint16_1()
  for i = 0, size - 1, 2 do
    ffi.copy(i16, b8 + i, 2)
    c = c + i16[0]
  end
  if size % 2 == 1 then
    i16[0] = 0
    ffi.copy(i16, b8[size - 1], 1)
    c = c + i16[0]
  end

  local v = bit.band(c, 0xffff)
  if v < 0 then v = v + 0x10000 end -- positive
  c = bit.rshift(c, 16) + v
  c = c + bit.rshift(c, 16)

  if not notfinal then c = bit.bnot(c) end
  if c < 0 then c = c + 0x10000 end -- positive
  return c
end

meth.iphdr = {
  index = {
    checksum = function(i) return function(i)
      i.check = 0
      i.check = ip_checksum(i, s.iphdr)
      return i.check
    end end,
  },
  newindex = {
  },
}

mt.iphdr = {
  __index = function(i, k) if meth.iphdr.index[k] then return meth.iphdr.index[k](i) end end,
  __newindex = function(i, k, v) if meth.iphdr.newindex[k] then meth.iphdr.index[k](i, v) end end,
}

addtype("iphdr", "struct iphdr", mt.iphdr)

-- ugh, naming problems as cannot remove namespace as usual
meth.udphdr = {
  index = {
    src = function(u) return ntohs(u.source) end,
    dst = function(u) return ntohs(u.dest) end,
    length = function(u) return ntohs(u.len) end,
    checksum = function(i) return function(i, ip, body)
      local bip = pt.char(ip)
      local bup = pt.char(i)
      local cs = 0
      -- checksum pseudo header
      cs = ip_checksum(bip + ffi.offsetof(ip, "saddr"), 4, cs, true)
      cs = ip_checksum(bip + ffi.offsetof(ip, "daddr"), 4, cs, true)
      local pr = t.char2(0, c.IPPROTO.UDP)
      cs = ip_checksum(pr, 2, cs, true)
      cs = ip_checksum(bup + ffi.offsetof(i, "len"), 2, cs, true)
      -- checksum udp header
      i.check = 0
      cs = ip_checksum(i, s.udphdr, cs, true)
      -- checksum body
      cs = ip_checksum(body, i.length - s.udphdr, cs)
      if cs == 0 then cs = 0xffff end
      i.check = cs
      return cs
    end end,
  },
  newindex = {
    src = function(u, v) u.source = htons(v) end,
    dst = function(u, v) u.dest = htons(v) end,
    length = function(u, v) u.len = htons(v) end,
  },
}

-- checksum = function(u, ...) return 0 end, -- TODO checksum, needs IP packet info too. as method.
mt.udphdr = {
  __index = function(u, k) if meth.udphdr.index[k] then return meth.udphdr.index[k](u) end end,
  __newindex = function(u, k, v) if meth.udphdr.newindex[k] then meth.udphdr.newindex[k](u, v) end end,
}

addtype("udphdr", "struct udphdr", mt.udphdr)

mt.ethhdr = {
  -- TODO
}

addtype("ethhdr", "struct ethhdr", mt.ethhdr)

mt.sock_filter = {
  __new = function(tp, code, k, jt, jf)
    return ffi.new(tp, c.BPF[code], jt or 0, jf or 0, k or 0)
  end
}

addtype("sock_filter", "struct sock_filter", mt.sock_filter)

-- capabilities data is an array so cannot put metatable on it. Also depends on version, so combine into one structure.

-- TODO maybe add caching
local function capflags(val, str)
  if not str then return val end
  if #str == 0 then return val end
  local a = h.split(",", str)
  for i, v in ipairs(a) do
    local s = h.trim(v):upper()
    assert(c.CAP[s], "invalid capability") -- TODO not sure if throw is best solution here, but silent errors otherwise
    val[s] = true
  end
  return val
end

mt.cap = {
  __index = function(cap, k)
    local ci = c.CAP[k]
    if not ci then return end
    local i, shift = h.divmod(ci, 32)
    local mask = bit.lshift(1, shift)
    return bit.band(cap.cap[i], mask) ~= 0
  end,
  __newindex = function(cap, k, v)
    if v == true then v = 1 elseif v == false then v = 0 end
    local ci = c.CAP[k]
    if not ci then return end
    local i, shift = h.divmod(ci, 32)
    local mask = bit.bnot(bit.lshift(1, shift))
    local set = bit.lshift(v, shift)
    cap.cap[i] = bit.bor(bit.band(cap.cap[i], mask), set)
  end,
  __tostring = function(cap)
    local tab = {}
    for i = 1, #c.CAP do
      local k = c.CAP[i]
      if cap[k] then tab[#tab + 1] = k end
    end
    return table.concat(tab, ",")
  end,
  __new = function(tp, str)
    local cap = ffi.new(tp)
    if str then capflags(cap, str) end
    return cap
  end,
}

addtype("cap", "struct cap", mt.cap)

-- TODO add method to return hdr, data
meth.capabilities = {
  index = {
    hdrdata = function(cap)
      local hdr, data = t.user_cap_header(cap.version, cap.pid), t.user_cap_data2()
      data[0].effective, data[1].effective = cap.effective.cap[0], cap.effective.cap[1]
      data[0].permitted, data[1].permitted = cap.permitted.cap[0], cap.permitted.cap[1]
      data[0].inheritable, data[1].inheritable = cap.inheritable.cap[0], cap.inheritable.cap[1]
      return hdr, data
    end
  },
}

mt.capabilities = {
  __index = function(cap, k) if meth.capabilities.index[k] then return function() return meth.capabilities.index[k](cap) end end end,
  __new = function(tp, hdr, data)
    local cap = ffi.new(tp, c.LINUX_CAPABILITY_VERSION[3], 0)
    if type(hdr) == "table" then
      if hdr.permitted then cap.permitted = t.cap(hdr.permitted) end
      if hdr.effective then cap.effective = t.cap(hdr.effective) end
      if hdr.inheritable then cap.inheritable = t.cap(hdr.inheritable) end
      cap.pid = hdr.pid or 0
      if hdr.version then cap.version = c.LINUX_CAPABILITY_VERSION[hdr.version] end
      return cap
    end
    -- not passed a table
    if hdr then cap.version, cap.pid = hdr.version, hdr.pid end
    if data then
      cap.effective.cap[0], cap.effective.cap[1] = data[0].effective, data[1].effective
      cap.permitted.cap[0], cap.permitted.cap[1] = data[0].permitted, data[1].permitted
      cap.inheritable.cap[0], cap.inheritable.cap[1] = data[0].inheritable, data[1].inheritable
    end
    return cap
  end,
  __tostring = function(cap)
    local str = ""
    for nm, capt in pairs{permitted = cap.permitted, inheritable = cap.inheritable, effective = cap.effective} do
      str = str .. nm .. ": "
      str = str .. tostring(capt) .. "\n"
    end
    return str
  end,
}

addtype("capabilities", "struct capabilities", mt.capabilities)

t.groups = ffi.metatype("struct {int count; gid_t list[?];}", {
  __index = function(g, k)
    return g.list[k - 1]
  end,
  __newindex = function(g, k, v)
    g.list[k - 1] = v
  end,
  __new = function(tp, gs)
    if type(gs) == 'number' then return ffi.new(tp, gs, gs) end
    return ffi.new(tp, #gs, #gs, gs)
  end,
  __len = function(g) return g.count end,
})

-- difficult to sanely use an ffi metatype for inotify events, so use Lua table
mt.inotify_events = {
  __index = function(tab, k)
    if c.IN[k] then return bit.band(tab.mask, c.IN[k]) ~= 0 end
  end
}

t.inotify_events = function(buffer, len)
  local off, ee = 0, {}
  while off < len do
    local ev = pt.inotify_event(buffer + off)
    local le = setmetatable({wd = ev.wd, mask = ev.mask, cookie = ev.cookie}, mt.inotify_events)
    if ev.len > 0 then le.name = ffi.string(ev.name) end
    ee[#ee + 1] = le
    off = off + ffi.sizeof(t.inotify_event(ev.len))
  end
  return ee
end

-- TODO for input should be able to set modes automatically from which fields are set.
mt.timex = {
  __new = function(tp, a)
    if type(a) == 'table' then
      if a.modes then a.modes = c.ADJ[a.modes] end
      if a.status then a.status = c.STA[a.status] end
      return ffi.new(tp, a)
    end
    return ffi.new(tp)
  end,
}

addtype("timex", "struct timex", mt.timex)

-- not sane to convert to ffi metatype, only used as adjtimex needs to return ret and a struct
mt.adjtimex = {
  __index = function(timex, k)
    if c.TIME[k] then return timex.state == c.TIME[k] end
    return nil
  end
}

t.adjtimex = function(ret, timex)
  return setmetatable({state = ret, timex = timex}, mt.adjtimex)
end

meth.epoll_event = {
  index = {
    fd = function(e) return tonumber(e.data.fd) end,
    u64 = function(e) return e.data.u64 end,
    u32 = function(e) return e.data.u32 end,
    ptr = function(e) return e.data.ptr end,
  },
  newindex = {
    fd = function(e, v) e.data.fd = v end,
    u64 = function(e, v) e.data.u64 = v end,
    u32 = function(e, v) e.data.u32 = v end,
    ptr = function(e, v) e.data.ptr = v end,
  }
}

mt.epoll_event = {
  __index = function(e, k)
    if meth.epoll_event.index[k] then return meth.epoll_event.index[k](e) end
    if c.EPOLL[k] then return bit.band(e.events, c.EPOLL[k]) ~= 0 end
  end,
  __newindex = function(e, k, v) if meth.epoll_event.newindex[k] then meth.epoll_event.newindex[k](e, v) end end,
  __new = function(tp, a)
    local e = ffi.new(tp)
    if a then
      if a.events then a.events = c.EPOLL[a.events] end
      for k, v in pairs(a) do e[k] = v end
    end
    return e
  end,
}

addtype("epoll_event", "struct epoll_event", mt.epoll_event)

-- this is array form of epoll_events as returned from epoll_wait TODO make constructor for epoll_events?
t.epoll_wait = function(n, events)
  local r = {events = events}
  for i = 1, n do
    r[i] = events[i - 1]
  end
  return r
end

-- difficult to use ffi type as variable length
mt.dent = {
  __index = function(tab, k)
    if c.DT[k] then return tab.type == c.DT[k] end
  end
}

t.dent = function(dp)
  return setmetatable({
    inode = tonumber(dp.d_ino),
    type = dp.d_type,
    name = ffi.string(dp.d_name), -- could calculate length
    d_ino = dp.d_ino,
  }, mt.dent)
end

-- default implementation, no metatmethods, overriden later
t.socketpair = function(s1, s2)
  if ffi.istype(t.int2, s1) then s1, s2 = s1[0], s1[1] end
  return {t.fd(s1), t.fd(s2)}
end

t.pipe = t.socketpair -- also just two fds

-- sigaction
t.sa_sigaction = ffi.typeof("void (*)(int, siginfo_t *, ucontext_t *)")
s.sa_sigaction = ffi.sizeof(t.sa_sigaction)

meth.sigaction = {
  index = {
    handler = function(sa) return sa.sa_handler end,
    sigaction = function(sa) return sa.sa_sigaction end,
    mask = function(sa) return sa.sa_mask end,
    flags = function(sa) return tonumber(sa.sa_flags) end,
  },
  newindex = {
    handler = function(sa, v)
      if type(v) == "string" then v = c.SIGACT[v] end
      if type(v) == "number" then v = pt.void(v) end
      if type(v) == "function" then v = ffi.cast(t.sighandler, v) end -- note doing this will leak resource, use carefully
      sa.sa_handler.sa_handler = v
    end,
    sigaction = function(sa, v)
      if type(v) == "string" then v = c.SIGACT[v] end
      if type(v) == "number" then v = pt.void(v) end
      if type(v) == "function" then v = ffi.cast(t.sa_sigaction, v) end -- note doing this will leak resource, use carefully
      sa.sa_handler.sa_sigaction = v
    end,
    mask = function(sa, v)
      if not ffi.istype(t.sigset, v) then v = t.sigset(v) end
      sa.sa_mask = v
    end,
    flags = function(sa, v) sa.sa_flags = c.SA[v] end,
  }
}

mt.sigaction = {
  __index = function(sa, k) if meth.sigaction.index[k] then return meth.sigaction.index[k](sa) end end,
  __newindex = function(sa, k, v) if meth.sigaction.newindex[k] then meth.sigaction.newindex[k](sa, v) end end,
  __new = function(tp, tab)
    local sa = ffi.new(tp)
    if tab then for k, v in pairs(tab) do sa[k] = v end end
    if tab and tab.sigaction then sa.sa_flags = bit.bor(sa.flags, c.SA.SIGINFO) end -- this flag must be set if sigaction set
    return sa
  end,
}

addtype("sigaction", "struct sigaction", mt.sigaction)

meth.cpu_set = {
  index = {
    zero = function(set) ffi.fill(set, s.cpu_set) end,
    set = function(set, cpu)
      if type(cpu) == "table" then -- table is an array of CPU numbers eg {1, 2, 4}
        for i = 1, #cpu do set:set(cpu[i]) end
        return set
      end
      local d = bit.rshift(cpu, 5) -- 5 is 32 bits
      set.val[d] = bit.bor(set.val[d], bit.lshift(1, cpu % 32))
      return set
    end,
    clear = function(set, cpu)
      if type(cpu) == "table" then -- table is an array of CPU numbers eg {1, 2, 4}
        for i = 1, #cpu do set:clear(cpu[i]) end
        return set
      end
      local d = bit.rshift(cpu, 5) -- 5 is 32 bits
      set.val[d] = bit.band(set.val[d], bit.bnot(bit.lshift(1, cpu % 32)))
      return set
    end,
    get = function(set, cpu)
      local d = bit.rshift(cpu, 5) -- 5 is 32 bits
      return bit.band(set.val[d], bit.lshift(1, cpu % 32)) ~= 0
    end,
    -- TODO add rest of interface from man(3) CPU_SET
  },
}

mt.cpu_set = {
  __index = function(set, k)
    if meth.cpu_set.index[k] then return meth.cpu_set.index[k] end
    if type(k) == "number" then return set:get(k) end
  end,
  __newindex = function(set, k, v)
    if v then set:set(k) else set:clear(k) end
  end,
  __new = function(tp, tab)
    local set = ffi.new(tp)
    if tab then set:set(tab) end
    return set
  end,
  __tostring = function(set)
    local tab = {}
    for i = 0, s.cpu_set * 8 - 1 do if set:get(i) then tab[#tab + 1] = i end end
    return "{" .. table.concat(tab, ",") .. "}"
  end
}

addtype("cpu_set", "struct cpu_set_t", mt.cpu_set)

meth.mq_attr = {
  index = {
    flags = function(mqa) return mqa.mq_flags end,
    maxmsg = function(mqa) return mqa.mq_maxmsg end,
    msgsize = function(mqa) return mqa.mq_msgsize end,
    curmsgs = function(mqa) return mqa.mq_curmsgs end,
  },
  newindex = {
    flags = function(mqa, v) mqa.mq_flags = c.OMQATTR[v] end, -- only allows O.NONBLOCK
    maxmsg = function(mqa, v) mqa.mq_maxmsg = v end,
    msgsize = function(mqa, v) mqa.mq_msgsize = v end,
    -- no sense in writing curmsgs
  }
}

mt.mq_attr = {
  __index = function(mqa, k) if meth.mq_attr.index[k] then return meth.mq_attr.index[k](mqa) end end,
  __newindex = function(mqa, k, v) if meth.mq_attr.newindex[k] then meth.mq_attr.newindex[k](mqa, v) end end,
  __new = newfn,
}

addtype("mq_attr", "struct mq_attr", mt.mq_attr)

meth.ifreq = {
  index = {
    name = function(ifr) return ffi.string(ifr.ifr_ifrn.ifrn_name) end,
    addr = function(ifr) return ifr.ifr_ifru.ifru_addr end,
    dstaddr = function(ifr) return ifr.ifr_ifru.ifru_dstaddr end,
    broadaddr = function(ifr) return ifr.ifr_ifru.ifru_broadaddr end,
    netmask = function(ifr) return ifr.ifr_ifru.ifru_netmask end,
    hwaddr = function(ifr) return ifr.ifr_ifru.ifru_hwaddr end,
    flags = function(ifr) return ifr.ifr_ifru.ifru_flags end,
    -- TODO rest of fields
  },
  newindex = {
    name = function(ifr, v)
      assert(#v <= c.IFNAMSIZ, "name too long")
      ifr.ifr_ifrn.ifrn_name = v
    end,
    flags = function(ifr, v)
      ifr.ifr_ifru.ifru_flags = c.IFREQ[v]
    end,
    -- TODO rest of fields
  },
}

mt.ifreq = {
  __index = function(ifr, k) if meth.ifreq.index[k] then return meth.ifreq.index[k](ifr) end end,
  __newindex = function(ifr, k, v) if meth.ifreq.newindex[k] then meth.ifreq.newindex[k](ifr, v) end end,
  __new = newfn,
}

addtype("ifreq", "struct ifreq", mt.ifreq)

return types

end

