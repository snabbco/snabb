-- BSD types

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(types, hh, c)

local abi = require "syscall.abi"

local t, pt, s, ctypes = types.t, types.pt, types.s, types.ctypes

local ptt, addtype, addtype_var, addtype_fn, lenmt, newfn, istype, reviter =
  hh.ptt, hh.addtype, hh.addtype_var, hh.addtype_fn, hh.lenmt, hh.newfn, hh.istype, hh.reviter

local ffi = require "ffi"
local bit = require "syscall.bit"

local i6432, u6432 = bit.i6432, bit.u6432

local h = require "syscall.helpers"

local ntohl, ntohl, ntohs, htons, octal = h.ntohl, h.ntohl, h.ntohs, h.htons, h.octal

-- TODO duplicated
local function getfd(fd)
  if type(fd) == "number" or ffi.istype(t.int, fd) then return fd end
  return fd:getfd()
end
local function mktype(tp, x) if ffi.istype(tp, x) then return x else return tp(x) end end

local mt = {} -- metatables

local addtypes = {
  clockid = "clockid_t",
  register = "register_t",
}

local addstructs = {
  ufs_args = "struct ufs_args",
  tmpfs_args = "struct tmpfs_args",
  ptyfs_args = "struct ptyfs_args",
  procfs_args = "struct procfs_args",
  flock = "struct flock",
  statvfs = "struct statvfs",
  kfilter_mapping = "struct kfilter_mapping",
}

if abi.netbsd.version == 6 then
  addstructs.ptmget = "struct compat_60_ptmget"
else
  addstructs.ptmget = "struct ptmget"
end

for k, v in pairs(addtypes) do addtype(k, v) end
for k, v in pairs(addstructs) do addtype(k, v, lenmt) end

-- 64 bit dev_t
local function makedev(major, minor)
  local dev = t.dev(major or 0)
  if minor then
    local low = bit.bor(bit.band(minor, 0xff), bit.lshift(bit.band(major, 0xfff), 8), bit.lshift(bit.band(minor, bit.bnot(0xff)), 12))
    local high = bit.band(major, bit.bnot(0xfff))
    dev = t.dev(low) + 0x100000000ULL * t.dev(high)
  end
  return dev
end

mt.device = {
  index = {
    major = function(dev)
      local dev = dev.dev
      local h, l = i6432(dev)
      return bit.bor(bit.band(bit.rshift(l, 8), 0xfff), bit.band(h, bit.bnot(0xfff)))
    end,
    minor = function(dev)
      local dev = dev.dev
      local h, l = i6432(dev)
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

addtype("device", "struct {dev_t dev;}", mt.device)

mt.sockaddr_un = {
  index = {
    family = function(sa) return sa.sun_family end,
    path = function(sa) return ffi.string(sa.sun_path) end,
  },
  newindex = {
    family = function(sa, v) sa.sun_family = v end,
    path = function(sa, v) ffi.copy(sa.sun_path, v) end,
  },
  __new = function(tp, path) return newfn(tp, {family = c.AF.UNIX, path = path, sun_len = s.sockaddr_un}) end,
  __len = function(sa) return 2 + #sa.path end,
}

addtype("sockaddr_un", "struct sockaddr_un", mt.sockaddr_un)

function t.sa(addr, addrlen) return addr end -- non Linux is trivial, Linux has odd unix handling

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

addtype("stat", "struct stat", mt.stat)

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

addtype("siginfo", "siginfo_t", mt.siginfo)

-- sigaction, standard POSIX behaviour with union of handler and sigaction
addtype_fn("sa_sigaction", "void (*)(int, siginfo_t *, void *)")

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

addtype("sigaction", "struct sigaction", mt.sigaction)

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

addtype("dirent", "struct dirent", mt.dirent)

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

addtype("ifreq", "struct ifreq", mt.ifreq)

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
    addr = function(ifra, v) ifra.ifra_addr = v end, -- TODO type constructor?
    dstaddr = function(ifra, v) ifra.ifra_dstaddr = v end,
    mask = function(ifra, v) ifra.ifra_mask = v end,
  },
  __new = newfn,
}

mt.ifaliasreq.index.broadaddr = mt.ifaliasreq.index.dstaddr
mt.ifaliasreq.newindex.broadaddr = mt.ifaliasreq.newindex.dstaddr

addtype("ifaliasreq", "struct ifaliasreq", mt.ifaliasreq)

