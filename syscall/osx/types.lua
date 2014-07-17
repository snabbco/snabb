-- OSX types

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(types)

local abi = require "syscall.abi"

local t, pt, s, ctypes = types.t, types.pt, types.s, types.ctypes

local ffi = require "ffi"
local bit = require "syscall.bit"

local h = require "syscall.helpers"

local addtype, addtype_var, addtype_fn, addraw2 = h.addtype, h.addtype_var, h.addtype_fn, h.addraw2
local ptt, reviter, mktype, istype, lenfn, lenmt, getfd, newfn
  = h.ptt, h.reviter, h.mktype, h.istype, h.lenfn, h.lenmt, h.getfd, h.newfn
local ntohl, ntohl, ntohs, htons, octal = h.ntohl, h.ntohl, h.ntohs, h.htons, h.octal

local c = require "syscall.osx.constants"

local mt = {} -- metatables

local addtypes = {
  fdset = "fd_set",
  clock_serv = "clock_serv_t",
}

local addstructs = {
  mach_timespec = "struct mach_timespec",
}

for k, v in pairs(addtypes) do addtype(types, k, v) end
for k, v in pairs(addstructs) do addtype(types, k, v, lenmt) end

t.clock_serv1 = ffi.typeof("clock_serv_t[1]")

-- 32 bit dev_t, 24 bit minor, 8 bit major
local function makedev(major, minor)
  if type(major) == "table" then major, minor = major[1], major[2] end
  local dev = major or 0
  if minor then dev = bit.bor(minor, bit.lshift(major, 24)) end
  return dev
end

mt.device = {
  index = {
    major = function(dev) return bit.bor(bit.band(bit.rshift(dev.dev, 24), 0xff)) end,
    minor = function(dev) return bit.band(dev.dev, 0xffffff) end,
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

mt.siginfo = {
  index = {
    signo   = function(s) return s.si_signo end,
    errno   = function(s) return s.si_errno end,
    code    = function(s) return s.si_code end,
    pid     = function(s) return s.si_pid end,
    uid     = function(s) return s.si_uid end,
    status  = function(s) return s.si_status end,
    addr    = function(s) return s.si_addr end,
    value   = function(s) return s.si_value end,
    band    = function(s) return s.si_band end,
  },
  newindex = {
    signo   = function(s, v) s.si_signo = v end,
    errno   = function(s, v) s.si_errno = v end,
    code    = function(s, v) s.si_code = v end,
    pid     = function(s, v) s.si_pid = v end,
    uid     = function(s, v) s.si_uid = v end,
    status  = function(s, v) s.si_status = v end,
    addr    = function(s, v) s.si_addr = v end,
    value   = function(s, v) s.si_value = v end,
    band    = function(s, v) s.si_band = v end,
  },
  __len = lenfn,
}

addtype(types, "siginfo", "siginfo_t", mt.siginfo)

mt.dirent = {
  index = {
    ino = function(self) return self.d_ino end,
    --seekoff = function(self) return self.d_seekoff end, -- not in legacy dirent
    reclen = function(self) return self.d_reclen end,
    namlen = function(self) return self.d_namlen end,
    type = function(self) return self.d_type end,
    name = function(self) return ffi.string(self.d_name, self.d_namlen) end,
    toif = function(self) return bit.lshift(self.d_type, 12) end, -- convert to stat types
  },
  __len = function(self) return self.d_reclen end,
}

for k, v in pairs(c.DT) do
  mt.dirent.index[k] = function(self) return self.type == v end
end

addtype(types, "dirent", "struct legacy_dirent", mt.dirent)

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

-- TODO see Linux notes. Also maybe can be shared with BSDs, have not checked properly
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

-- sigaction, standard POSIX behaviour with union of handler and sigaction
addtype_fn(types, "sa_sigaction", "void (*)(int, siginfo_t *, void *)")

mt.sigaction = {
  index = {
    handler = function(sa) return sa.__sigaction_u.__sa_handler end,
    sigaction = function(sa) return sa.__sigaction_u.__sa_sigaction end,
    mask = function(sa) return sa.sa_mask end,
    flags = function(sa) return tonumber(sa.sa_flags) end,
  },
  newindex = {
    handler = function(sa, v)
      if type(v) == "string" then v = pt.void(c.SIGACT[v]) end
      if type(v) == "number" then v = pt.void(v) end
      sa.__sigaction_u.__sa_handler = v
    end,
    sigaction = function(sa, v)
      if type(v) == "string" then v = pt.void(c.SIGACT[v]) end
      if type(v) == "number" then v = pt.void(v) end
      sa.__sigaction_u.__sa_sigaction = v
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

return types

end

return {init = init}

