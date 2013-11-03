-- OSX types

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(types, hh, abi, c)

local t, pt, s, ctypes = types.t, types.pt, types.s, types.ctypes

local ptt, addtype, lenfn, lenmt, newfn, istype = hh.ptt, hh.addtype, hh.lenfn, hh.lenmt, hh.newfn, hh.istype

local ffi = require "ffi"
local bit = require "syscall.bit"

local h = require "syscall.helpers"

local ntohl, ntohl, ntohs, htons = h.ntohl, h.ntohl, h.ntohs, h.htons

local mt = {} -- metatables

-- 32 bit dev_t, 24 bit minor, 8 bit major
local function makedev(major, minor)
  local dev = major or 0
  if minor then dev = bit.bor(minor, bit.lshift(major, 24)) end
  return dev
end

mt.device = {
  index = {
    major = function(dev) return bit.bor(bit.band(bit.rshift(dev:device(), 24), 0xff)) end,
    minor = function(dev) return bit.band(dev:device(), 0xffffff) end,
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

addtype("stat", "struct stat", mt.stat)

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

addtype("siginfo", "siginfo_t", mt.siginfo)

mt.dirent = {
  index = {
    ino = function(self) return self.d_ino end,
    seekoff = function(self) return self.d_seekoff end,
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

addtype("dirent", "struct dirent", mt.dirent)

return types

end

return {init = init}

