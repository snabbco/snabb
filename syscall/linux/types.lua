-- Linux kernel types

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

-- TODO add __len to metatables of more

local function init(types)

local abi = require "syscall.abi"

local t, pt, s, ctypes = types.t, types.pt, types.s, types.ctypes

local ffi = require "ffi"
local bit = require "syscall.bit"

local h = require "syscall.helpers"

local addtype, addtype_var, addtype_fn, addraw2 = h.addtype, h.addtype_var, h.addtype_fn, h.addraw2
local ptt, reviter, mktype, istype, lenfn, lenmt, getfd, newfn
  = h.ptt, h.reviter, h.mktype, h.istype, h.lenfn, h.lenmt, h.getfd, h.newfn
local ntohl, ntohl, ntohs, htons = h.ntohl, h.ntohl, h.ntohs, h.htons
local split, trim = h.split, h.trim

local c = require "syscall.linux.constants"

local mt = {} -- metatables

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
for k, v in pairs(c.SIGFPE ) do
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
for k, v in pairs(c.SIGPOLL or {}) do
  signal_reasons[c.SIG.POLL][v] = k
end

local addtypes = {
  fdset = "fd_set",
  clockid = "clockid_t",
  sighandler = "sighandler_t",
  aio_context = "aio_context_t",
  clockid = "clockid_t",
}

local addstructs = {
  ucred = "struct ucred",
  sysinfo = "struct sysinfo",
  nlmsghdr = "struct nlmsghdr",
  rtgenmsg = "struct rtgenmsg",
  ifinfomsg = "struct ifinfomsg",
  ifaddrmsg = "struct ifaddrmsg",
  rtattr = "struct rtattr",
  rta_cacheinfo = "struct rta_cacheinfo",
  nlmsgerr = "struct nlmsgerr",
  nda_cacheinfo = "struct nda_cacheinfo",
  ndt_stats = "struct ndt_stats",
  ndtmsg = "struct ndtmsg",
  ndt_config = "struct ndt_config",
  utsname = "struct utsname",
  fdb_entry = "struct fdb_entry",
  seccomp_data = "struct seccomp_data",
  rtnl_link_stats = "struct rtnl_link_stats",
  statfs = "struct statfs64",
  ifa_cacheinfo = "struct ifa_cacheinfo",
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
  sock_fprog = "struct sock_fprog",
  user_cap_header = "struct user_cap_header",
  user_cap_data = "struct user_cap_data",
  xt_get_revision = "struct xt_get_revision",
  vfs_cap_data = "struct vfs_cap_data",
  ucontext = "ucontext_t",
  mcontext = "mcontext_t",
  tun_pi = "struct tun_pi",
  tun_filter = "struct tun_filter",
  vhost_vring_state = "struct vhost_vring_state",
  vhost_vring_file = "struct vhost_vring_file",
  vhost_vring_addr = "struct vhost_vring_addr",
  vhost_memory_region = "struct vhost_memory_region",
  vhost_memory = "struct vhost_memory",
}

for k, v in pairs(addtypes) do addtype(types, k, v) end
for k, v in pairs(addstructs) do addtype(types, k, v, lenmt) end

-- these ones not in table as not helpful with vararg or arrays TODO add more addtype variants
t.inotify_event = ffi.typeof("struct inotify_event")
pt.inotify_event = ptt("struct inotify_event") -- still need pointer to this

t.aio_context1 = ffi.typeof("aio_context_t[1]")
t.sock_fprog1 = ffi.typeof("struct sock_fprog[1]")

t.user_cap_data2 = ffi.typeof("struct user_cap_data[2]")

-- luaffi gets confused if call ffi.typeof("...[?]") it calls __new so redefine as functions
local iocbs = ffi.typeof("struct iocb[?]")
t.iocbs = function(n, ...) return ffi.new(iocbs, n, ...) end
local sock_filters = ffi.typeof("struct sock_filter[?]")
t.sock_filters = function(n, ...) return ffi.new(sock_filters, n, ...) end
local iocb_ptrs = ffi.typeof("struct iocb *[?]")
t.iocb_ptrs = function(n, ...) return ffi.new(iocb_ptrs, n, ...) end

-- types with metatypes

-- Note 32 bit dev_t; glibc has 64 bit dev_t but we use syscall API which does not
local function makedev(major, minor)
  if type(major) == "table" then major, minor = major[1], major[2] end
  local dev = major or 0
  if minor then dev = bit.bor(bit.lshift(bit.band(minor, 0xffffff00), 12), bit.band(minor, 0xff), bit.lshift(major, 8)) end
  return dev
