-- choose correct types for OS

-- these are either simple ffi types or ffi metatypes for the kernel types
-- plus some Lua metatables for types that cannot be sensibly done as Lua types eg arrays, integers

-- note that some types will be overridden, eg default fd type will have metamethods added

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math

local function init(c, ostypes, bsdtypes)

local abi = require "syscall.abi"

local ffi = require "ffi"
local bit = require "syscall.bit"

local h = require "syscall.helpers"

local ptt, reviter, mktype, istype, lenfn, lenmt, getfd, newfn
  = h.ptt, h.reviter, h.mktype, h.istype, h.lenfn, h.lenmt, h.getfd, h.newfn
local addtype, addtype_var, addtype_fn, addraw2 = h.addtype, h.addtype_var, h.addtype_fn, h.addraw2
local ntohl, ntohl, ntohs, htons = h.ntohl, h.ntohl, h.ntohs, h.htons
local split, trim, strflag = h.split, h.trim, h.strflag
local align = h.align

local types = {t = {}, pt = {}, s = {}, ctypes = {}}

local t, pt, s, ctypes = types.t, types.pt, types.s, types.ctypes

local sharedtypes = require "syscall.shared.types"

for k, v in pairs(sharedtypes.t) do t[k] = v end
for k, v in pairs(sharedtypes.pt) do pt[k] = v end
for k, v in pairs(sharedtypes.s) do s[k] = v end
for k, v in pairs(sharedtypes.ctypes) do ctypes[k] = v end

local mt = {} -- metatables

-- generic types

local voidp = ffi.typeof("void *")

function pt.void(x)
  return ffi.cast(voidp, x)
end

local addtypes = {
  size = "size_t",
  ssize = "ssize_t",
  mode = "mode_t",
  dev = "dev_t",
  off = "off_t",
  uid = "uid_t",
  gid = "gid_t",
  pid = "pid_t",
  in_port = "in_port_t",
  sa_family = "sa_family_t",
  socklen = "socklen_t",
  id = "id_t",
  daddr = "daddr_t",
  time = "time_t",
  blksize = "blksize_t",
  blkcnt = "blkcnt_t",
  clock = "clock_t",
  nlink = "nlink_t",
  ino = "ino_t",
  nfds = "nfds_t",
  winsize = "struct winsize",
}

-- note we cannot add any metatable, as may be declared in os and rump, so not even lenmt added
for k, v in pairs(addtypes) do addtype(types, k, v) end

t.socklen1 = ffi.typeof("socklen_t[1]")
t.off1 = ffi.typeof("off_t[1]")
t.uid1 = ffi.typeof("uid_t[1]")
t.gid1 = ffi.typeof("gid_t[1]")

local errsyms = {} -- reverse lookup
for k, v in pairs(c.E) do
  errsyms[v] = k
end

mt.error = {
  __tostring = function(e) return c.errornames[e.sym] end,
  __index = function(t, k)
    if k == 'sym' then return errsyms[t.errno] end
    if k == 'lsym' then return errsyms[t.errno]:lower() end
    if c.E[k] then return c.E[k] == t.errno end
    error("invalid error " .. k)
  end,
  __new = function(tp, errno)
    if not errno then errno = ffi.errno() end
    return ffi.new(tp, errno)
  end,
}

t.error = ffi.metatype("struct {int errno;}", mt.error)

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

mt.timeval = {
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
  },
  __new = function(tp, v)
    if not v then v = {0, 0} end
    if istype(t.timespec, v) then v = {v.tv_sec, math.floor(v.tv_nsec / 1000)} end
    if type(v) == "table" then
      if v.tv_nsec then -- compat with timespec
        v.tv_usec = math.floor(v.tv_nsec / 1000)
        v.tv_nsec = 0
      end
    end
    if type(v) ~= "number" then return ffi.new(tp, v) end
    local ts = ffi.new(tp)
    ts.time = v
    return ts
  end
}

addtype(types, "timeval", "struct timeval", mt.timeval)

