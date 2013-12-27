-- BSD shared types

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(c, types)

local abi = require "syscall.abi"

local t, pt, s, ctypes = types.t, types.pt, types.s, types.ctypes

local ffi = require "ffi"
local bit = require "syscall.bit"

local h = require "syscall.helpers"

local addtype, addtype_var, addtype_fn, addraw2 = h.addtype, h.addtype_var, h.addtype_fn, h.addraw2
local ptt, reviter, mktype, istype, lenfn, lenmt, getfd, newfn
  = h.ptt, h.reviter, h.mktype, h.istype, h.lenfn, h.lenmt, h.getfd, h.newfn
local ntohl, ntohl, ntohs, htons = h.ntohl, h.ntohl, h.ntohs, h.htons

local mt = {} -- metatables

local addtypes = {
}

local addstructs = {
}

for k, v in pairs(addtypes) do addtype(types, k, v) end
for k, v in pairs(addstructs) do addtype(types, k, v, lenmt) end

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

addtype(types, "sockaddr_un", "struct sockaddr_un", mt.sockaddr_un)

function t.sa(addr, addrlen) return addr end -- non Linux is trivial, Linux has odd unix handling

-- TODO need to check in detail all this as ported from Linux and may differ
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

addtype(types, "termios", "struct termios", mt.termios)

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

addtype(types, "kevent", "struct kevent", mt.kevent)

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

addtype_var(types, "kevents", "struct {int count; struct kevent kev[?];}", mt.kevents)

return types

end

return {init = init}