end

mt.device = {
  index = {
    major = function(dev)
      local d = dev.dev
      return bit.band(bit.rshift(d, 8), 0x00000fff)
    end,
    minor = function(dev)
      local d = dev.dev
      return bit.bor(bit.band(d, 0x000000ff), bit.band(bit.rshift(d, 12), 0x000000ff))
    end,
    device = function(dev) return tonumber(dev.dev) end,
  },
  newindex = {
    device = function(dev, major, minor) dev.dev = makedev(major, minor) end,
  },
  __new = function(tp, major, minor)
    return ffi.new(tp, makedev(major, minor))
  end,
}

addtype(types, "device", "struct {dev_t dev;}", mt.device)

mt.sockaddr = {
  index = {
    family = function(sa) return sa.sa_family end,
  },
}

addtype(types, "sockaddr", "struct sockaddr", mt.sockaddr)

-- cast socket address to actual type based on family, defined later
local samap_pt = {}

mt.sockaddr_storage = {
  index = {
    family = function(sa) return sa.ss_family end,
  },
  newindex = {
    family = function(sa, v) sa.ss_family = c.AF[v] end,
  },
  __index = function(sa, k)
    if mt.sockaddr_storage.index[k] then return mt.sockaddr_storage.index[k](sa) end
    local st = samap_pt[sa.ss_family]
    if st then
      local cs = st(sa)
      return cs[k]
    end
    error("invalid index " .. k)
  end,
  __newindex = function(sa, k, v)
    if mt.sockaddr_storage.newindex[k] then
      mt.sockaddr_storage.newindex[k](sa, v)
      return
    end
    local st = samap_pt[sa.ss_family]
    if st then
      local cs = st(sa)
      cs[k] = v
      return
    end
    error("invalid index " .. k)
  end,
  __new = function(tp, init)
    local ss = ffi.new(tp)
    local family
    if init and init.family then family = c.AF[init.family] end
    local st
    if family then
      st = samap_pt[family]
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
  -- netbsd likes to see the correct size when it gets a sockaddr; Linux was ok with a longer one
  __len = function(sa)
    if samap_pt[sa.family] then
      local cs = samap_pt[sa.family](sa)
      return #cs
    else
      return s.sockaddr_storage
    end
  end,
}

-- experiment, see if we can use this as generic type, to avoid allocations.
addtype(types, "sockaddr_storage", "struct sockaddr_storage", mt.sockaddr_storage)

mt.sockaddr_in = {
  index = {
    family = function(sa) return sa.sin_family end,
    port = function(sa) return ntohs(sa.sin_port) end,
    addr = function(sa) return sa.sin_addr end,
  },
  newindex = {
    family = function(sa, v) sa.sin_family = v end,
    port = function(sa, v) sa.sin_port = htons(v) end,
    addr = function(sa, v) sa.sin_addr = mktype(t.in_addr, v) end,
  },
  __new = function(tp, port, addr)
    if type(port) == "table" then return newfn(tp, port) end
    return newfn(tp, {family = c.AF.INET, port = port, addr = addr})
  end,
  __len = function(tp) return s.sockaddr_in end,
}

addtype(types, "sockaddr_in", "struct sockaddr_in", mt.sockaddr_in)

mt.sockaddr_in6 = {
  index = {
    family = function(sa) return sa.sin6_family end,
    port = function(sa) return ntohs(sa.sin6_port) end,
    addr = function(sa) return sa.sin6_addr end,
  },
  newindex = {
    family = function(sa, v) sa.sin6_family = v end,
    port = function(sa, v) sa.sin6_port = htons(v) end,
    addr = function(sa, v) sa.sin6_addr = mktype(t.in6_addr, v) end,
    flowinfo = function(sa, v) sa.sin6_flowinfo = v end,
    scope_id = function(sa, v) sa.sin6_scope_id = v end,
  },
  __new = function(tp, port, addr, flowinfo, scope_id) -- reordered initialisers.
    if type(port) == "table" then return newfn(tp, port) end
    return newfn(tp, {family = c.AF.INET6, port = port, addr = addr, flowinfo = flowinfo, scope_id = scope_id})
  end,
  __len = function(tp) return s.sockaddr_in6 end,
}

addtype(types, "sockaddr_in6", "struct sockaddr_in6", mt.sockaddr_in6)

