-- this module defines the types with metatypes that are always common, so do not get errors redefining metatypes

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local ffi = require "ffi"

local bit = require "syscall.bit"

local t, ctypes, pt, s = {}, {}, {}, {}
local types = {t = t, pt = pt, s = s, ctypes = ctypes}

local h = require "syscall.helpers"

local addtype, addtype_var, addtype_fn, addraw2 = h.addtype, h.addtype_var, h.addtype_fn, h.addraw2
local addtype1, addtype2, addptrtype = h.addtype1, h.addtype2, h.addptrtype
local ptt, reviter, mktype, istype, lenfn, lenmt, getfd, newfn
  = h.ptt, h.reviter, h.mktype, h.istype, h.lenfn, h.lenmt, h.getfd, h.newfn
local ntohl, ntohl, ntohs, htons, htonl = h.ntohl, h.ntohl, h.ntohs, h.htons, h.htonl
local split, trim, strflag = h.split, h.trim, h.strflag
local align = h.align

local addtypes = {
  char = "char",
  uchar = "unsigned char",
  int = "int",
  uint = "unsigned int",
  int8 = "int8_t",
  uint8 = "uint8_t",
  int16 = "int16_t",
  uint16 = "uint16_t",
  int32 = "int32_t",
  uint32 = "uint32_t",
  int64 = "int64_t",
  uint64 = "uint64_t",
  long = "long",
  ulong = "unsigned long",
}

for k, v in pairs(addtypes) do addtype(types, k, v) end

local addtypes1 = {
  char1 = "char",
  uchar1 = "unsigned char",
  int1 = "int",
  uint1 = "unsigned int",
  int16_1 = "int16_t",
  uint16_1 = "uint16_t",
  int32_1 = "int32_t",
  uint32_1 = "uint32_t",
  int64_1 = "int64_t",
  uint64_1 = "uint64_t",
  long1 = "long",
  ulong1 = "unsigned long",
  intptr1 = "intptr_t",
  size1 = "size_t",
}

for k, v in pairs(addtypes1) do addtype1(types, k, v) end

local addtypes2 = {
  char2 = "char",
  int2 = "int",
  uint2 = "unsigned int",
}

for k, v in pairs(addtypes2) do addtype2(types, k, v) end

local ptrtypes = {
  uintptr = "uintptr_t",
  intptr = "intptr_t",
}

for k, v in pairs(ptrtypes) do addptrtype(types, k, v) end

t.ints = ffi.typeof("int[?]")
t.buffer = ffi.typeof("char[?]") -- TODO rename as chars?
t.string_array = ffi.typeof("const char *[?]")

local mt = {}

mt.iovec = {
  index = {
    base = function(self) return self.iov_base end,
    len = function(self) return self.iov_len end,
  },
}

addtype(types, "iovec", "struct iovec", mt.iovec)

