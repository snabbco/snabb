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
  clock = "clock_t",
  nlink = "nlink_t",
  ino = "ino_t",
  nfds = "nfds_t",
}

-- note we cannot add any metatable, as may be declared in os and rump, so not even lenmt added
for k, v in pairs(addtypes) do addtype(types, k, v) end

t.socklen1 = ffi.typeof("socklen_t[1]")
t.off1 = ffi.typeof("off_t[1]")
t.uid1 = ffi.typeof("uid_t[1]")
t.gid1 = ffi.typeof("gid_t[1]")

local errsyms = {} -- reverse lookup by number
local errnames = {} -- lookup error message by number
for k, v in pairs(c.E) do
  errsyms[v] = k
  errnames[v] = assert(c.errornames[k], "missing error name " .. k)
end

for k, v in pairs(c.EALIAS or {}) do
  c.E[k] = v
end
c.EALIAS = nil

mt.error = {
  __tostring = function(e) return errnames[e.errno] end,
  __index = function(e, k)
    if k == 'sym' then return errsyms[e.errno] end
    if k == 'lsym' then return errsyms[e.errno]:lower() end
    if c.E[k] then return c.E[k] == e.errno end
    error("invalid error " .. k)
  end,
  __new = function(tp, errno)
    if not errno then errno = ffi.errno() end
    return ffi.new(tp, errno)
  end,
}

t.error = ffi.metatype("struct {int errno;}", mt.error)

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
  end,
  __tostring = function(tv) return tostring(tv.time) end,
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
  __tostring = function(tv) return tostring(tv.time) end,
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
  return bit.band(set.sig[d], bit.lshift(1, (sig - 1) % 32)) ~= 0
end

local function sigemptyset(set)
  for i = 0, s.sigset / 4 - 1 do
    if set.sig[i] ~= 0 then return false end
  end
  return true
end

local function sigaddset(set, sig)
  set = t.sigset(set)
  local d = bit.rshift(sig - 1, 5)
  set.sig[d] = bit.bor(set.sig[d], bit.lshift(1, (sig - 1) % 32))
  return set
end

local function sigdelset(set, sig)
  set = t.sigset(set)
  local d = bit.rshift(sig - 1, 5)
  set.sig[d] = bit.band(set.sig[d], bit.bnot(bit.lshift(1, (sig - 1) % 32)))
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
      f.sig[d] = bit.bor(f.sig[d], bit.lshift(1, (sig - 1) % 32))
    end
    return f
  end,
}

addtype(types, "sigset", "sigset_t", mt.sigset)

mt.sigval = {
  index = {
    int = function(self) return self.sival_int end,
    ptr = function(self) return self.sival_ptr end,
  },
  newindex = {
    int = function(self, v) self.sival_int = v end,
    ptr = function(self, v) self.sival_ptr = v end,
  },
  __new = function(tp, v)
    if not v or type(v) == "table" then return newfn(tp, v) end
    local siv = ffi.new(tp)
    if type(v) == "number" then siv.int = v else siv.ptr = v end
    return siv
  end,
}

addtype(types, "sigval", "union sigval", mt.sigval) -- not always called sigval_t

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
    -- TODO add iov
  },
  newindex = {
    name = function(m, n)
      m.msg_name, m.msg_namelen = n, #n
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
  print = {"utime", "stime", "maxrss", "ixrss", "idrss", "isrss", "minflt", "majflt", "nswap",
           "inblock", "oublock", "msgsnd", "msgrcv", "nsignals", "nvcsw", "nivcsw"},
}

addtype(types, "rusage", "struct rusage", mt.rusage)

local function itnormal(v)
  if not v then v = {{0, 0}, {0, 0}} end
  if v.interval then
    v.it_interval = v.interval
    v.interval = nil
  end
  if v.value then
    v.it_value = v.value
    v.value = nil
  end
  if not v.it_interval then
    v.it_interval = v[1]
    v[1] = nil
  end
  if not v.it_value then
    v.it_value = v[2]
    v[2] = nil
  end
  return v
end

mt.itimerspec = {
  index = {
    interval = function(it) return it.it_interval end,
    value = function(it) return it.it_value end,
  },
  __new = function(tp, v)
    v = itnormal(v)
    v.it_interval = istype(t.timespec, v.it_interval) or t.timespec(v.it_interval)
    v.it_value = istype(t.timespec, v.it_value) or t.timespec(v.it_value)
    return ffi.new(tp, v)
  end,
}

addtype(types, "itimerspec", "struct itimerspec", mt.itimerspec)

mt.itimerval = {
  index = {
    interval = function(it) return it.it_interval end,
    value = function(it) return it.it_value end,
  },
  __new = function(tp, v)
    v = itnormal(v)
    v.it_interval = istype(t.timeval, v.it_interval) or t.timeval(v.it_interval)
    v.it_value = istype(t.timeval, v.it_value) or t.timeval(v.it_value)
    return ffi.new(tp, v)
  end,
}

addtype(types, "itimerval", "struct itimerval", mt.itimerval)

mt.macaddr = {
  __tostring = function(m)
    local hex = {}
    for i = 1, 6 do
      hex[i] = string.format("%02x", m.mac_addr[i - 1])
    end
    return table.concat(hex, ":")
  end,
  __new = function(tp, str)
    local mac = ffi.new(tp)
    if str then
      for i = 1, 6 do
        local n = tonumber(str:sub(i * 3 - 2, i * 3 - 1), 16) -- TODO more checks on syntax
        mac.mac_addr[i - 1] = n
      end
    end
    return mac
  end,
}

addtype(types, "macaddr", "struct {uint8_t mac_addr[6];}", mt.macaddr)

-- include OS specific types
types = ostypes.init(types)
if bsdtypes then types = bsdtypes.init(c, types) end

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