-- we do provide this directly for compatibility, only use for standard names
mt.sockaddr_un = {
  index = {
    family = function(sa) return sa.sun_family end,
    path = function(sa) return ffi.string(sa.sun_path) end, -- only valid for proper names
  },
  newindex = {
    family = function(sa, v) sa.sun_family = v end,
    path = function(sa, v) ffi.copy(sa.sun_path, v) end,
  },
  __new = function(tp, path) return newfn(tp, {family = c.AF.UNIX, path = path}) end, -- TODO accept table initialiser
  __len = function(tp) return s.sockaddr_un end, -- TODO lenfn (default) instead
}

addtype(types, "sockaddr_un", "struct sockaddr_un", mt.sockaddr_un)

-- this is a bit odd, but we actually use Lua metatables for sockaddr_un, and use t.sa to multiplex
-- basically the lINUX unix socket structure is not possible to interpret without size, but does not have size in struct
-- nasty, but have not thought of a better way yet; could make an ffi type
local lua_sockaddr_un_mt = {
  __index = function(un, k)
    local sa = un.addr
    if k == 'family' then return sa.family end
    local namelen = un.addrlen - s.sun_family
    if namelen > 0 then
      if sa.sun_path[0] == 0 then
        if k == 'abstract' then return true end
        if k == 'name' then return ffi.string(sa.sun_path, namelen) end -- should we also remove leading \0?
      else
        if k == 'name' then return ffi.string(sa.sun_path) end
      end
    else
      if k == 'unnamed' then return true end
    end
  end,
  __len = function(un) return un.addrlen end,
}

function t.sa(addr, addrlen)
  local family = addr.family
  if family == c.AF.UNIX then -- we return Lua metatable not metatype, as need length to decode
    local sa = t.sockaddr_un()
    ffi.copy(sa, addr, addrlen)
    return setmetatable({addr = sa, addrlen = addrlen}, lua_sockaddr_un_mt)
  end
  return addr
end

local nlgroupmap = { -- map from netlink socket type to group names. Note there are two forms of name though, bits and shifts.
  [c.NETLINK.ROUTE] = c.RTMGRP, -- or RTNLGRP_ and shift not mask TODO make shiftflags function
  -- add rest of these
--  [c.NETLINK.SELINUX] = c.SELNLGRP,
}

mt.sockaddr_nl = {
  index = {
    family = function(sa) return sa.nl_family end,
    pid = function(sa) return sa.nl_pid end,
    groups = function(sa) return sa.nl_groups end,
  },
  newindex = {
    pid = function(sa, v) sa.nl_pid = v end,
    groups = function(sa, v) sa.nl_groups = v end,
  },
  __new = function(tp, pid, groups, nltype)
    if type(pid) == "table" then
      local tb = pid
      pid, groups, nltype = tb.nl_pid or tb.pid, tb.nl_groups or tb.groups, tb.type
    end
    if nltype and nlgroupmap[nltype] then groups = nlgroupmap[nltype][groups] end -- see note about shiftflags
    return ffi.new(tp, {nl_family = c.AF.NETLINK, nl_pid = pid, nl_groups = groups})
  end,
  __len = function(tp) return s.sockaddr_nl end,
}

addtype(types, "sockaddr_nl", "struct sockaddr_nl", mt.sockaddr_nl)

mt.sockaddr_ll = {
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
  },
  __new = function(tp, tb)
    local sa = ffi.new(tp, {sll_family = c.AF.PACKET})
    for k, v in pairs(tb or {}) do sa[k] = v end
    return sa
  end,
  __len = function(tp) return s.sockaddr_ll end,
}

addtype(types, "sockaddr_ll", "struct sockaddr_ll", mt.sockaddr_ll)

mt.stat = {
  index = {
    dev = function(st) return t.device(st.st_dev) end,
    ino = function(st) return tonumber(st.st_ino) end,
    mode = function(st) return st.st_mode end,
    nlink = function(st) return tonumber(st.st_nlink) end,
    uid = function(st) return st.st_uid end,
    gid = function(st) return st.st_gid end,
    size = function(st) return tonumber(st.st_size) end,
    blksize = function(st) return tonumber(st.st_blksize) end,
    blocks = function(st) return tonumber(st.st_blocks) end,
    atime = function(st) return tonumber(st.st_atime) end,
    ctime = function(st) return tonumber(st.st_ctime) end,
    mtime = function(st) return tonumber(st.st_mtime) end,
    rdev = function(st) return t.device(st.st_rdev) end,

    type = function(st) return bit.band(st.st_mode, c.S_I.FMT) end,
    todt = function(st) return bit.rshift(st.type, 12) end,
    isreg = function(st) return st.type == c.S_I.FREG end,
    isdir = function(st) return st.type == c.S_I.FDIR end,
    ischr = function(st) return st.type == c.S_I.FCHR end,
    isblk = function(st) return st.type == c.S_I.FBLK end,
    isfifo = function(st) return st.type == c.S_I.FIFO end,
    islnk = function(st) return st.type == c.S_I.FLNK end,
    issock = function(st) return st.type == c.S_I.FSOCK end,
  },
}