mt.iovecs = {
  __len = function(io) return io.count end,
  __tostring = function(io)
    local s = {}
    for i = 0, io.count - 1 do
      local iovec = io.iov[i]
      s[i + 1] = ffi.string(iovec.iov_base, iovec.iov_len)
    end
    return table.concat(s)
  end;
  __new = function(tp, is)
    if type(is) == 'number' then return ffi.new(tp, is, is) end
    local count = #is
    local iov = ffi.new(tp, count, count)
    local j = 0
    for n, i in ipairs(is) do
      if type(i) == 'string' then
        local buf = t.buffer(#i)
        ffi.copy(buf, i, #i)
        iov.iov[j].iov_base = buf
        iov.iov[j].iov_len = #i
      elseif type(i) == 'number' then
        iov.iov[j].iov_base = t.buffer(i)
        iov.iov[j].iov_len = i
      elseif ffi.istype(t.iovec, i) then
        ffi.copy(iov[n], i, s.iovec)
      elseif type(i) == 'cdata' or type(i) == 'userdata' then -- eg buffer or other structure, userdata if luaffi
        iov.iov[j].iov_base = i
        iov.iov[j].iov_len = ffi.sizeof(i)
      else -- eg table
        iov.iov[j] = i
      end
      j = j + 1
    end
    return iov
  end,
}

addtype_var(types, "iovecs", "struct {int count; struct iovec iov[?];}", mt.iovecs)

-- convert strings to inet addresses and the reverse
local function inet4_ntop(src)
  local b = pt.uchar(src)
  return b[0] .. "." .. b[1] .. "." .. b[2] .. "." .. b[3]
end

local function inet6_ntop(src)
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

local function inet4_pton(src)
  local ip4 = split("%.", src)
  if #ip4 ~= 4 then error "malformed IP address" end
  return htonl(tonumber(ip4[1]) * 0x1000000 + tonumber(ip4[2]) * 0x10000 + tonumber(ip4[3]) * 0x100 + tonumber(ip4[4]))
end

local function hex(str) return tonumber("0x" .. str) end

local function inet6_pton(src, addr)
  -- TODO allow form with decimals at end for ipv4 addresses
  local ip8 = split(":", src)
  if #ip8 > 8 then return nil end
  local before, after = src:find("::")
  before, after = src:sub(1, before - 1), src:sub(after + 1)
  if before then
    if #ip8 == 8 then return nil end -- must be some missing
    if before == "" then before = "0" end
    if after == "" then after = "0" end
    src = before .. ":" .. string.rep("0:", 8 - #ip8 + 1) .. after
    ip8 = split(":", src)
  end
  for i = 1, 8 do
    addr.s6_addr[i * 2 - 1] = bit.band(hex(ip8[i]), 0xff)
    addr.s6_addr[i * 2 - 2] = bit.rshift(hex(ip8[i]), 8)
  end
  return addr
end

local inaddr = strflag {
  ANY = "0.0.0.0",
  LOOPBACK = "127.0.0.1",
  BROADCAST = "255.255.255.255",
}

local in6addr = strflag {
  ANY = "::",
  LOOPBACK = "::1",
}

 -- given this address and a mask, return a netmask and broadcast as in_addr
local function mask_bcast(address, netmask)
  local bcast = t.in_addr()
  local nmask = t.in_addr() -- TODO
  if netmask > 32 then error("bad netmask " .. netmask) end
  if netmask < 32 then nmask.s_addr = htonl(bit.rshift(-1, netmask)) end
  bcast.s_addr = bit.bor(tonumber(address.s_addr), nmask.s_addr)
  return {address = address, broadcast = bcast, netmask = nmask}
end

mt.in_addr = {
  __index = {
    get_mask_bcast = function(addr, mask) return mask_bcast(addr, mask) end,
  },
  newindex = {
    addr = function(addr, s)
      if ffi.istype(t.in_addr, s) then
        addr.s_addr = s.s_addr
      elseif type(s) == "string" then
        if inaddr[s] then s = inaddr[s] end
        addr.s_addr = inet4_pton(s)
      else -- number
        addr.s_addr = htonl(s)
      end
    end,
  },
  __tostring = inet4_ntop,
  __new = function(tp, s)
    local addr = ffi.new(tp)
    if s then addr.addr = s end
    return addr
  end,
  __len = lenfn,
}

addtype(types, "in_addr", "struct in_addr", mt.in_addr)

mt.in6_addr = {
  __tostring = inet6_ntop,
  __new = function(tp, s)
    local addr = ffi.new(tp)
    if s then
      if in6addr[s] then s = in6addr[s] end
      addr = inet6_pton(s, addr)
    end
    return addr
  end,
  __len = lenfn,
}

addtype(types, "in6_addr", "struct in6_addr", mt.in6_addr)

-- ip, udp types. Need endian conversions.
local ptchar = ffi.typeof("char *")
local uint16 = ffi.typeof("uint16_t[1]")

local function ip_checksum(buf, size, c, notfinal)
  c = c or 0
  local b8 = ffi.cast(ptchar, buf)
  local i16 = uint16()
  for i = 0, size - 1, 2 do
    ffi.copy(i16, b8 + i, 2)
    c = c + i16[0]
  end
  if size % 2 == 1 then
    i16[0] = 0
    ffi.copy(i16, b8[size - 1], 1)
    c = c + i16[0]
  end

  local v = bit.band(c, 0xffff)
  if v < 0 then v = v + 0x10000 end -- positive
  c = bit.rshift(c, 16) + v
  c = c + bit.rshift(c, 16)

  if not notfinal then c = bit.bnot(c) end
  if c < 0 then c = c + 0x10000 end -- positive
  return c
end

mt.iphdr = {
  index = {
    checksum = function(i) return function(i)
      i.check = 0
      i.check = ip_checksum(i, s.iphdr)
      return i.check
    end end,
  },
}

addtype(types, "iphdr", "struct iphdr", mt.iphdr)

local udphdr_size = ffi.sizeof("struct udphdr")

-- ugh, naming problems as cannot remove namespace as usual
-- checksum = function(u, ...) return 0 end, -- TODO checksum, needs IP packet info too. as method.
mt.udphdr = {
  index = {
    src = function(u) return ntohs(u.source) end,
    dst = function(u) return ntohs(u.dest) end,
    length = function(u) return ntohs(u.len) end,
    checksum = function(i) return function(i, ip, body)
      local bip = pt.char(ip)
      local bup = pt.char(i)
      local cs = 0
      -- checksum pseudo header
      cs = ip_checksum(bip + ffi.offsetof(ip, "saddr"), 4, cs, true)
      cs = ip_checksum(bip + ffi.offsetof(ip, "daddr"), 4, cs, true)
      local pr = t.char2(0, 17) -- c.IPPROTO.UDP
      cs = ip_checksum(pr, 2, cs, true)
      cs = ip_checksum(bup + ffi.offsetof(i, "len"), 2, cs, true)
      -- checksum udp header
      i.check = 0
      cs = ip_checksum(i, udphdr_size, cs, true)
      -- checksum body
      cs = ip_checksum(body, i.length - udphdr_size, cs)
      if cs == 0 then cs = 0xffff end
      i.check = cs
      return cs
    end end,
  },
  newindex = {
    src = function(u, v) u.source = htons(v) end,
    dst = function(u, v) u.dest = htons(v) end,
    length = function(u, v) u.len = htons(v) end,
  },
}

addtype(types, "udphdr", "struct udphdr", mt.udphdr)

mt.ethhdr = {
  -- TODO
}

addtype(types, "ethhdr", "struct ethhdr", mt.ethhdr)

mt.winsize = {
  index = {
    row = function(ws) return ws.ws_row end,
    col = function(ws) return ws.ws_col end,
    xpixel = function(ws) return ws.ws_xpixel end,
    ypixel = function(ws) return ws.ws_ypixel end,
  },
  newindex = {
    row = function(ws, v) ws.ws_row = v end,
    col = function(ws, v) ws.ws_col = v end,
    xpixel = function(ws, v) ws.ws_xpixel = v end,
    ypixel = function(ws, v) ws.ws_ypixel = v end,
  },
  __new = newfn,
}

addtype(types, "winsize", "struct winsize", mt.winsize)

return types

