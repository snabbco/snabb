-- this module defines the types with metatypes that are always common, so do not get errors redefining metatypes

local ffi = require "ffi"

local t, ctypes, pt, s = {}, {}, {}, {}

local C = ffi.C -- for inet_pton, TODO due to be replaced with Lua
ffi.cdef[[
int inet_pton(int af, const char *src, void *dst);
]]

local c = require "syscall.linux.constants"

local h = require "syscall.helpers"

local ntohl, ntohl, ntohs, htons = h.ntohl, h.ntohl, h.ntohs, h.htons
local split, trim, strflag = h.split, h.trim, h.strflag

local function ptt(tp)
  local ptp = ffi.typeof(tp .. " *")
  return function(x) return ffi.cast(ptp, x) end
end

local function addtype(name, tp, mt)
  t[name] = ffi.metatype(tp, mt)
  ctypes[tp] = t[name]
  pt[name] = ptt(tp)
  s[name] = ffi.sizeof(t[name])
end

local function lenfn(tp) return ffi.sizeof(tp) end

-- TODO add generic address type that works out which to take? basically inet_name, except without netmask

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

local function inet4_pton(src, addr)
  local ip4 = split("%.", src)
  if #ip4 ~= 4 then return nil end
  addr = addr or t.in_addr()
  addr.s_addr = ip4[4] * 0x1000000 + ip4[3] * 0x10000 + ip4[2] * 0x100 + ip4[1]
  return addr
end

local function inet6_pton(src, addr)
-- TODO ipv6 implementation
  local ret = ffi.C.inet_pton(c.AF.INET6, src, addr) -- TODO redo in pure Lua
  if ret == -1 then return nil, t.error() end
  if ret == 0 then return nil end -- maybe return string
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

addtype("in_addr", "struct in_addr", {
  __tostring = inet4_ntop,
  __new = function(tp, s)
    local addr = ffi.new(tp)
    if s then
      if ffi.istype(tp, s) then
        addr.s_addr = s.s_addr
      else
        if inaddr[s] then s = inaddr[s] end
        addr = inet4_pton(s, addr)
        if not addr then return nil end
      end
    end
    return addr
  end,
  __len = lenfn,
})

addtype("in6_addr", "struct in6_addr", {
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
})

return {t = t, pt = pt, s = s, ctypes = ctypes}