-- add some friendlier names to stat, also for luafilesystem compatibility
mt.stat.index.access = mt.stat.index.atime
mt.stat.index.modification = mt.stat.index.mtime
mt.stat.index.change = mt.stat.index.ctime

local namemap = {
  file             = mt.stat.index.isreg,
  directory        = mt.stat.index.isdir,
  link             = mt.stat.index.islnk,
  socket           = mt.stat.index.issock,
  ["char device"]  = mt.stat.index.ischr,
  ["block device"] = mt.stat.index.isblk,
  ["named pipe"]   = mt.stat.index.isfifo,
}

mt.stat.index.typename = function(st)
  for k, v in pairs(namemap) do if v(st) then return k end end
  return "other"
end

addtype(types, "stat", "struct stat", mt.stat)

-- TODO this is broken, need to use fields from the correct union technically
-- ie check which of the unions we should be using and get all fields from that
-- (note as per Musl list the standard kernel,glibc definitions are wrong too...)
mt.siginfo = {
  index = {
    signo   = function(s) return s.si_signo end,
    errno   = function(s) return s.si_errno end,
    code    = function(s) return s.si_code end,
    pid     = function(s) return s._sifields.kill.si_pid end,
    uid     = function(s) return s._sifields.kill.si_uid end,
    timerid = function(s) return s._sifields.timer.si_tid end,
    overrun = function(s) return s._sifields.timer.si_overrun end,
    status  = function(s) return s._sifields.sigchld.si_status end,
    utime   = function(s) return s._sifields.sigchld.si_utime end,
    stime   = function(s) return s._sifields.sigchld.si_stime end,
    value   = function(s) return s._sifields.rt.si_sigval end,
    int     = function(s) return s._sifields.rt.si_sigval.sival_int end,
    ptr     = function(s) return s._sifields.rt.si_sigval.sival_ptr end,
    addr    = function(s) return s._sifields.sigfault.si_addr end,
    band    = function(s) return s._sifields.sigpoll.si_band end,
    fd      = function(s) return s._sifields.sigpoll.si_fd end,
  },
  newindex = {
    signo   = function(s, v) s.si_signo = v end,
    errno   = function(s, v) s.si_errno = v end,
    code    = function(s, v) s.si_code = v end,
    pid     = function(s, v) s._sifields.kill.si_pid = v end,
    uid     = function(s, v) s._sifields.kill.si_uid = v end,
    timerid = function(s, v) s._sifields.timer.si_tid = v end,
    overrun = function(s, v) s._sifields.timer.si_overrun = v end,
    status  = function(s, v) s._sifields.sigchld.si_status = v end,
    utime   = function(s, v) s._sifields.sigchld.si_utime = v end,
    stime   = function(s, v) s._sifields.sigchld.si_stime = v end,
    value   = function(s, v) s._sifields.rt.si_sigval = v end,
    int     = function(s, v) s._sifields.rt.si_sigval.sival_int = v end,
    ptr     = function(s, v) s._sifields.rt.si_sigval.sival_ptr = v end,
    addr    = function(s, v) s._sifields.sigfault.si_addr = v end,
    band    = function(s, v) s._sifields.sigpoll.si_band = v end,
    fd      = function(s, v) s._sifields.sigpoll.si_fd = v end,
  },
}

addtype(types, "siginfo", "struct siginfo", mt.siginfo)