mt.timespec = {
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
  },
  __new = function(tp, v)
    if not v then v = {0, 0} end
    if istype(t.timeval, v) then v = {v.tv_sec, v.tv_usec * 1000} end
    if type(v) == "table" then
      if v.tv_usec then -- compat with timespec TODO add to methods, and use standard new allocation function?
        v.tv_nsec = v.tv_usec * 1000
        v.tv_usec = 0
      end
    end
    if type(v) ~= "number" then return ffi.new(tp, v) end
    local ts = ffi.new(tp)
    ts.time = v
    return ts
  end,
}

addtype(types, "timespec", "struct timespec", mt.timespec)

-- array so cannot just add metamethods
addraw2(types, "timeval2_raw", "struct timeval")
t.timeval2 = function(tv1, tv2)
  if ffi.istype(t.timeval2_raw, tv1) then return tv1 end
  if type(tv1) == "table" then tv1, tv2 = tv1[1], tv1[2] end
  local tv = t.timeval2_raw()
  if tv1 then tv[0] = t.timeval(tv1) end
  if tv2 then tv[1] = t.timeval(tv2) end
  return tv
end

-- array so cannot just add metamethods
addraw2(types, "timespec2_raw", "struct timespec")
t.timespec2 = function(ts1, ts2)
  if ffi.istype(t.timespec2_raw, ts1) then return ts1 end
  if type(ts1) == "table" then ts1, ts2 = ts1[1], ts1[2] end
  local ts = t.timespec2_raw()
  if ts1 then if type(ts1) == 'string' then ts[0].tv_nsec = c.UTIME[ts1] else ts[0] = t.timespec(ts1) end end
  if ts2 then if type(ts2) == 'string' then ts[1].tv_nsec = c.UTIME[ts2] else ts[1] = t.timespec(ts2) end end
  return ts
end

mt.groups = {
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
}

addtype_var(types, "groups", "struct {int count; gid_t list[?];}", mt.groups)

-- signal set handlers
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

mt.sigset = {
  __index = function(set, k)
    if k == 'add' then return sigaddsets end
    if k == 'del' then return sigdelsets end
    if k == 'isemptyset' then return sigemptyset(set) end
    local sig = c.SIG[k]
    if sig then return sigismember(set, sig) end
    error("invalid index " .. k)
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
}

addtype(types, "sigset", "sigset_t", mt.sigset)

-- cmsg functions, try to hide some of this nasty stuff from the user
local cmsgtype = "struct cmsghdr"
if abi.rumpfn then cmsgtype = abi.rumpfn(cmsgtype) end
local cmsg_hdrsize = ffi.sizeof(ffi.typeof(cmsgtype), 0)
local voidalign = ffi.alignof(ffi.typeof("void *"))
local function cmsg_align(len) return align(len, voidalign) end -- TODO double check this is correct for all OSs
local cmsg_ahdr = cmsg_align(cmsg_hdrsize)
--local function cmsg_space(len) return cmsg_ahdr + cmsg_align(len) end
local function cmsg_len(len) return cmsg_ahdr + len end

-- TODO move this to sockopt file, like set/getsockopt as very similar mapping
local typemap = {
  [c.SOL.SOCKET] = c.SCM,
}

-- TODO add the othes here, they differ by OS
if c.SOL.IP then typemap[c.SOL.IP] = c.IP end

