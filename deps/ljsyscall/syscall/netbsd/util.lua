-- NetBSD utility functions

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(S)

local abi, types, c = S.abi, S.types, S.c
local t, pt, s = types.t, types.pt, types.s

local h = require "syscall.helpers"
local divmod = h.divmod

local ffi = require "ffi"

local bit = require "syscall.bit"

local octal = h.octal

-- TODO move to helpers? see notes in syscall.lua about reworking though
local function istype(tp, x)
  if ffi.istype(tp, x) then return x end
  return false
end

local util = {}

local mt = {}

-- initial implementation of network ioctls, no real attempt to make it compatible with Linux...
-- initially just implement the ones from rump netconfig, make interface later

-- it is a bit messy creating new socket every time, better make a sequence of commands

local function sockioctl(domain, tp, io, data)
  local sock, err = S.socket(domain, tp)
  if not sock then return nil, err end
  local io, err = sock:ioctl(io, data)
  sock:close()
  if not io then return nil, err end
  return io
end

function util.ifcreate(name) return sockioctl("inet", "dgram", "SIOCIFCREATE", t.ifreq{name = name}) end
function util.ifdestroy(name) return sockioctl("inet", "dgram", "SIOCIFDESTROY", t.ifreq{name = name}) end
function util.ifgetflags(name)
  local io, err = sockioctl("inet", "dgram", "SIOCGIFFLAGS", t.ifreq{name = name})
  if not io then return nil, err end
  return io.flags
end
function util.ifsetflags(name, flags)
  return sockioctl("inet", "dgram", "SIOCSIFFLAGS", {name = name, flags = c.IFF[flags]})
end
function util.ifup(name)
  local flags, err = util.ifgetflags(name)
  if not flags then return nil, err end
  return util.ifsetflags(name, c.IFF(flags, "up"))
end
function util.ifdown(name)
  local flags, err = util.ifgetflags(name)
  if not flags then return nil, err end
  return util.ifsetflags(name, c.IFF(flags, "~up"))
end

function util.ifsetlinkstr(name, str) -- used to pass (optional) string to rump virtif (eg name of underlying tap device)
  return sockioctl("inet", "dgram", "SIOCSLINKSTR", {name = name, cmd = 0, data = str})
end

-- TODO merge into one ifaddr function
function util.ifaddr_inet4(name, addr, mask)
-- TODO this function needs mask as an inaddr, so need to fix this if passed as / format or number
  local addr, mask = util.inet_name(addr, mask)

  local bn = addr:get_mask_bcast(mask)
  local broadcast, netmask = bn.broadcast, bn.netmask

  local ia = t.ifaliasreq{name = name, addr = addr, mask = netmask, broadaddr = broadcast}

  return sockioctl("inet", "dgram", "SIOCAIFADDR", ia)
end
function util.ifaddr_inet6(name, addr, mask)
  local addr, mask = util.inet_name(addr, mask)
  assert(ffi.istype(t.in6_addr, addr), "not an ipv6 address") -- TODO remove once merged

  local prefixmask = t.in6_addr()
  local bb, b = divmod(mask, 8)
  for i = 0, bb - 1 do prefixmask.s6_addr[i] = 0xff end
  if bb < 16 then prefixmask.s6_addr[bb] = bit.lshift(0xff, 8 - b) end -- TODO needs test!

  local ia = t.in6_aliasreq{name = name, addr = addr, prefixmask = prefixmask,
                            lifetime = {pltime = "infinite_lifetime", vltime = "infinite_lifetime"}}

  return sockioctl("inet6", "dgram", "SIOCAIFADDR_IN6", ia)
end

-- table based mount, more cross OS compatible
function util.mount(tab)
  local filesystemtype = tab.type
  local dir = tab.target or tab.dir
  local flags = tab.flags
  local data = tab.data
  local datalen = tab.datalen
  if tab.fspec then data = tab.fspec end
  return S.mount(filesystemtype, dir, flags, data, datalen)
end

local function kdumpfn(len)
  return function(buf, pos)
    if pos + s.ktr_header >= len then return nil end
    local ktr = pt.ktr_header(buf + pos)
    if pos + s.ktr_header + ktr.len >= len then return nil end
    return pos + #ktr, ktr
  end
end

function util.kdump(buf, len)
  return kdumpfn(len), buf, 0
end

local function do_bridge_setcmd(name, op, arg)
  return sockioctl("inet", "dgram", "SIOCSDRVSPEC", {name = name, cms = op, data = arg})
end
local function do_bridge_getcmd(name, op, arg) -- TODO should allocate correct arg type here based on arg
  local data, err = sockioctl("inet", "dgram", "SIOCGDRVSPEC", {name = name, cms = op, data = arg})
  if not data then return nil, err end
  return arg
end

return util

end

return {init = init}