-- Linux internally uses non standard sigaction type k_sigaction
local sa_handler_type = ffi.typeof("void (*)(int)")
local to_handler = function(v) return ffi.cast(sa_handler_type, t.uintptr(v)) end -- luaffi needs uintptr, and full cast
mt.sigaction = {
  index = {
    handler = function(sa) return sa.sa_handler end,
    sigaction = function(sa) return sa.sa_handler end,
    mask = function(sa) return sa.sa_mask end, -- TODO would rather return type of sigset_t
    flags = function(sa) return tonumber(sa.sa_flags) end,
  },
  newindex = {
    handler = function(sa, v)
      if type(v) == "string" then v = to_handler(c.SIGACT[v]) end
      if type(v) == "number" then v = to_handler(v) end
      sa.sa_handler = v
    end,
    sigaction = function(sa, v)
      if type(v) == "string" then v = to_handler(c.SIGACT[v]) end
      if type(v) == "number" then v = to_handler(v) end
      sa.sa_handler.sa_sigaction = v
    end,
    mask = function(sa, v)
      if not ffi.istype(t.sigset, v) then v = t.sigset(v) end
      ffi.copy(sa.sa_mask, v, ffi.sizeof(sa.sa_mask))
    end,
    flags = function(sa, v) sa.sa_flags = c.SA[v] end,
  },
  __new = function(tp, tab)
    local sa = ffi.new(tp)
    if tab then for k, v in pairs(tab) do sa[k] = v end end
    if tab and tab.sigaction then sa.sa_flags = bit.bor(sa.flags, c.SA.SIGINFO) end -- this flag must be set if sigaction set
    return sa
  end,
}

addtype(types, "sigaction", "struct k_sigaction", mt.sigaction)

mt.rlimit = {
  index = {
    cur = function(r) if r.rlim_cur == c.RLIM.INFINITY then return -1 else return tonumber(r.rlim_cur) end end,
    max = function(r) if r.rlim_max == c.RLIM.INFINITY then return -1 else return tonumber(r.rlim_max) end end,
  },
  newindex = {
    cur = function(r, v)
      if v == -1 then v = c.RLIM.INFINITY end
      r.rlim_cur = c.RLIM[v] -- allows use of "infinity"
    end,
    max = function(r, v)
      if v == -1 then v = c.RLIM.INFINITY end
      r.rlim_max = c.RLIM[v] -- allows use of "infinity"
    end,
  },
  __new = newfn,
}

-- TODO some fields still missing
mt.sigevent = {
  index = {
    notify = function(self) return self.sigev_notify end,
    signo = function(self) return self.sigev_signo end,
    value = function(self) return self.sigev_value end,
  },
  newindex = {
    notify = function(self, v) self.sigev_notify = c.SIGEV[v] end,
    signo = function(self, v) self.sigev_signo = c.SIG[v] end,
    value = function(self, v) self.sigev_value = t.sigval(v) end, -- auto assigns based on type
  },
  __new = newfn,
}

addtype(types, "sigevent", "struct sigevent", mt.sigevent)

addtype(types, "rlimit", "struct rlimit64", mt.rlimit)

mt.signalfd = {
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
    ptr = function(ss) return ss.ssi_ptr end,
    utime = function(ss) return tonumber(ss.ssi_utime) end,
    stime = function(ss) return tonumber(ss.ssi_stime) end,
    addr = function(ss) return ss.ssi_addr end,
  },
  __index = function(ss, k) -- TODO simplify this
    local sig = c.SIG[k]
    if sig then return tonumber(ss.ssi_signo) == sig end
    local rname = signal_reasons_gen[ss.ssi_code]
    if not rname and signal_reasons[ss.ssi_signo] then rname = signal_reasons[ss.ssi_signo][ss.ssi_code] end
    if rname == k then return true end
    if rname == k:upper() then return true end -- TODO use some metatable to hide this?
    if mt.signalfd.index[k] then return mt.signalfd.index[k](ss) end
    error("invalid index " .. k)
  end,
}

addtype(types, "signalfd_siginfo", "struct signalfd_siginfo", mt.signalfd)

mt.siginfos = {
  __index = function(ss, k)
    return ss.sfd[k - 1]
  end,
  __len = function(p) return p.count end,
  __new = function(tp, ss)
    return ffi.new(tp, ss, ss, ss * s.signalfd_siginfo)
  end,
}

addtype_var(types, "siginfos", "struct {int count, bytes; struct signalfd_siginfo sfd[?];}", mt.siginfos)

-- TODO convert to use constants? note missing some macros eg WCOREDUMP(). Allow lower case. Also do not create table dynamically.
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

-- cannot use metatype as just an integer
function t.waitstatus(status)
  return setmetatable({status = status}, mt.wait)
end

-- termios

local bits_to_speed = {}
for k, v in pairs(c.B) do
  bits_to_speed[v] = tonumber(k)
end

