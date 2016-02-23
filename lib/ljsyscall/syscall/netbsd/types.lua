-- NetBSD types

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(types)

local abi = require "syscall.abi"

local version = require "syscall.netbsd.version".version

local t, pt, s, ctypes = types.t, types.pt, types.s, types.ctypes

local ffi = require "ffi"
local bit = require "syscall.bit"

local i6432, u6432 = bit.i6432, bit.u6432

local h = require "syscall.helpers"

local addtype, addtype_var, addtype_fn, addraw2 = h.addtype, h.addtype_var, h.addtype_fn, h.addraw2
local ptt, reviter, mktype, istype, lenfn, lenmt, getfd, newfn
  = h.ptt, h.reviter, h.mktype, h.istype, h.lenfn, h.lenmt, h.getfd, h.newfn
local ntohl, ntohl, ntohs, htons, octal = h.ntohl, h.ntohl, h.ntohs, h.htons, h.octal

local c = require "syscall.netbsd.constants"

local mt = {} -- metatables

local addtypes = {
  fdset = "fd_set",
  clockid = "clockid_t",
  register = "register_t",
  lwpid = "lwpid_t",
}

local addstructs = {
  ufs_args = "struct ufs_args",
  tmpfs_args = "struct tmpfs_args",
  ptyfs_args = "struct ptyfs_args",
  procfs_args = "struct procfs_args",
  statvfs = "struct statvfs",
  kfilter_mapping = "struct kfilter_mapping",
  in6_ifstat = "struct in6_ifstat",
  icmp6_ifstat = "struct icmp6_ifstat",
  in6_ifreq = "struct in6_ifreq",
  in6_addrlifetime = "struct in6_addrlifetime",
}

if version == 6 then
  addstructs.ptmget = "struct compat_60_ptmget"
else
  addstructs.ptmget = "struct ptmget"
end

for k, v in pairs(addtypes) do addtype(types, k, v) end
for k, v in pairs(addstructs) do addtype(types, k, v, lenmt) end

-- 64 bit dev_t
local function makedev(major, minor)
  if type(major) == "table" then major, minor = major[1], major[2] end
  local dev = t.dev(major or 0)
  if minor then
    local low = bit.bor(bit.band(minor, 0xff), bit.lshift(bit.band(major, 0xfff), 8), bit.lshift(bit.band(minor, bit.bnot(0xff)), 12))
    local high = bit.band(major, bit.bnot(0xfff))
    dev = t.dev(low) + 0x100000000 * t.dev(high)
  end
  return dev
end

