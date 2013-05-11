-- choose correct types for OS

-- these are either simple ffi types or ffi metatypes for the kernel types
-- plus some Lua metatables for types that cannot be sensibly done as Lua types eg arrays, integers

-- note that some types will be overridden, eg default fd type will have metamethods added

local ffi = require "ffi"
local bit = require "bit"

require "syscall.ffitypes"

local h = require "syscall.helpers"

local ntohl, ntohl, ntohs, htons = h.ntohl, h.ntohl, h.ntohs, h.htons

local c = require "syscall.constants"

local abi = require "syscall.abi"

local C = ffi.C -- for inet_pton, TODO due to be replaced with Lua
ffi.cdef[[
int inet_pton(int af, const char *src, void *dst);
]]

local types = {}

local t, pt, s, ctypes = {}, {}, {}, {} -- types, pointer types and sizes tables
types.t, types.pt, types.s, types.ctypes = t, pt, s, ctypes

local mt = {} -- metatables
local meth = {}

--helpers
local function ptt(tp)
  local ptp = ffi.typeof(tp .. " *")
  return function(x) return ffi.cast(ptp, x) end
end

local function addtype(name, tp, mt)
  if mt then t[name] = ffi.metatype(tp, mt) else t[name] = ffi.typeof(tp) end
  ctypes[tp] = t[name]
  pt[name] = ptt(tp)
  s[name] = ffi.sizeof(t[name])
end

local function lenfn(tp) return ffi.sizeof(tp) end

local lenmt = {__len = lenfn}

-- generic for __new TODO use more
local function newfn(tp, tab)
  local num = {}
  if tab then for i = 1, #tab do num[i] = tab[i] end end -- numeric index initialisers
  local obj = ffi.new(tp, num)
  -- these are split out so __newindex is called, not just initialisers luajit understands
  for k, v in pairs(tab or {}) do if type(k) == "string" then obj[k] = v end end -- set string indexes
  return obj
end

-- makes code tidier
local function istype(tp, x)
  if ffi.istype(tp, x) then return x else return false end
end

-- convert strings to inet addresses and the reverse
local function inet_ntop(af, src)
  af = c.AF[af] -- TODO do not need, in fact could split into two functions if no need to export.
  if af == c.AF.INET then
    local b = pt.uchar(src)
    return b[0] .. "." .. b[1] .. "." .. b[2] .. "." .. b[3]
  end
  if af ~= c.AF.INET6 then return end
  local a = src.s6_addr
  local parts = {256*a[0] + a[1], 256*a[2] + a[3],   256*a[4] + a[5],   256*a[6] + a[7],
                 256*a[8] + a[9], 256*a[10] + a[11], 256*a[12] + a[13], 256*a[14] + a[15]}

  for i = 1, #parts do parts[i] = string.format("%x", parts[i]) end

  local start, max = 0, 0
  for i = 1, #parts do
    if parts[i] == "0" then
      local count = 0
      for j = i, #parts do
        if parts[j] == "0" then count = count + 1 else break end
      end
      if count > max then max, start = count, i end
    end
  end

  if max > 2 then
    parts[start] = ""
    if start == 1 or start + max == 9 then parts[start] = ":" end
    if start == 1 and start + max == 9 then parts[start] = "::" end 
    for i = 1, max - 1 do table.remove(parts, start + 1) end
  end

  return table.concat(parts, ":")
end

local function inet_pton(af, src, addr)
  af = c.AF[af]
  if not addr then addr = t.addrtype[af]() end
  local ret = C.inet_pton(af, src, addr) -- TODO redo in pure Lua
  if ret == -1 then return nil, t.error() end
  if ret == 0 then return nil end -- maybe return string
  return addr
end

-- generic types

local voidp = ffi.typeof("void *")

pt.void = function(x)
  return ffi.cast(voidp, x)
end

local addtypes = {
  char = "char",
  uchar = "unsigned char",
  int = "int",
  uint = "unsigned int",
  int16 = "int16_t",
  uint16 = "uint16_t",
  int32 = "int32_t",
  uint32 = "uint32_t",
  int64 = "int64_t",
  uint64 = "uint64_t",
  long = "long",
  ulong = "unsigned long",
  uintptr = "uintptr_t",
  intptr = "intptr_t",
  size = "size_t",
  mode = "mode_t",
  dev = "dev_t",
  off = "off_t",
  pid = "pid_t",
  sa_family = "sa_family_t",
}

local addstructs = {
  iovec = "struct iovec",
}

for k, v in pairs(addtypes) do addtype(k, v) end
for k, v in pairs(addstructs) do addtype(k, v, lenmt) end

t.ints = ffi.typeof("int[?]")
t.buffer = ffi.typeof("char[?]") -- TODO rename as chars?

t.int1 = ffi.typeof("int[1]")
t.uint1 = ffi.typeof("unsigned int[1]")
t.int16_1 = ffi.typeof("int16_t[1]")
t.uint16_1 = ffi.typeof("uint16_t[1]")
t.int32_1 = ffi.typeof("int32_t[1]")
t.uint32_1 = ffi.typeof("uint32_t[1]")
t.int64_1 = ffi.typeof("int64_t[1]")
t.uint64_1 = ffi.typeof("uint64_t[1]")
t.socklen1 = ffi.typeof("socklen_t[1]")
t.off1 = ffi.typeof("off_t[1]")
t.uid1 = ffi.typeof("uid_t[1]")
t.gid1 = ffi.typeof("gid_t[1]")

