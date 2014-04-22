-- FreeBSD types

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

local c = require "syscall.freebsd.constants"

local mt = {} -- metatables

local addtypes = {
}

local addstructs = {
  fiodgname_arg = "struct fiodgname_arg",
}

for k, v in pairs(addtypes) do addtype(types, k, v) end
for k, v in pairs(addstructs) do addtype(types, k, v, lenmt) end

-- 32 bit dev_t, 24 bit minor, 8 bit major, but minor is a cookie and neither really used just legacy
local function makedev(major, minor)
  if type(major) == "table" then major, minor = major[1], major[2] end
  local dev = major or 0
  if minor then dev = bit.bor(minor, bit.lshift(major, 8)) end
  return dev
end

mt.device = {
  index = {
    major = function(dev) return bit.bor(bit.band(bit.rshift(dev.dev, 8), 0xff)) end,
    minor = function(dev) return bit.band(dev.dev, 0xffff00ff) end,
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
    atime = function(st) return st.st_atim.time end,
    ctime = function(st) return st.st_ctim.time end,
    mtime = function(st) return st.st_mtim.time end,
    birthtime = function(st) return st.st_birthtim.time end,
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

mt.flock = {
  index = {
    type = function(self) return self.l_type end,
    whence = function(self) return self.l_whence end,
    start = function(self) return self.l_start end,
    len = function(self) return self.l_len end,
    pid = function(self) return self.l_pid end,
    sysid = function(self) return self.l_sysid end,
  },
  newindex = {
    type = function(self, v) self.l_type = c.FCNTL_LOCK[v] end,
    whence = function(self, v) self.l_whence = c.SEEK[v] end,
    start = function(self, v) self.l_start = v end,
    len = function(self, v) self.l_len = v end,
    pid = function(self, v) self.l_pid = v end,
    sysid = function(self, v) self.l_sysid = v end,
  },
  __new = newfn,
}

addtype(types, "flock", "struct flock", mt.flock)

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

mt.fdset = {
  index = {
    fds_bits = function(self) return self.__fds_bits end,
  },
}

addtype(types, "fdset", "fd_set", mt.fdset)

mt.cap_rights = {
  -- TODO
}

addtype(types, "cap_rights", "cap_rights_t", mt.cap_rights)

-- TODO see Linux notes. Also maybe can be shared with BSDs, have not checked properly
-- TODO also remove WIF prefixes.
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
    trapno  = function(s) return s._fault._trapno end,
    timerid = function(s) return s._timer._timerid end,
    overrun = function(s) return s._timer._overrun end,
    mqd     = function(s) return s._mesgq._mqd end,
    band    = function(s) return s._poll._band end,
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
    trapno  = function(s, v) s._fault._trapno = v end,
    timerid = function(s, v) s._timer._timerid = v end,
    overrun = function(s, v) s._timer._overrun = v end,
    mqd     = function(s, v) s._mesgq._mqd = v end,
    band    = function(s, v) s._poll._band = v end,
  },
  __len = lenfn,
}

addtype(types, "siginfo", "siginfo_t", mt.siginfo)

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

return types

end

return {init = init}