mt.termios = {
  makeraw = function(termios)
    termios.c_iflag = bit.band(termios.c_iflag, bit.bnot(c.IFLAG["IGNBRK,BRKINT,PARMRK,ISTRIP,INLCR,IGNCR,ICRNL,IXON"]))
    termios.c_oflag = bit.band(termios.c_oflag, bit.bnot(c.OFLAG["OPOST"]))
    termios.c_lflag = bit.band(termios.c_lflag, bit.bnot(c.LFLAG["ECHO,ECHONL,ICANON,ISIG,IEXTEN"]))
    termios.c_cflag = bit.bor(bit.band(termios.c_cflag, bit.bnot(c.CFLAG["CSIZE,PARENB"])), c.CFLAG.CS8)
    termios.c_cc[c.CC.VMIN] = 1
    termios.c_cc[c.CC.VTIME] = 0
    return true
  end,
  index = {
    iflag = function(termios) return termios.c_iflag end,
    oflag = function(termios) return termios.c_oflag end,
    cflag = function(termios) return termios.c_cflag end,
    lflag = function(termios) return termios.c_lflag end,
    makeraw = function(termios) return mt.termios.makeraw end,
    speed = function(termios)
      local bits = bit.band(termios.c_cflag, c.CBAUD)
      return bits_to_speed[bits]
    end,
  },
  newindex = {
    iflag = function(termios, v) termios.c_iflag = c.IFLAG(v) end,
    oflag = function(termios, v) termios.c_oflag = c.OFLAG(v) end,
    cflag = function(termios, v) termios.c_cflag = c.CFLAG(v) end,
    lflag = function(termios, v) termios.c_lflag = c.LFLAG(v) end,
    speed = function(termios, speed)
      local speed = c.B[speed]
      termios.c_cflag = bit.bor(bit.band(termios.c_cflag, bit.bnot(c.CBAUD)), speed)
    end,
  },
}

mt.termios.index.ospeed = mt.termios.index.speed
mt.termios.index.ispeed = mt.termios.index.speed
mt.termios.newindex.ospeed = mt.termios.newindex.speed
mt.termios.newindex.ispeed = mt.termios.newindex.speed

for k, i in pairs(c.CC) do
  mt.termios.index[k] = function(termios) return termios.c_cc[i] end
  mt.termios.newindex[k] = function(termios, v) termios.c_cc[i] = v end
end

addtype(types, "termios", "struct termios", mt.termios)
addtype(types, "termios2", "struct termios2", mt.termios)

mt.iocb = {
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
  __new = newfn,
}

addtype(types, "iocb", "struct iocb", mt.iocb)

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

mt.sock_filter = {
  __new = function(tp, code, k, jt, jf)
    return ffi.new(tp, c.BPF[code], jt or 0, jf or 0, k or 0)
  end
}

addtype(types, "sock_filter", "struct sock_filter", mt.sock_filter)

-- capabilities data is an array so cannot put metatable on it. Also depends on version, so combine into one structure.

-- TODO maybe add caching
local function capflags(val, str)
  if not str then return val end
  if #str == 0 then return val end
  local a = h.split(",", str)
  for i, v in ipairs(a) do
    local s = h.trim(v):upper()
    if not c.CAP[s] then error("invalid capability " .. s) end
    val[s] = true
  end
  return val
end

