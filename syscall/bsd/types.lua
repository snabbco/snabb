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

mt.sockaddr = {
  index = {
    len = function(sa) return sa.sa_len end,
    family = function(sa) return sa.sa_family end,
  },
  newindex = {
    len = function(sa, v) sa.sa_len = v end,
  },
}

addtype(types, "sockaddr", "struct sockaddr", mt.sockaddr)

-- cast socket address to actual type based on family, defined later
local samap_pt = {}

mt.sockaddr_storage = {
  index = {
    len = function(sa) return sa.ss_len end,
    family = function(sa) return sa.ss_family end,
  },
  newindex = {
    len = function(sa, v) sa.ss_len = v end,
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
    ss.len = #ss
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
    len = function(sa) return sa.sin_len end,
    family = function(sa) return sa.sin_family end,
    port = function(sa) return ntohs(sa.sin_port) end,
    addr = function(sa) return sa.sin_addr end,
  },
  newindex = {
    len = function(sa, v) sa.sin_len = v end,
    family = function(sa, v) sa.sin_family = v end,
    port = function(sa, v) sa.sin_port = htons(v) end,
    addr = function(sa, v) sa.sin_addr = mktype(t.in_addr, v) end,
  },
  __new = function(tp, port, addr)
    if type(port) == "table" then
      port.len = s.sockaddr_in
      return newfn(tp, port)
    end
   return newfn(tp, {len = s.sockaddr_in, family = c.AF.INET, port = port, addr = addr})
  end,
  __len = function(tp) return s.sockaddr_in end,
}

addtype(types, "sockaddr_in", "struct sockaddr_in", mt.sockaddr_in)

mt.sockaddr_in6 = {
  index = {
    len = function(sa) return sa.sin6_len end,
    family = function(sa) return sa.sin6_family end,
    port = function(sa) return ntohs(sa.sin6_port) end,
    addr = function(sa) return sa.sin6_addr end,
  },
  newindex = {
    len = function(sa, v) sa.sin6_len = v end,
    family = function(sa, v) sa.sin6_family = v end,
    port = function(sa, v) sa.sin6_port = htons(v) end,
    addr = function(sa, v) sa.sin6_addr = mktype(t.in6_addr, v) end,
    flowinfo = function(sa, v) sa.sin6_flowinfo = v end,
    scope_id = function(sa, v) sa.sin6_scope_id = v end,
  },
  __new = function(tp, port, addr, flowinfo, scope_id) -- reordered initialisers.
    if type(port) == "table" then
      port.len = s.sockaddr_in6
      return newfn(tp, port)
    end
    return newfn(tp, {len = s.sockaddr_in6, family = c.AF.INET6, port = port, addr = addr, flowinfo = flowinfo, scope_id = scope_id})
  end,
  __len = function(tp) return s.sockaddr_in6 end,
}

addtype(types, "sockaddr_in6", "struct sockaddr_in6", mt.sockaddr_in6)

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
    termios.c_iflag = bit.band(termios.iflag, bit.bnot(c.IFLAG["IGNBRK,BRKINT,PARMRK,ISTRIP,INLCR,IGNCR,ICRNL,IXON"]))
    termios.c_oflag = bit.band(termios.oflag, bit.bnot(c.OFLAG["OPOST"]))
    termios.c_lflag = bit.band(termios.lflag, bit.bnot(c.LFLAG["ECHO,ECHONL,ICANON,ISIG,IEXTEN"]))
    termios.c_cflag = bit.bor(bit.band(termios.cflag, bit.bnot(c.CFLAG["CSIZE,PARENB"])), c.CFLAG.CS8)
    termios.c_cc[c.CC.VMIN] = 1
    termios.c_cc[c.CC.VTIME] = 0
    return true
  end,
  index = {
    iflag = function(termios) return tonumber(termios.c_iflag) end,
    oflag = function(termios) return tonumber(termios.c_oflag) end,
    cflag = function(termios) return tonumber(termios.c_cflag) end,
    lflag = function(termios) return tonumber(termios.c_lflag) end,
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
    signal = function(kev) return tonumber(kev.ident) end,
  },
  newindex = {
    fd = function(kev, v) kev.ident = t.uintptr(getfd(v)) end,
    signal = function(kev, v) kev.ident = c.SIG[v] end,
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

-- this is declared above
samap_pt = {
  [c.AF.UNIX] = pt.sockaddr_un,
  [c.AF.INET] = pt.sockaddr_in,
  [c.AF.INET6] = pt.sockaddr_in6,
}

return types

end

return {init = init}

