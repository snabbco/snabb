-- OSX types

return function(types, hh, abi, c)

local t, pt, s, ctypes = types.t, types.pt, types.s, types.ctypes

local ptt, addtype, lenfn, lenmt, newfn, istype = hh.ptt, hh.addtype, hh.lenfn, hh.lenmt, hh.newfn, hh.istype

local ffi = require "ffi"
local bit = require "bit"

local h = require "syscall.helpers"

local ntohl, ntohl, ntohs, htons = h.ntohl, h.ntohl, h.ntohs, h.htons

local mt = {} -- metatables
local meth = {}

-- 32 bit dev_t, 24 bit minor, 8 bit major
mt.device = {
  __index = {
    major = function(dev) return bit.bor(bit.band(bit.rshift(dev:device(), 24), 0xff)) end,
    minor = function(dev) return bit.band(dev:device(), 0xffffff) end,
    device = function(dev) return tonumber(dev.dev) end,
  },
}

t.device = function(major, minor)
  local dev = major
  if minor then dev = bit.bor(minor, bit.lshift(major, 24)) end
  return setmetatable({dev = t.dev(dev)}, mt.device)
end

function t.sa(addr, addrlen) return addr end -- non Linux is trivial, Linux has odd unix handling

meth.stat = {
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

    isreg = function(st) return bit.band(st.st_mode, c.S_I.FMT) == c.S_I.FREG end,
    isdir = function(st) return bit.band(st.st_mode, c.S_I.FMT) == c.S_I.FDIR end,
    ischr = function(st) return bit.band(st.st_mode, c.S_I.FMT) == c.S_I.FCHR end,
    isblk = function(st) return bit.band(st.st_mode, c.S_I.FMT) == c.S_I.FBLK end,
    isfifo = function(st) return bit.band(st.st_mode, c.S_I.FMT) == c.S_I.FIFO end,
    islnk = function(st) return bit.band(st.st_mode, c.S_I.FMT) == c.S_I.FLNK end,
    issock = function(st) return bit.band(st.st_mode, c.S_I.FMT) == c.S_I.FSOCK end,
  }
}

addtype("stat", "struct stat", {
  __index = function(st, k) if meth.stat.index[k] then return meth.stat.index[k](st) end end,
  __len = lenfn,
})

meth.siginfo = {
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
}

addtype("siginfo", "siginfo_t", {
  __index = function(t, k) if meth.siginfo.index[k] then return meth.siginfo.index[k](t) end end,
  __newindex = function(t, k, v) if meth.siginfo.newindex[k] then meth.siginfo.newindex[k](t, v) end end,
  __len = lenfn,
})

return types

end