mt.cap = {
  __index = function(cap, k)
    local ci = c.CAP[k]
    if not ci then error("invalid capability " .. k) end
    local i, shift = h.divmod(ci, 32)
    local mask = bit.lshift(1, shift)
    return bit.band(cap.cap[i], mask) ~= 0
  end,
  __newindex = function(cap, k, v)
    if v == true then v = 1 elseif v == false then v = 0 end
    local ci = c.CAP[k]
    if not ci then error("invalid capability " .. k) end
    local i, shift = h.divmod(ci, 32)
    local mask = bit.bnot(bit.lshift(1, shift))
    local set = bit.lshift(v, shift)
    cap.cap[i] = bit.bor(bit.band(cap.cap[i], mask), set)
  end,
  __tostring = function(cap)
    local tab = {}
    for k, _ in pairs(c.CAP) do
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

addtype(types, "cap", "struct cap", mt.cap)

mt.capabilities = {
    hdrdata = function(cap)
      local hdr, data = t.user_cap_header(cap.version, cap.pid), t.user_cap_data2()
      data[0].effective, data[1].effective = cap.effective.cap[0], cap.effective.cap[1]
      data[0].permitted, data[1].permitted = cap.permitted.cap[0], cap.permitted.cap[1]
      data[0].inheritable, data[1].inheritable = cap.inheritable.cap[0], cap.inheritable.cap[1]
      return hdr, data
    end,
    index = {
      hdrdata = function(cap) return mt.capabilities.hdrdata end,
    },
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

addtype(types, "capabilities", "struct capabilities", mt.capabilities)

-- difficult to sanely use an ffi metatype for inotify events, so use Lua table
mt.inotify_events = {
  __index = function(tab, k)
    if c.IN[k] then return bit.band(tab.mask, c.IN[k]) ~= 0 end
    error("invalid index " .. k)
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

addtype(types, "timex", "struct timex", mt.timex)

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

mt.epoll_event = {
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
  },
  __new = function(tp, a)
    local e = ffi.new(tp)
    if a then
      if type(a) == "string" then a.events = c.EPOLL[a]
      else 
        if a.events then a.events = c.EPOLL[a.events] end
        for k, v in pairs(a) do e[k] = v end
      end
    end
    return e
  end,
}

for k, v in pairs(c.EPOLL) do
  mt.epoll_event.index[k] = function(e) return bit.band(e.events, v) ~= 0 end
end

addtype(types, "epoll_event", "struct epoll_event", mt.epoll_event)

mt.epoll_events = {
  __len = function(ep) return ep.count end,
  __new = function(tp, n) return ffi.new(tp, n, n) end,
  __ipairs = function(ep) return reviter, ep.ep, ep.count end
}

addtype_var(types, "epoll_events", "struct {int count; struct epoll_event ep[?];}", mt.epoll_events)

mt.io_event = {
  index = {
    error = function(ev) if (ev.res < 0) then return t.error(-ev.res) end end,
  }
}

addtype(types, "io_event", "struct io_event", mt.io_event)

mt.io_events = {
  __len = function(evs) return evs.count end,
  __new = function(tp, n) return ffi.new(tp, n, n) end,
  __ipairs = function(evs) return reviter, evs.ev, evs.count end
}

addtype_var(types, "io_events", "struct {int count; struct io_event ev[?];}", mt.io_events)

mt.cpu_set = {
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
  __index = function(set, k)
    if mt.cpu_set.index[k] then return mt.cpu_set.index[k] end
    if type(k) == "number" then return set:get(k) end
    error("invalid index " .. k)
  end,
  __newindex = function(set, k, v)
    if type(k) ~= "number" then error("invalid index " .. k) end
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
  end,
}

addtype(types, "cpu_set", "struct cpu_set_t", mt.cpu_set)

mt.mq_attr = {
  index = {
    flags = function(mqa) return tonumber(mqa.mq_flags) end,
    maxmsg = function(mqa) return tonumber(mqa.mq_maxmsg) end,
    msgsize = function(mqa) return tonumber(mqa.mq_msgsize) end,
    curmsgs = function(mqa) return tonumber(mqa.mq_curmsgs) end,
  },
  newindex = {
    flags = function(mqa, v) mqa.mq_flags = c.OMQATTR[v] end, -- only allows O.NONBLOCK
    maxmsg = function(mqa, v) mqa.mq_maxmsg = v end,
    msgsize = function(mqa, v) mqa.mq_msgsize = v end,
    -- no sense in writing curmsgs
  },
  __new = newfn,
}

addtype(types, "mq_attr", "struct mq_attr", mt.mq_attr)

mt.ifreq = {
  index = {
    name = function(ifr) return ffi.string(ifr.ifr_ifrn.ifrn_name) end,
    addr = function(ifr) return ifr.ifr_ifru.ifru_addr end,
    dstaddr = function(ifr) return ifr.ifr_ifru.ifru_dstaddr end,
    broadaddr = function(ifr) return ifr.ifr_ifru.ifru_broadaddr end,
    netmask = function(ifr) return ifr.ifr_ifru.ifru_netmask end,
    hwaddr = function(ifr) return ifr.ifr_ifru.ifru_hwaddr end,
    flags = function(ifr) return ifr.ifr_ifru.ifru_flags end,
    ivalue = function(ifr) return ifr.ifr_ifru.ifru_ivalue end,
    -- TODO rest of fields
  },
  newindex = {
    name = function(ifr, v)
      assert(#v <= c.IFNAMSIZ, "name too long")
      ifr.ifr_ifrn.ifrn_name = v
    end,
    flags = function(ifr, v) ifr.ifr_ifru.ifru_flags = c.IFREQ[v] end,
    ivalue = function(ifr, v) ifr.ifr_ifru.ifru_ivalue = v end,
    -- TODO rest of fields
  },
  __new = newfn,
}

addtype(types, "ifreq", "struct ifreq", mt.ifreq)

-- note t.dirents iterator is defined in common types
local d_name_offset = ffi.offsetof("struct linux_dirent64", "d_name") -- d_name is at end of struct
mt.dirent = {
  index = {
    ino = function(self) return tonumber(self.d_ino) end,
    off = function(self) return self.d_off end,
    reclen = function(self) return self.d_reclen end,
    name = function(self) return ffi.string(pt.char(self) + d_name_offset) end,
    type = function(self) return self.d_type end,
    toif = function(self) return bit.lshift(self.d_type, 12) end, -- convert to stat types
  },
  __len = function(self) return self.d_reclen end,
}

-- TODO previously this allowed lower case values, but this static version does not
-- could add mt.dirent.index[tolower(k)] = mt.dirent.index[k] but need to do consistently elsewhere
for k, v in pairs(c.DT) do
  mt.dirent.index[k] = function(self) return self.type == v end
end

addtype(types, "dirent", "struct linux_dirent64", mt.dirent)

mt.rtmsg = {
  index = {
    family = function(self) return tonumber(self.rtm_family) end,
  },
  newindex = {
    family = function(self, v) self.rtm_family = c.AF[v] end,
    protocol = function(self, v) self.rtm_protocol = c.RTPROT[v] end,
    type = function(self, v) self.rtm_type = c.RTN[v] end,
    scope = function(self, v) self.rtm_scope = c.RT_SCOPE[v] end,
    flags = function(self, v) self.rtm_flags = c.RTM_F[v] end,
    table = function(self, v) self.rtm_table = c.RT_TABLE[v] end,
    dst_len = function(self, v) self.rtm_dst_len = v end,
    src_len = function(self, v) self.rtm_src_len = v end,
    tos = function(self, v) self.rtm_tos = v end,
  },
  __new = newfn,
}

addtype(types, "rtmsg", "struct rtmsg", mt.rtmsg)

mt.ndmsg = {
  index = {
    family = function(self) return tonumber(self.ndm_family) end,
  },
  newindex = {
    family = function(self, v) self.ndm_family = c.AF[v] end,
    state = function(self, v) self.ndm_state = c.NUD[v] end,
    flags = function(self, v) self.ndm_flags = c.NTF[v] end,
    type = function(self, v) self.ndm_type = v end, -- which lookup?
    ifindex = function(self, v) self.ndm_ifindex = v end,
  },
  __new = newfn,
}

addtype(types, "ndmsg", "struct ndmsg", mt.ndmsg)

mt.sched_param = {
  __new = function(tp, v) -- allow positional parameters as only first is ever used
    local obj = ffi.new(tp)
    obj.sched_priority = v or 0
    return obj
  end,
}

addtype(types, "sched_param", "struct sched_param", mt.sched_param)

mt.flock = {
  index = {
    type = function(self) return self.l_type end,
    whence = function(self) return self.l_whence end,
    start = function(self) return self.l_start end,
    len = function(self) return self.l_len end,
    pid = function(self) return self.l_pid end,
  },
  newindex = {
    type = function(self, v) self.l_type = c.FCNTL_LOCK[v] end,
    whence = function(self, v) self.l_whence = c.SEEK[v] end,
    start = function(self, v) self.l_start = v end,
    len = function(self, v) self.l_len = v end,
    pid = function(self, v) self.l_pid = v end,
  },
  __new = newfn,
}

addtype(types, "flock", "struct flock64", mt.flock)

mt.mmsghdr = {
  index = {
    hdr = function(self) return self.msg_hdr end,
    len = function(self) return self.msg_len end,
  },
  newindex = {
    hdr = function(self, v) self.hdr = v end,
  },
  __new = newfn,
}

addtype(types, "mmsghdr", "struct mmsghdr", mt.mmsghdr)

mt.mmsghdrs = {
  __len = function(p) return p.count end,
  __new = function(tp, ps)
    if type(ps) == 'number' then return ffi.new(tp, ps, ps) end
    local count = #ps
    local mms = ffi.new(tp, count, count)
    for n = 1, count do
      mms.msg[n - 1].msg_hdr = mktype(t.msghdr, ps[n])
    end
    return mms
  end,
  __ipairs = function(p) return reviter, p.msg, p.count end -- TODO want forward iterator really...
}

addtype_var(types, "mmsghdrs", "struct {int count; struct mmsghdr msg[?];}", mt.mmsghdrs)

-- this is declared above
samap_pt = {
  [c.AF.UNIX] = pt.sockaddr_un,
  [c.AF.INET] = pt.sockaddr_in,
  [c.AF.INET6] = pt.sockaddr_in6,
  [c.AF.NETLINK] = pt.sockaddr_nl,
  [c.AF.PACKET] = pt.sockaddr_ll,
}

return types

end

return {init = init}