mt.cmsghdr = {
  __index = {
    len = function(self) return tonumber(self.cmsg_len) end,
    data = function(self) return self.cmsg_data end,
    datalen = function(self) return self:len() - cmsg_ahdr end,
    hdrsize = function(self) return cmsg_hdrsize end, -- constant, but better to have it here
    align = function(self) return cmsg_align(self:len()) end,
    fds = function(self)
      if self.cmsg_level == c.SOL.SOCKET and self.cmsg_type == c.SCM.RIGHTS then
        local fda = pt.int(self:data())
        local fdc = bit.rshift(self:datalen(), 2) -- shift by int size
        local i = 0
        return function()
          if i < fdc then
            local fd = t.fd(fda[i])
            i = i + 1
            return fd
          end
        end
      else
        return function() end
      end
    end,
    credentials = function(self) -- TODO Linux only, NetBSD uses SCM_CREDS
      if self.cmsg_level == c.SOL.SOCKET and self.cmsg_type == c.SCM.CREDENTIALS then
        local cred = pt.ucred(self:data())
        return cred.pid, cred.uid, cred.gid
      else
        return nil, "cmsg does not contain credentials"
      end
    end,
    setdata = function(self, data, datalen)
      ffi.copy(self:data(), data, datalen or #data)
    end,
    setfd = function(self, fd) -- single fd
      local int = pt.int(self:data())
      int[0] = getfd(fd)
    end,
    setfds = function(self, fds) -- general case, note does not check size
      if type(fds) == "number" or fds.getfd then return self:setfd(fds) end
      local int = pt.int(self:data())
      local off = 0
      for _, v in ipairs(fds) do
        int[off] = getfd(v)
        off = off + 1
      end
    end,
  },
  __new = function (tp, level, scm, data, data_size)
    if not data then data_size = data_size or 0 end
    level = c.SOL[level]
    if typemap[level] then scm = typemap[level][scm] end
    if level == c.SOL.SOCKET and scm == c.SCM.RIGHTS then
      if type(data) == "number" then -- slightly odd but useful interfaces for fds - TODO document
        data_size = data * s.int
        data = nil
      elseif type(data) == "table" then data_size = #data * s.int end
    end
    data_size = data_size or #data
    local self = ffi.new(tp, data_size, {
      cmsg_len = cmsg_len(data_size),
      cmsg_level = level,
      cmsg_type = scm,
    })
    if data and (level == c.SOL.SOCKET and scm == c.SCM.RIGHTS) then
      self:setfds(data)
    elseif data then
      self:setdata(data, data_size)
    end
    return self
  end,
}

addtype_var(types, "cmsghdr", "struct cmsghdr", mt.cmsghdr)

-- msg_control is a bunch of cmsg structs, but these are all different lengths, as they have variable size arrays

-- these functions also take and return a raw char pointer to msg_control, to make life easier, as well as the cast cmsg
local function cmsg_firsthdr(msg)
  local mc = msg.msg_control
  local cmsg = pt.cmsghdr(mc)
  if tonumber(msg.msg_controllen) < cmsg:hdrsize() then return nil end -- hdrsize is a constant, so does not matter if invalid struct
  return mc, cmsg
end

local function cmsg_nxthdr(msg, buf, cmsg)
  if tonumber(cmsg.cmsg_len) < cmsg:hdrsize() then return nil end -- invalid cmsg
  buf = pt.char(buf)
  local msg_control = pt.char(msg.msg_control)
  buf = buf + cmsg:align() -- find next cmsg
  if buf + cmsg:hdrsize() > msg_control + msg.msg_controllen then return nil end -- header would not fit
  cmsg = pt.cmsghdr(buf)
  if buf + cmsg:align() > msg_control + msg.msg_controllen then return nil end -- whole cmsg would not fit
  return buf, cmsg
end

local function cmsg_iter(msg, last_msg_control)
  local msg_control
  if last_msg_control == nil then -- First iteration
    msg_control = pt.char(msg.msg_control)
  else
    local last_cmsg = pt.cmsghdr(last_msg_control)
    msg_control = last_msg_control + last_cmsg:align() -- find next cmsg
  end
  local end_offset = pt.char(msg.msg_control) + msg.msg_controllen
  local cmsg = pt.cmsghdr(msg_control)
  if msg_control + cmsg:hdrsize() > end_offset then return nil end -- header would not fit
  if msg_control + cmsg:align() > end_offset then return nil end -- whole cmsg would not fit
  return msg_control, cmsg
end
local function cmsg_headers(msg)
  return cmsg_iter, msg, nil
end

mt.msghdr = {
  __index = {
    cmsg_firsthdr = cmsg_firsthdr,
    cmsg_nxthdr = cmsg_nxthdr,
    cmsgs = cmsg_headers,
  },
  newindex = {
    name = function(m, n)
      if n then m.msg_name, m.msg_namelen = n, #n else m.msg_name, m.msg_namelen = nil, 0 end
    end,
    iov = function(m, io)
      if ffi.istype(t.iovec, io) then -- single iovec
        m.msg_iov, m.msg_iovlen = io, 1
      else -- iovecs
        m.msg_iov, m.msg_iovlen = io.iov, #io
      end
    end,
    control = function(m, buf)
      if buf then m.msg_control, m.msg_controllen = buf, #buf else m.msg_control, m.msg_controllen = nil, 0 end
    end,
  },
  __new = newfn,
}

addtype(types, "msghdr", "struct msghdr", mt.msghdr)

mt.pollfd = {
  index = {
    getfd = function(pfd) return pfd.fd end,
  }
}

for k, v in pairs(c.POLL) do mt.pollfd.index[k] = function(pfd) return bit.band(pfd.revents, v) ~= 0 end end

addtype(types, "pollfd", "struct pollfd", mt.pollfd)

mt.pollfds = {
  __len = function(p) return p.count end,
  __new = function(tp, ps)
    if type(ps) == 'number' then return ffi.new(tp, ps, ps) end
    local count = #ps
    local fds = ffi.new(tp, count, count)
    for n = 1, count do -- TODO ideally we use ipairs on both arrays/tables
      fds.pfd[n - 1].fd = ps[n].fd:getfd()
      fds.pfd[n - 1].events = c.POLL[ps[n].events]
      fds.pfd[n - 1].revents = 0
    end
    return fds
  end,
  __ipairs = function(p) return reviter, p.pfd, p.count end
}

addtype_var(types, "pollfds", "struct {int count; struct pollfd pfd[?];}", mt.pollfds)

mt.rusage = {
  index = {
    utime    = function(ru) return ru.ru_utime end,
    stime    = function(ru) return ru.ru_stime end,
    maxrss   = function(ru) return tonumber(ru.ru_maxrss) end,
    ixrss    = function(ru) return tonumber(ru.ru_ixrss) end,
    idrss    = function(ru) return tonumber(ru.ru_idrss) end,
    isrss    = function(ru) return tonumber(ru.ru_isrss) end,
    minflt   = function(ru) return tonumber(ru.ru_minflt) end,
    majflt   = function(ru) return tonumber(ru.ru_majflt) end,
    nswap    = function(ru) return tonumber(ru.ru_nswap) end,
    inblock  = function(ru) return tonumber(ru.ru_inblock) end,
    oublock  = function(ru) return tonumber(ru.ru_oublock) end,
    msgsnd   = function(ru) return tonumber(ru.ru_msgsnd) end,
    msgrcv   = function(ru) return tonumber(ru.ru_msgrcv) end,
    nsignals = function(ru) return tonumber(ru.ru_nsignals) end,
    nvcsw    = function(ru) return tonumber(ru.ru_nvcsw) end,
    nivcsw   = function(ru) return tonumber(ru.ru_nivcsw) end,
  },
}

addtype(types, "rusage", "struct rusage", mt.rusage)

-- include OS specific types
types = ostypes.init(types)
if bsdtypes then types = bsdtypes.init(c, types) end

-- this is declared above
samap_pt = {
  [c.AF.UNIX] = pt.sockaddr_un,
  [c.AF.INET] = pt.sockaddr_in,
  [c.AF.INET6] = pt.sockaddr_in6,
}

-- these are not defined for every OS (yet)
if c.AF.NETLINK then samap_pt[c.AF.NETLINK] = pt.sockaddr_nl end
if c.AF.PACKET then samap_pt[c.AF.PACKET] = pt.sockaddr_ll end

-- define dents type if dirent is defined
if t.dirent then
  t.dirents = function(buf, size) -- buf should be char*
    local d, i = nil, 0
    return function() -- TODO work out if possible to make stateless
      if size > 0 and not d then
        d = pt.dirent(buf)
        i = i + d.d_reclen
        return d
      end
      while i < size do
        d = pt.dirent(pt.char(d) + d.d_reclen)
        i = i + d.d_reclen
        if d.ino ~= 0 then return d end -- some systems use ino = 0 for deleted files before removed eg OSX; it is never valid
      end
      return nil
    end
  end
end

return types

end

return {init = init}