mt.device = {
  index = {
    major = function(dev)
      local h, l = i6432(dev.dev)
      return bit.bor(bit.band(bit.rshift(l, 8), 0xfff), bit.band(h, bit.bnot(0xfff)))
    end,
    minor = function(dev)
      local h, l = i6432(dev.dev)
      return bit.bor(bit.band(l, 0xff), bit.band(bit.rshift(l, 12), bit.bnot(0xff)))
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

mt.stat = {
  index = {
    dev = function(st) return t.device(st.st_dev) end,
    mode = function(st) return st.st_mode end,
    ino = function(st) return tonumber(st.st_ino) end,
    nlink = function(st) return st.st_nlink end,
    uid = function(st) return st.st_uid end,
    gid = function(st) return st.st_gid end,
    rdev = function(st) return t.device(st.st_rdev) end,
    atime = function(st) return st.st_atimespec.time end,
    ctime = function(st) return st.st_ctimespec.time end,
    mtime = function(st) return st.st_mtimespec.time end,
    birthtime = function(st) return st.st_birthtimespec.time end,
    size = function(st) return tonumber(st.st_size) end,
    blocks = function(st) return tonumber(st.st_blocks) end,
    blksize = function(st) return tonumber(st.st_blksize) end,
    flags = function(st) return st.st_flags end,
    gen = function(st) return st.st_gen end,

    type = function(st) return bit.band(st.st_mode, c.S_I.FMT) end,
    todt = function(st) return bit.rshift(st.type, 12) end,
    isreg = function(st) return st.type == c.S_I.FREG end, -- TODO allow upper case too?
    isdir = function(st) return st.type == c.S_I.FDIR end,
    ischr = function(st) return st.type == c.S_I.FCHR end,
    isblk = function(st) return st.type == c.S_I.FBLK end,
    isfifo = function(st) return st.type == c.S_I.FIFO end,
    islnk = function(st) return st.type == c.S_I.FLNK end,
    issock = function(st) return st.type == c.S_I.FSOCK end,
    iswht = function(st) return st.type == c.S_I.FWHT end,
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

local signames = {}
local duplicates = {IOT = true}
for k, v in pairs(c.SIG) do
  if not duplicates[k] then signames[v] = k end
end

-- TODO see note in Linux, we should be consistently using the correct union
mt.siginfo = {
  index = {
    signo   = function(s) return s._info._signo end,
    code    = function(s) return s._info._code end,
    errno   = function(s) return s._info._errno end,
    value   = function(s) return s._info._reason._rt._value end,
    pid     = function(s) return s._info._reason._child._pid end,
    uid     = function(s) return s._info._reason._child._uid end,
    status  = function(s) return s._info._reason._child._status end,
    utime   = function(s) return s._info._reason._child._utime end,
    stime   = function(s) return s._info._reason._child._stime end,
    addr    = function(s) return s._info._reason._fault._addr end,
    band    = function(s) return s._info._reason._poll._band end,
    fd      = function(s) return s._info._reason._poll._fd end,
    signame = function(s) return signames[s.signo] end,
  },
  newindex = {
    signo   = function(s, v) s._info._signo = v end,
    code    = function(s, v) s._info._code = v end,
    errno   = function(s, v) s._info._errno = v end,
    value   = function(s, v) s._info._reason._rt._value = v end,
    pid     = function(s, v) s._info._reason._child._pid = v end,
    uid     = function(s, v) s._info._reason._child._uid = v end,
    status  = function(s, v) s._info._reason._child._status = v end,
    utime   = function(s, v) s._info._reason._child._utime = v end,
    stime   = function(s, v) s._info._reason._child._stime = v end,
    addr    = function(s, v) s._info._reason._fault._addr = v end,
    band    = function(s, v) s._info._reason._poll._band = v end,
    fd      = function(s, v) s._info._reason._poll._fd = v end,
  },
}

addtype(types, "siginfo", "siginfo_t", mt.siginfo)

-- sigaction, standard POSIX behaviour with union of handler and sigaction
addtype_fn(types, "sa_sigaction", "void (*)(int, siginfo_t *, void *)")

mt.sigaction = {
  index = {
    handler = function(sa) return sa._sa_u._sa_handler end,
    sigaction = function(sa) return sa._sa_u._sa_sigaction end,
    mask = function(sa) return sa.sa_mask end,
    flags = function(sa) return tonumber(sa.sa_flags) end,
  },
  newindex = {
    handler = function(sa, v)
      if type(v) == "string" then v = pt.void(c.SIGACT[v]) end
      if type(v) == "number" then v = pt.void(v) end
      sa._sa_u._sa_handler = v
    end,
    sigaction = function(sa, v)
      if type(v) == "string" then v = pt.void(c.SIGACT[v]) end
      if type(v) == "number" then v = pt.void(v) end
      sa._sa_u._sa_sigaction = v
    end,
    mask = function(sa, v)
      if not ffi.istype(t.sigset, v) then v = t.sigset(v) end
      sa.sa_mask = v
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

addtype(types, "sigaction", "struct sigaction", mt.sigaction)

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

mt.dirent = {
  index = {
    fileno = function(self) return tonumber(self.d_fileno) end,
    reclen = function(self) return self.d_reclen end,
    namlen = function(self) return self.d_namlen end,
    type = function(self) return self.d_type end,
    name = function(self) return ffi.string(self.d_name, self.d_namlen) end,
    toif = function(self) return bit.lshift(self.d_type, 12) end, -- convert to stat types
  },
  __len = function(self) return self.d_reclen end,
}

mt.dirent.index.ino = mt.dirent.index.fileno -- alternate name

-- TODO previously this allowed lower case values, but this static version does not
-- could add mt.dirent.index[tolower(k)] = mt.dirent.index[k] but need to do consistently elsewhere
for k, v in pairs(c.DT) do
  mt.dirent.index[k] = function(self) return self.type == v end
end

addtype(types, "dirent", "struct dirent", mt.dirent)

mt.ifreq = {
  index = {
    name = function(ifr) return ffi.string(ifr.ifr_name) end,
    addr = function(ifr) return ifr.ifr_ifru.ifru_addr end,
    dstaddr = function(ifr) return ifr.ifr_ifru.ifru_dstaddr end,
    broadaddr = function(ifr) return ifr.ifr_ifru.ifru_broadaddr end,
    space = function(ifr) return ifr.ifr_ifru.ifru_space end,
    flags = function(ifr) return ifr.ifr_ifru.ifru_flags end,
    metric = function(ifr) return ifr.ifr_ifru.ifru_metric end,
    mtu = function(ifr) return ifr.ifr_ifru.ifru_mtu end,
    dlt = function(ifr) return ifr.ifr_ifru.ifru_dlt end,
    value = function(ifr) return ifr.ifr_ifru.ifru_value end,
    -- TODO rest of fields (buf, buflen)
  },
  newindex = {
    name = function(ifr, v)
      assert(#v < c.IFNAMSIZ, "name too long")
      ifr.ifr_name = v
    end,
    flags = function(ifr, v)
      ifr.ifr_ifru.ifru_flags = c.IFF[v]
    end,
    -- TODO rest of fields
  },
  __new = newfn,
}

addtype(types, "ifreq", "struct ifreq", mt.ifreq)

-- ifaliasreq takes sockaddr, but often want to supply in_addr as port irrelevant
-- TODO want to return a sockaddr so can asign vs ffi.copy below, or fix sockaddr to be more like sockaddr_storage
local function tosockaddr(v)
  if ffi.istype(t.in_addr, v) then return t.sockaddr_in(0, v) end
  if ffi.istype(t.in6_addr, v) then return t.sockaddr_in6(0, v) end
  return mktype(t.sockaddr, v)
end

mt.ifaliasreq = {
  index = {
    name = function(ifra) return ffi.string(ifra.ifra_name) end,
    addr = function(ifra) return ifra.ifra_addr end,
    dstaddr = function(ifra) return ifra.ifra_dstaddr end,
    mask = function(ifra) return ifra.ifra_mask end,
  },
  newindex = {
    name = function(ifra, v)
      assert(#v < c.IFNAMSIZ, "name too long")
      ifra.ifra_name = v
    end,
    addr = function(ifra, v)
      local addr = tosockaddr(v)
      ffi.copy(ifra.ifra_addr, addr, #addr)
    end,
    dstaddr = function(ifra, v)
      local addr = tosockaddr(v)
      ffi.copy(ifra.ifra_dstaddr, addr, #addr)
    end,
    mask = function(ifra, v)
      local addr = tosockaddr(v)
      ffi.copy(ifra.ifra_mask, addr, #addr)
    end,
  },
  __new = newfn,
}

mt.ifaliasreq.index.broadaddr = mt.ifaliasreq.index.dstaddr
mt.ifaliasreq.newindex.broadaddr = mt.ifaliasreq.newindex.dstaddr

addtype(types, "ifaliasreq", "struct ifaliasreq", mt.ifaliasreq)

mt.in6_aliasreq = {
  index = {
    name = function(ifra) return ffi.string(ifra.ifra_name) end,
    addr = function(ifra) return ifra.ifra_addr end,
    dstaddr = function(ifra) return ifra.ifra_dstaddr end,
    prefixmask = function(ifra) return ifra.ifra_prefixmask end,
    lifetime = function(ifra) return ifra.ifra_lifetime end,
  },
  newindex = {
    name = function(ifra, v)
      assert(#v < c.IFNAMSIZ, "name too long")
      ifra.ifra_name = v
    end,
    addr = function(ifra, v)
      local addr = tosockaddr(v)
      ffi.copy(ifra.ifra_addr, addr, #addr)
    end,
    dstaddr = function(ifra, v)
      local addr = tosockaddr(v)
      ffi.copy(ifra.ifra_dstaddr, addr, #addr)
    end,
    prefixmask = function(ifra, v)
      local addr = tosockaddr(v)
      ffi.copy(ifra.ifra_prefixmask, addr, #addr)
    end,
    lifetime = function(ifra, v) ifra.ifra_lifetime = mktype(t.in6_addrlifetime, v) end,
  },
  __new = newfn,
}

addtype(types, "in6_aliasreq", "struct in6_aliasreq", mt.in6_aliasreq)

mt.in6_addrlifetime = {
  index = {
    expire = function(self) return self.ia6t_expire end,
    preferred = function(self) return self.ia6t_preferred end,
    vltime = function(self) return self.ia6t_vltime end,
    pltime = function(self) return self.ia6t_pltime end,
  },
  newindex = {
    expire = function(self, v) self.ia6t_expire = mktype(t.time, v) end,
    preferred = function(self, v) self.ia6t_preferred = mktype(t.time, v) end,
    vltime = function(self, v) self.ia6t_vltime = c.ND6[v] end,
    pltime = function(self, v) self.ia6t_pltime = c.ND6[v] end,
  },
  __new = newfn,
}

local ktr_type = {}
for k, v in pairs(c.KTR) do ktr_type[v] = k end

local ktr_val_tp = {
  SYSCALL = "ktr_syscall",
  SYSRET = "ktr_sysret",
  NAMEI = "string",
  -- TODO GENIO
  -- TODO PSIG
  CSW = "ktr_csw",
  EMUL = "string",
  -- TODO USER
  EXEC_ARG = "string",
  EXEC_ENV = "string",
  -- TODO SAUPCALL
  MIB = "string",
  -- TODO EXEC_FD
}

mt.ktr_header = {
  index = {
    len = function(ktr) return ktr.ktr_len end,
    version = function(ktr) return ktr.ktr_version end,
    type = function(ktr) return ktr.ktr_type end,
    typename = function(ktr) return ktr_type[ktr.ktr_type] end,
    pid = function(ktr) return ktr.ktr_pid end,
    comm = function(ktr) return ffi.string(ktr.ktr_comm) end,
    lid = function(ktr) return ktr._v._v2._lid end,
    olid = function(ktr) return ktr._v._v1._lid end,
    time = function(ktr) return ktr._v._v2._ts end,
    otv = function(ktr) return ktr._v._v0._tv end,
    ots = function(ktr) return ktr._v._v1._ts end,
    unused = function(ktr) return ktr._v._v0._buf end,
    valptr = function(ktr) return pt.char(ktr) + s.ktr_header end, -- assumes ktr is a pointer
    values = function(ktr)
      if not ktr.typename then return "bad ktrace type" end
      local tpnam = ktr_val_tp[ktr.typename]
      if not tpnam then return "unimplemented ktrace type" end
      if tpnam == "string" then return ffi.string(ktr.valptr, ktr.len) end
      return pt[tpnam](ktr.valptr)
    end,
  },
  __len = function(ktr) return s.ktr_header + ktr.len end,
  __tostring = function(ktr)
    return ktr.pid .. " " .. ktr.comm .. " " .. (ktr.typename or "??") .. " " .. tostring(ktr.values)
  end,
}

addtype(types, "ktr_header", "struct ktr_header", mt.ktr_header)

local sysname = {}
for k, v in pairs(c.SYS) do sysname[v] = k end

local ioctlname

-- TODO this is a temporary hack, needs better code
local special = {
  ioctl = function(fd, request, val)
    if not ioctlname then
      ioctlname = {}
      local IOCTL = require "syscall.netbsd.constants".IOCTL -- see #94 as well, we cannot load early as ioctl depends on types
      for k, v in pairs(IOCTL) do
        if type(v) == "table" then v = v.number end
        v = tonumber(v)
        if v then ioctlname[v] = k end
      end
    end
    fd = tonumber(t.int(fd))
    request = tonumber(t.int(request))
    val = tonumber(val)
    local ionm = ioctlname[request] or tostring(request)
    return tostring(fd) .. ", " .. ionm .. ", " .. tostring(val)
  end,
}

mt.ktr_syscall = {
  index = {
    code = function(ktr) return ktr.ktr_code end,
    name = function(ktr) return sysname[ktr.code] or tostring(ktr.code) end,
    argsize = function(ktr) return ktr.ktr_argsize end,
    nreg = function(ktr) return ktr.argsize / s.register end,
    registers = function(ktr) return pt.register(pt.char(ktr) + s.ktr_syscall) end -- assumes ktr is a pointer
  },
  __len = function(ktr) return s.ktr_syscall + ktr.argsize end,
  __tostring = function(ktr)
    local rtab = {}
    for i = 0, ktr.nreg - 1 do rtab[i + 1] = tostring(ktr.registers[i]) end
    if special[ktr.name] then
      for i = 0, ktr.nreg - 1 do rtab[i + 1] = ktr.registers[i] end
      return ktr.name .. " (" .. special[ktr.name](unpack(rtab)) .. ")"
    end
    for i = 0, ktr.nreg - 1 do rtab[i + 1] = tostring(ktr.registers[i]) end
    return ktr.name .. " (" .. table.concat(rtab, ",") .. ")"
  end,
}

addtype(types, "ktr_syscall", "struct ktr_syscall", mt.ktr_syscall)

mt.ktr_sysret = {
  index = {
    code = function(ktr) return ktr.ktr_code end,
    name = function(ktr) return sysname[ktr.code] or tostring(ktr.code) end,
    error = function(ktr) if ktr.ktr_error ~= 0 then return t.error(ktr.ktr_error) end end,
    retval = function(ktr) return ktr.ktr_retval end,
    retval1 = function(ktr) return ktr.ktr_retval_1 end,
  },
  __tostring = function(ktr)
    if ktr.error then
      return ktr.name .. " " .. (ktr.error.sym or ktr.error.errno) .. " " .. (tostring(ktr.error) or "")
    else
      return ktr.name .. " " .. tostring(ktr.retval) .. " " .. tostring(ktr.retval1) .. " "
    end
  end
}

addtype(types, "ktr_sysret", "struct ktr_sysret", mt.ktr_sysret)

mt.ktr_csw = {
  __tostring = function(ktr)
    return "context switch" -- TODO
  end,
}

addtype(types, "ktr_csw", "struct ktr_csw", mt.ktr_csw)

-- slightly miscellaneous types, eg need to use Lua metatables

-- TODO see Linux notes
mt.wait = {
  __index = function(w, k)
    local _WSTATUS = bit.band(w.status, octal("0177"))
    local _WSTOPPED = octal("0177")
    local WTERMSIG = _WSTATUS
    local EXITSTATUS = bit.band(bit.rshift(w.status, 8), 0xff)
    local WIFEXITED = (_WSTATUS == 0)
    local tab = {
      WIFEXITED = WIFEXITED,
      WIFSTOPPED = bit.band(w.status, 0xff) == _WSTOPPED,
      WIFSIGNALED = _WSTATUS ~= _WSTOPPED and _WSTATUS ~= 0
    }
    if tab.WIFEXITED then tab.EXITSTATUS = EXITSTATUS end
    if tab.WIFSTOPPED then tab.WSTOPSIG = EXITSTATUS end
    if tab.WIFSIGNALED then tab.WTERMSIG = WTERMSIG end
    if tab[k] then return tab[k] end
    local uc = 'W' .. k:upper()
    if tab[uc] then return tab[uc] end
  end
}

function t.waitstatus(status)
  return setmetatable({status = status}, mt.wait)
end

mt.ifdrv = {
  index = {
    name = function(self) return ffi.string(self.ifd_name) end,
  },
  newindex = {
    name = function(self, v)
      assert(#v < c.IFNAMSIZ, "name too long")
      self.ifd_name = v
    end,
    cmd = function(self, v) self.ifd_cmd = v end, -- TODO which namespace(s)?
    data = function(self, v)
      self.ifd_data = v
      self.ifd_len = #v
    end,
    len = function(self, v) self.ifd_len = v end,
  },
  __new = newfn,
}

addtype(types, "ifdrv", "struct ifdrv", mt.ifdrv)

mt.ifbreq = {
  index = {
    ifsname = function(self) return ffi.string(self.ifbr_ifsname) end,
  },
  newindex = {
    ifsname = function(self, v)
      assert(#v < c.IFNAMSIZ, "name too long")
      self.ifbr_ifsname = v
    end,
  },
  __new = newfn,
}

addtype(types, "ifbreq", "struct ifbreq", mt.ifbreq)

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

addtype(types, "flock", "struct flock", mt.flock)

mt.clockinfo = {
  print = {"tick", "tickadj", "hz", "profhz", "stathz"},
  __new = newfn,
}

addtype(types, "clockinfo", "struct clockinfo", mt.clockinfo)

mt.loadavg = {
  index = {
    loadavg = function(self) return {tonumber(self.ldavg[0]) / tonumber(self.fscale),
                                     tonumber(self.ldavg[1]) / tonumber(self.fscale),
                                     tonumber(self.ldavg[2]) / tonumber(self.fscale)}
    end,
  },
  __tostring = function(self)
    local loadavg = self.loadavg
    return string.format("{ %.2f, %.2f, %.2f }", loadavg[1], loadavg[2], loadavg[3])
  end,
}

addtype(types, "loadavg", "struct loadavg", mt.loadavg)

mt.vmtotal = {
  index = {
    rq = function(self) return self.t_rq end,
    dw = function(self) return self.t_dw end,
    pw = function(self) return self.t_pw end,
    sl = function(self) return self.t_sl end,
    vm = function(self) return self.t_vm end,
    avm = function(self) return self.t_avm end,
    rm = function(self) return self.t_rm end,
    arm = function(self) return self.t_arm end,
    vmshr= function(self) return self.t_vmshr end,
    avmshr= function(self) return self.t_avmshr end,
    rmshr = function(self) return self.t_rmshr end,
    armshr = function(self) return self.t_armshr end,
    free = function(self) return self.t_free end,
  },
  print = {"rq", "dw", "pw", "sl", "vm", "avm", "rm", "arm", "vmshr", "avmshr", "rmshr", "armshr", "free"},
}

addtype(types, "vmtotal", "struct vmtotal", mt.vmtotal)

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

return types

end

return {init = init}