t.char2 = ffi.typeof("char[2]")
t.int2 = ffi.typeof("int[2]")
t.uint2 = ffi.typeof("unsigned int[2]")

-- still need sizes for these, for ioctls
s.uint2 = ffi.sizeof(t.uint2)

-- 64 to 32 bit conversions via unions TODO use meth not object?
if abi.le then
mt.i6432 = {
  __index = {
    to32 = function(u) return u.i32[1], u.i32[0] end,
  }
}
else
mt.i6432 = {
  __index = {
    to32 = function(u) return u.i32[0], u.i32[1] end,
  }
}
end

t.i6432 = ffi.metatype("union {int64_t i64; int32_t i32[2];}", mt.i6432)
t.u6432 = ffi.metatype("union {uint64_t i64; uint32_t i32[2];}", mt.i6432)

local errsyms = {} -- reverse lookup
for k, v in pairs(c.E) do
  errsyms[v] = k
end

t.error = ffi.metatype("struct {int errno;}", {
  __tostring = function(e) return require("syscall.errors")[e.errno] end,
  __index = function(t, k)
    if k == 'sym' then return errsyms[t.errno] end
    if k == 'lsym' then return errsyms[t.errno]:lower() end
    if c.E[k] then return c.E[k] == t.errno end
  end,
  __new = function(tp, errno)
    if not errno then errno = ffi.errno() end
    return ffi.new(tp, errno)
  end
})

-- TODO should we change to meth
mt.device = {
  __index = {
    major = function(dev)
      local h, l = t.i6432(dev.dev):to32()
      return bit.bor(bit.band(bit.rshift(l, 8), 0xfff), bit.band(h, bit.bnot(0xfff)));
    end,
    minor = function(dev)
      local h, l = t.i6432(dev.dev):to32()
      return bit.bor(bit.band(l, 0xff), bit.band(bit.rshift(l, 12), bit.bnot(0xff)));
    end,
    device = function(dev) return tonumber(dev.dev) end,
  },
}

t.device = function(major, minor)
  local dev = major
  if minor then dev = bit.bor(bit.band(minor, 0xff), bit.lshift(bit.band(major, 0xfff), 8), bit.lshift(bit.band(minor, bit.bnot(0xff)), 12)) + 0x100000000 * bit.band(major, bit.bnot(0xfff)) end
  return setmetatable({dev = t.dev(dev)}, mt.device)
end

-- TODO add generic address type that works out which to take? basically inet_name, except without netmask

addtype("in_addr", "struct in_addr", {
  __tostring = function(a) return inet_ntop(c.AF.INET, a) end,
  __new = function(tp, s)
    local addr = ffi.new(tp)
    if s then
      if ffi.istype(tp, s) then addr.s_addr = s.s_addr else addr = inet_pton(c.AF.INET, s, addr) end
    end
    return addr
  end
})

addtype("in6_addr", "struct in6_addr", {
  __tostring = function(a) return inet_ntop(c.AF.INET6, a) end,
  __new = function(tp, s)
    local addr = ffi.new(tp)
    if s then addr = inet_pton(c.AF.INET6, s, addr) end
    return addr
  end
})

t.addrtype = {
  [c.AF.INET] = t.in_addr,
  [c.AF.INET6] = t.in6_addr,
}

mt.iovecs = {
  __index = function(io, k)
    return io.iov[k - 1]
  end,
  __newindex = function(io, k, v)
    v = istype(t.iovec, v) or t.iovec(v)
    ffi.copy(io.iov[k - 1], v, s.iovec)
  end,
  __len = function(io) return io.count end,
  __new = function(tp, is)
    if type(is) == 'number' then return ffi.new(tp, is, is) end
    local count = #is
    local iov = ffi.new(tp, count, count)
    for n = 1, count do
      local i = is[n]
      if type(i) == 'string' then
        local buf = t.buffer(#i)
        ffi.copy(buf, i, #i)
        iov[n].iov_base = buf
        iov[n].iov_len = #i
      elseif type(i) == 'number' then
        iov[n].iov_base = t.buffer(i)
        iov[n].iov_len = i
      elseif ffi.istype(t.iovec, i) then
        ffi.copy(iov[n], i, s.iovec)
      elseif type(i) == 'cdata' then -- eg buffer or other structure
        iov[n].iov_base = i
        iov[n].iov_len = ffi.sizeof(i)
      else -- eg table
        iov[n] = i
      end
    end
    return iov
  end
}

t.iovecs = ffi.metatype("struct { int count; struct iovec iov[?];}", mt.iovecs) -- do not use metatype helper as variable size

-- include OS specific types
local hh = {ptt = ptt, addtype = addtype, lenfn = lenfn, lenmt = lenmt, newfn = newfn, istype = istype}

types = require("syscall." .. abi.os .. ".types")(types, hh)

return types