-- TODO need to check in detail all this as ported form Linux and may differ
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
    ispeed = function(termios) return termios.c_ispeed end,
    ospeed = function(termios) return termios.c_ospeed end,
  },
  newindex = {
    iflag = function(termios, v) termios.c_iflag = c.IFLAG(v) end,
    oflag = function(termios, v) termios.c_oflag = c.OFLAG(v) end,
    cflag = function(termios, v) termios.c_cflag = c.CFLAG(v) end,
    lflag = function(termios, v) termios.c_lflag = c.LFLAG(v) end,
    ispeed = function(termios, v) termios.c_ispeed = v end,
    ospeed = function(termios, v) termios.c_ospeed = v end,
    speed = function(termios, v)
      termios.c_ispeed = v
      termios.c_ospeed = v
    end,
  },
}

for k, i in pairs(c.CC) do
  mt.termios.index[k] = function(termios) return termios.c_cc[i] end
  mt.termios.newindex[k] = function(termios, v) termios.c_cc[i] = v end
end

addtype("termios", "struct termios", mt.termios)

mt.kevent = {
  index = {
    size = function(kev) return tonumber(kev.data) end,
    fd = function(kev) return tonumber(kev.ident) end,
  },
  newindex = {
    fd = function(kev, v) kev.ident = t.uintptr(getfd(v)) end,
    -- due to naming, use 'set' names TODO better naming scheme reads oddly as not a function
    setflags = function(kev, v) kev.flags = c.EV[v] end,
    setfilter = function(kev, v) kev.filter = c.EVFILT[v] end,
  },
  __new = function(tp, tab)
    if type(tab) == "table" then
      tab.flags = c.EV[tab.flags]
      tab.filter = c.EVFILT[tab.filter] -- TODO this should also support extra ones via ioctl see man page
      tab.fflags = c.NOTE[tab.fflags]
    end
    local obj = ffi.new(tp)
    for k, v in pairs(tab or {}) do obj[k] = v end
    return obj
  end,
}

for k, v in pairs(c.NOTE) do
  mt.kevent.index[k] = function(kev) return bit.band(kev.fflags, v) ~= 0 end
end

for _, k in pairs{"FLAG1", "EOF", "ERROR"} do
  mt.kevent.index[k] = function(kev) return bit.band(kev.flags, c.EV[k]) ~= 0 end
end

addtype("kevent", "struct kevent", mt.kevent)

mt.kevents = {
  __len = function(kk) return kk.count end,
  __new = function(tp, ks)
    if type(ks) == 'number' then return ffi.new(tp, ks, ks) end
    local count = #ks
    local kks = ffi.new(tp, count, count)
    for n = 1, count do -- TODO ideally we use ipairs on both arrays/tables
      local v = mktype(t.kevent, ks[n])
      kks.kev[n - 1] = v
    end
    return kks
  end,
  __ipairs = function(kk) return reviter, kk.kev, kk.count end
}

addtype_var("kevents", "struct {int count; struct kevent kev[?];}", mt.kevents)

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
  __len = function(ktr) return s.ktr_header + ktr.len end
}

addtype("ktr_header", "struct ktr_header", mt.ktr_header)

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

addtype("ktr_syscall", "struct ktr_syscall", mt.ktr_syscall)

mt.ktr_sysret = {
  index = {
    code = function(ktr) return ktr.ktr_code end,
    name = function(ktr) return sysname[ktr.code] or tostring(ktr.code) end,
    error = function(ktr) return t.error(ktr.ktr_error) end,
    retval = function(ktr) return ktr.ktr_retval end,
    retval1 = function(ktr) return ktr.ktr_retval1 end,
  },
  __tostring = function(ktr)
    if ktr.retval == -1 then
      return ktr.name .. " " .. tostring(ktr.retval) .. " " .. ktr.error.sym .. " " .. tostring(ktr.error)
    else
      return ktr.name .. " " .. tostring(ktr.retval) -- and second one if applicable for code
    end
  end
}

addtype("ktr_sysret", "struct ktr_sysret", mt.ktr_sysret)

mt.ktr_csw = {
  __tostring = function(ktr)
    return "context switch" -- TODO
  end,
}

addtype("ktr_csw", "struct ktr_csw", mt.ktr_csw)

-- slightly miscellaneous types, eg need to use Lua metatables

-- TODO see Linux notes
mt.wait = { -- TODO port to NetBSD
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

return types

end

return {init = init}

