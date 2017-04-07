-- modularize netlink code as it is large and standalone

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(S)

local nl = {} -- exports

local ffi = require "ffi"
local bit = require "syscall.bit"

local h = require "syscall.helpers"

local util = S.util

local types = S.types
local c = S.c

local htonl = h.htonl
local align = h.align

local t, pt, s = types.t, types.pt, types.s

local adtt = {
  [c.AF.INET] = t.in_addr,
  [c.AF.INET6] = t.in6_addr,
}

local function addrtype(af)
  local tp = adtt[tonumber(af)]
  if not tp then error("bad address family") end
  return tp()
end

local function mktype(tp, x) if ffi.istype(tp, x) then return x else return tp(x) end end

local mt = {} -- metatables
local meth = {}

-- similar functions for netlink messages
local function nlmsg_align(len) return align(len, 4) end
local nlmsg_hdrlen = nlmsg_align(s.nlmsghdr)
local function nlmsg_length(len) return len + nlmsg_hdrlen end
local function nlmsg_ok(msg, len)
  return len >= nlmsg_hdrlen and msg.nlmsg_len >= nlmsg_hdrlen and msg.nlmsg_len <= len
end
local function nlmsg_next(msg, buf, len)
  local inc = nlmsg_align(msg.nlmsg_len)
  return pt.nlmsghdr(buf + inc), buf + inc, len - inc
end

local rta_align = nlmsg_align -- also 4 byte align
local function rta_length(len) return len + rta_align(s.rtattr) end
local function rta_ok(msg, len)
  return len >= s.rtattr and msg.rta_len >= s.rtattr and msg.rta_len <= len
end
local function rta_next(msg, buf, len)
  local inc = rta_align(msg.rta_len)
  return pt.rtattr(buf + inc), buf + inc, len - inc
end

local addrlenmap = { -- map interface type to length of hardware address TODO are these always same?
  [c.ARPHRD.ETHER] = 6,
  [c.ARPHRD.EETHER] = 6,
  [c.ARPHRD.LOOPBACK] = 6,
}

local ifla_decode = {
  [c.IFLA.IFNAME] = function(ir, buf, len)
    ir.name = ffi.string(buf)
  end,
  [c.IFLA.ADDRESS] = function(ir, buf, len)
    local addrlen = addrlenmap[ir.type]
    if (addrlen) then
      ir.addrlen = addrlen
      ir.macaddr = t.macaddr()
      ffi.copy(ir.macaddr, buf, addrlen)
    end
  end,
  [c.IFLA.BROADCAST] = function(ir, buf, len)
    local addrlen = addrlenmap[ir.type] -- TODO always same
    if (addrlen) then
      ir.broadcast = t.macaddr()
      ffi.copy(ir.broadcast, buf, addrlen)
    end
  end,
  [c.IFLA.MTU] = function(ir, buf, len)
    local u = pt.uint(buf)
    ir.mtu = tonumber(u[0])
  end,
  [c.IFLA.LINK] = function(ir, buf, len)
    local i = pt.int(buf)
    ir.link = tonumber(i[0])
  end,
  [c.IFLA.QDISC] = function(ir, buf, len)
    ir.qdisc = ffi.string(buf)
  end,
  [c.IFLA.STATS] = function(ir, buf, len)
    ir.stats = t.rtnl_link_stats() -- despite man page, this is what kernel uses. So only get 32 bit stats here.
    ffi.copy(ir.stats, buf, s.rtnl_link_stats)
  end
}

local ifa_decode = {
  [c.IFA.ADDRESS] = function(ir, buf, len)
    ir.addr = addrtype(ir.family)
    ffi.copy(ir.addr, buf, ffi.sizeof(ir.addr))
  end,
  [c.IFA.LOCAL] = function(ir, buf, len)
    ir.loc = addrtype(ir.family)
    ffi.copy(ir.loc, buf, ffi.sizeof(ir.loc))
  end,
  [c.IFA.BROADCAST] = function(ir, buf, len)
    ir.broadcast = addrtype(ir.family)
    ffi.copy(ir.broadcast, buf, ffi.sizeof(ir.broadcast))
  end,
  [c.IFA.LABEL] = function(ir, buf, len)
    ir.label = ffi.string(buf)
  end,
  [c.IFA.ANYCAST] = function(ir, buf, len)
    ir.anycast = addrtype(ir.family)
    ffi.copy(ir.anycast, buf, ffi.sizeof(ir.anycast))
  end,
  [c.IFA.CACHEINFO] = function(ir, buf, len)
    ir.cacheinfo = t.ifa_cacheinfo()
    ffi.copy(ir.cacheinfo, buf, ffi.sizeof(t.ifa_cacheinfo))
  end,
}

local rta_decode = {
  [c.RTA.DST] = function(ir, buf, len)
    ir.dst = addrtype(ir.family)
    ffi.copy(ir.dst, buf, ffi.sizeof(ir.dst))
  end,
  [c.RTA.SRC] = function(ir, buf, len)
    ir.src = addrtype(ir.family)
    ffi.copy(ir.src, buf, ffi.sizeof(ir.src))
  end,
  [c.RTA.IIF] = function(ir, buf, len)
    local i = pt.int(buf)
    ir.iif = tonumber(i[0])
  end,
  [c.RTA.OIF] = function(ir, buf, len)
    local i = pt.int(buf)
    ir.oif = tonumber(i[0])
  end,
  [c.RTA.GATEWAY] = function(ir, buf, len)
    ir.gateway = addrtype(ir.family)
    ffi.copy(ir.gateway, buf, ffi.sizeof(ir.gateway))
  end,
  [c.RTA.PRIORITY] = function(ir, buf, len)
    local i = pt.int(buf)
    ir.priority = tonumber(i[0])
  end,
  [c.RTA.PREFSRC] = function(ir, buf, len)
    local i = pt.uint32(buf)
    ir.prefsrc = tonumber(i[0])
  end,
  [c.RTA.METRICS] = function(ir, buf, len)
    local i = pt.int(buf)
    ir.metrics = tonumber(i[0])
  end,
  [c.RTA.TABLE] = function(ir, buf, len)
    local i = pt.uint32(buf)
    ir.table = tonumber(i[0])
  end,
  [c.RTA.CACHEINFO] = function(ir, buf, len)
    ir.cacheinfo = t.rta_cacheinfo()
    ffi.copy(ir.cacheinfo, buf, s.rta_cacheinfo)
  end,
  [c.RTA.PREF] = function(ir, buf, len)
    local i = pt.uint8(buf)
    ir.pref = tonumber(i[0])
  end,
  -- TODO some missing
}

local nda_decode = {
  [c.NDA.DST] = function(ir, buf, len)
    ir.dst = addrtype(ir.family)
    ffi.copy(ir.dst, buf, ffi.sizeof(ir.dst))
  end,
  [c.NDA.LLADDR] = function(ir, buf, len)
    ir.lladdr = t.macaddr()
    ffi.copy(ir.lladdr, buf, s.macaddr)
  end,
  [c.NDA.CACHEINFO] = function(ir, buf, len)
     ir.cacheinfo = t.nda_cacheinfo()
     ffi.copy(ir.cacheinfo, buf, s.nda_cacheinfo)
  end,
  [c.NDA.PROBES] = function(ir, buf, len)
     -- TODO what is this? 4 bytes
  end,
}

local ifflist = {}
for k, _ in pairs(c.IFF) do ifflist[#ifflist + 1] = k end

mt.iff = {
  __tostring = function(f)
    local s = {}
    for _, k in pairs(ifflist) do if bit.band(f.flags, c.IFF[k]) ~= 0 then s[#s + 1] = k end end
    return table.concat(s, ' ')
  end,
  __index = function(f, k)
    if c.IFF[k] then return bit.band(f.flags, c.IFF[k]) ~= 0 end
  end
}

nl.encapnames = {
  [c.ARPHRD.ETHER] = "Ethernet",
  [c.ARPHRD.LOOPBACK] = "Local Loopback",
}

meth.iflinks = {
  fn = {
    refresh = function(i)
      local j, err = nl.interfaces()
      if not j then return nil, err end
      for k, _ in pairs(i) do i[k] = nil end
      for k, v in pairs(j) do i[k] = v end
      return i
    end,
  },
}

mt.iflinks = {
  __index = function(i, k)
    if meth.iflinks.fn[k] then return meth.iflinks.fn[k] end
  end,
  __tostring = function(is)
    local s = {}
    for _, v in ipairs(is) do
      s[#s + 1] = tostring(v)
    end
    return table.concat(s, '\n')
  end
}

meth.iflink = {
  index = {
    family = function(i) return tonumber(i.ifinfo.ifi_family) end,
    type = function(i) return tonumber(i.ifinfo.ifi_type) end,
    typename = function(i)
      local n = nl.encapnames[i.type]
      return n or 'unknown ' .. i.type
    end,
    index = function(i) return tonumber(i.ifinfo.ifi_index) end,
    flags = function(i) return setmetatable({flags = tonumber(i.ifinfo.ifi_flags)}, mt.iff) end,
    change = function(i) return tonumber(i.ifinfo.ifi_change) end,
  },
  fn = {
    setflags = function(i, flags, change)
      local ok, err = nl.newlink(i, 0, flags, change or c.IFF.ALL)
      if not ok then return nil, err end
      return i:refresh()
    end,
    up = function(i) return i:setflags("up", "up") end,
    down = function(i) return i:setflags("", "up") end,
    setmtu = function(i, mtu)
      local ok, err = nl.newlink(i.index, 0, 0, 0, "mtu", mtu)
      if not ok then return nil, err end
      return i:refresh()
    end,
    setmac = function(i, mac)
      local ok, err = nl.newlink(i.index, 0, 0, 0, "address", mac)
      if not ok then return nil, err end
      return i:refresh()
    end,
    address = function(i, address, netmask) -- add address
      if type(address) == "string" then address, netmask = util.inet_name(address, netmask) end
      if not address then return nil end
      local ok, err
      if ffi.istype(t.in6_addr, address) then
        ok, err = nl.newaddr(i.index, c.AF.INET6, netmask, "permanent", "local", address)
      else
        local broadcast = address:get_mask_bcast(netmask).broadcast
        ok, err = nl.newaddr(i.index, c.AF.INET, netmask, "permanent", "local", address, "broadcast", broadcast)
      end
      if not ok then return nil, err end
      return i:refresh()
    end,
    deladdress = function(i, address, netmask)
      if type(address) == "string" then address, netmask = util.inet_name(address, netmask) end
      if not address then return nil end
      local af
      if ffi.istype(t.in6_addr, address) then af = c.AF.INET6 else af = c.AF.INET end
      local ok, err = nl.deladdr(i.index, af, netmask, "local", address)
      if not ok then return nil, err end
      return i:refresh()
    end,
    delete = function(i)
      local ok, err = nl.dellink(i.index)
      if not ok then return nil, err end
      return true     
    end,
    move_ns = function(i, ns) -- TODO also support file descriptor form as well as pid
      local ok, err = nl.newlink(i.index, 0, 0, 0, "net_ns_pid", ns)
      if not ok then return nil, err end
      return true -- no longer here so cannot refresh
    end,
    rename = function(i, name)
      local ok, err = nl.newlink(i.index, 0, 0, 0, "ifname", name)
      if not ok then return nil, err end
      i.name = name -- refresh not working otherwise as done by name TODO fix so by index
      return i:refresh()
    end,
    refresh = function(i)
      local j, err = nl.interface(i.name)
      if not j then return nil, err end
      for k, _ in pairs(i) do i[k] = nil end
      for k, v in pairs(j) do i[k] = v end
      return i
    end,
  }
}

mt.iflink = {
  __index = function(i, k)
    if meth.iflink.index[k] then return meth.iflink.index[k](i) end
    if meth.iflink.fn[k] then return meth.iflink.fn[k] end
    if k == "inet" or k == "inet6" then return end -- might not be set, as we add it, kernel does not provide
    if c.ARPHRD[k] then return i.ifinfo.ifi_type == c.ARPHRD[k] end
  end,
  __tostring = function(i)
    local hw = ''
    if not i.loopback and i.macaddr then hw = '  HWaddr ' .. tostring(i.macaddr) end
    local s = i.name .. string.rep(' ', 10 - #i.name) .. 'Link encap:' .. i.typename .. hw .. '\n'
    if i.inet then for a = 1, #i.inet do
      s = s .. '          ' .. 'inet addr: ' .. tostring(i.inet[a].addr) .. '/' .. i.inet[a].prefixlen .. '\n'
    end end
    if i.inet6 then for a = 1, #i.inet6 do
      s = s .. '          ' .. 'inet6 addr: ' .. tostring(i.inet6[a].addr) .. '/' .. i.inet6[a].prefixlen .. '\n'
    end end
      s = s .. '          ' .. tostring(i.flags) .. '  MTU: ' .. i.mtu .. '\n'
      s = s .. '          ' .. 'RX packets:' .. i.stats.rx_packets .. ' errors:' .. i.stats.rx_errors .. ' dropped:' .. i.stats.rx_dropped .. '\n'
      s = s .. '          ' .. 'TX packets:' .. i.stats.tx_packets .. ' errors:' .. i.stats.tx_errors .. ' dropped:' .. i.stats.tx_dropped .. '\n'
    return s
  end
}

meth.rtmsg = {
  index = {
    family = function(i) return tonumber(i.rtmsg.rtm_family) end,
    dst_len = function(i) return tonumber(i.rtmsg.rtm_dst_len) end,
    src_len = function(i) return tonumber(i.rtmsg.rtm_src_len) end,
    index = function(i) return tonumber(i.oif) end,
    flags = function(i) return tonumber(i.rtmsg.rtm_flags) end,
    dest = function(i) return i.dst or addrtype(i.family) end,
    source = function(i) return i.src or addrtype(i.family) end,
    gw = function(i) return i.gateway or addrtype(i.family) end,
    -- might not be set in Lua table, so return nil
    iif = function() return nil end,
    oif = function() return nil end,
    src = function() return nil end,
    dst = function() return nil end,
  },
  flags = { -- TODO rework so iterates in fixed order. TODO Do not seem to be set, find how to retrieve.
    [c.RTF.UP] = "U",
    [c.RTF.GATEWAY] = "G",
    [c.RTF.HOST] = "H",
    [c.RTF.REINSTATE] = "R",
    [c.RTF.DYNAMIC] = "D",
    [c.RTF.MODIFIED] = "M",
    [c.RTF.REJECT] = "!",
  }
}

mt.rtmsg = {
  __index = function(i, k)
    if meth.rtmsg.index[k] then return meth.rtmsg.index[k](i) end
    -- if S.RTF[k] then return bit.band(i.flags, S.RTF[k]) ~= 0 end -- TODO see above
  end,
  __tostring = function(i) -- TODO make more like output of ip route
    local s = "dst: " .. tostring(i.dest) .. "/" .. i.dst_len .. " gateway: " .. tostring(i.gw) .. " src: " .. tostring(i.source) .. "/" .. i.src_len .. " if: " .. (i.output or i.oif)
    return s
  end,
}

meth.routes = {
  fn = {
    match = function(rs, addr, len) -- exact match
      if type(addr) == "string" then
        local sl = addr:find("/", 1, true)
        if sl then
          len = tonumber(addr:sub(sl + 1))
          addr = addr:sub(1, sl - 1)
        end
        if rs.family == c.AF.INET6 then addr = t.in6_addr(addr) else addr = t.in_addr(addr) end
      end
      local matches = {}
      for _, v in ipairs(rs) do
        if len == v.dst_len then
          if v.family == c.AF.INET then
            if addr.s_addr == v.dest.s_addr then matches[#matches + 1] = v end
          else
            local match = true
            for i = 0, 15 do
              if addr.s6_addr[i] ~= v.dest.s6_addr[i] then match = false end
            end
            if match then matches[#matches + 1] = v end
          end
        end
      end
      matches.tp, matches.family = rs.tp, rs.family
      return setmetatable(matches, mt.routes)
    end,
    refresh = function(rs)
      local nr = nl.routes(rs.family, rs.tp)
      for k, _ in pairs(rs) do rs[k] = nil end
      for k, v in pairs(nr) do rs[k] = v end
      return rs
    end,
  }
}

mt.routes = {
  __index = function(i, k)
    if meth.routes.fn[k] then return meth.routes.fn[k] end
  end,
  __tostring = function(is)
    local s = {}
    for k, v in ipairs(is) do
      s[#s + 1] = tostring(v)
    end
    return table.concat(s, '\n')
  end,
}

meth.ifaddr = {
  index = {
    family = function(i) return tonumber(i.ifaddr.ifa_family) end,
    prefixlen = function(i) return tonumber(i.ifaddr.ifa_prefixlen) end,
    index = function(i) return tonumber(i.ifaddr.ifa_index) end,
    flags = function(i) return tonumber(i.ifaddr.ifa_flags) end,
    scope = function(i) return tonumber(i.ifaddr.ifa_scope) end,
  }
}

mt.ifaddr = {
  __index = function(i, k)
    if meth.ifaddr.index[k] then return meth.ifaddr.index[k](i) end
    if c.IFA_F[k] then return bit.band(i.ifaddr.ifa_flags, c.IFA_F[k]) ~= 0 end
  end
}

-- TODO functions repetitious
local function decode_link(buf, len)
  local iface = pt.ifinfomsg(buf)
  buf = buf + nlmsg_align(s.ifinfomsg)
  len = len - nlmsg_align(s.ifinfomsg)
  local rtattr = pt.rtattr(buf)
  local ir = setmetatable({ifinfo = t.ifinfomsg()}, mt.iflink)
  ffi.copy(ir.ifinfo, iface, s.ifinfomsg)
  while rta_ok(rtattr, len) do
    if ifla_decode[rtattr.rta_type] then
      ifla_decode[rtattr.rta_type](ir, buf + rta_length(0), rta_align(rtattr.rta_len) - rta_length(0))
    end
    rtattr, buf, len = rta_next(rtattr, buf, len)
  end
  return ir
end

local function decode_address(buf, len)
  local addr = pt.ifaddrmsg(buf)
  buf = buf + nlmsg_align(s.ifaddrmsg)
  len = len - nlmsg_align(s.ifaddrmsg)
  local rtattr = pt.rtattr(buf)
  local ir = setmetatable({ifaddr = t.ifaddrmsg(), addr = {}}, mt.ifaddr)
  ffi.copy(ir.ifaddr, addr, s.ifaddrmsg)
  while rta_ok(rtattr, len) do
    if ifa_decode[rtattr.rta_type] then
      ifa_decode[rtattr.rta_type](ir, buf + rta_length(0), rta_align(rtattr.rta_len) - rta_length(0))
    end
    rtattr, buf, len = rta_next(rtattr, buf, len)
  end
  return ir
end

local function decode_route(buf, len)
  local rt = pt.rtmsg(buf)
  buf = buf + nlmsg_align(s.rtmsg)
  len = len - nlmsg_align(s.rtmsg)
  local rtattr = pt.rtattr(buf)
  local ir = setmetatable({rtmsg = t.rtmsg()}, mt.rtmsg)
  ffi.copy(ir.rtmsg, rt, s.rtmsg)
  while rta_ok(rtattr, len) do
    if rta_decode[rtattr.rta_type] then
      rta_decode[rtattr.rta_type](ir, buf + rta_length(0), rta_align(rtattr.rta_len) - rta_length(0))
    else error("NYI: " .. rtattr.rta_type)
    end
    rtattr, buf, len = rta_next(rtattr, buf, len)
  end
  return ir
end

local function decode_neigh(buf, len)
  local rt = pt.rtmsg(buf)
  buf = buf + nlmsg_align(s.rtmsg)
  len = len - nlmsg_align(s.rtmsg)
  local rtattr = pt.rtattr(buf)
  local ir = setmetatable({rtmsg = t.rtmsg()}, mt.rtmsg)
  ffi.copy(ir.rtmsg, rt, s.rtmsg)
  while rta_ok(rtattr, len) do
    if nda_decode[rtattr.rta_type] then
      nda_decode[rtattr.rta_type](ir, buf + rta_length(0), rta_align(rtattr.rta_len) - rta_length(0))
    else error("NYI: " .. rtattr.rta_type)
    end
    rtattr, buf, len = rta_next(rtattr, buf, len)
  end
  return ir
end

-- TODO other than the first few these could be a table
local nlmsg_data_decode = {
  [c.NLMSG.NOOP] = function(r, buf, len) return r end,
  [c.NLMSG.ERROR] = function(r, buf, len)
    local e = pt.nlmsgerr(buf)
    if e.error ~= 0 then r.error = t.error(-e.error) else r.ack = true end -- error zero is ACK, others negative
    return r
  end,
  [c.NLMSG.DONE] = function(r, buf, len) return r end,
  [c.NLMSG.OVERRUN] = function(r, buf, len)
    r.overrun = true
    return r
  end,
  [c.RTM.NEWADDR] = function(r, buf, len)
    local ir = decode_address(buf, len)
    ir.op, ir.newaddr, ir.nl = "newaddr", true, c.RTM.NEWADDR
    r[#r + 1] = ir
    return r
  end,
  [c.RTM.DELADDR] = function(r, buf, len)
    local ir = decode_address(buf, len)
    ir.op, ir.deladdr, ir.nl = "delddr", true, c.RTM.DELADDR
    r[#r + 1] = ir
    return r
  end,
  [c.RTM.GETADDR] = function(r, buf, len)
    local ir = decode_address(buf, len)
    ir.op, ir.getaddr, ir.nl = "getaddr", true, c.RTM.GETADDR
    r[#r + 1] = ir
    return r
  end,
  [c.RTM.NEWLINK] = function(r, buf, len)
    local ir = decode_link(buf, len)
    ir.op, ir.newlink, ir.nl = "newlink", true, c.RTM.NEWLINK
    r[ir.name] = ir
    r[#r + 1] = ir
    return r
  end,
  [c.RTM.DELLINK] = function(r, buf, len)
    local ir = decode_link(buf, len)
    ir.op, ir.dellink, ir.nl = "dellink", true, c.RTM.DELLINK
    r[ir.name] = ir
    r[#r + 1] = ir
    return r
  end,
  -- TODO need test that returns these, assume updates do
  [c.RTM.GETLINK] = function(r, buf, len)
    local ir = decode_link(buf, len)
    ir.op, ir.getlink, ir.nl = "getlink", true, c.RTM.GETLINK
    r[ir.name] = ir
    r[#r + 1] = ir
    return r
  end,
  [c.RTM.NEWROUTE] = function(r, buf, len)
    local ir = decode_route(buf, len)
    ir.op, ir.newroute, ir.nl = "newroute", true, c.RTM.NEWROUTE
    r[#r + 1] = ir
    return r
  end,
  [c.RTM.DELROUTE] = function(r, buf, len)
    local ir = decode_route(buf, len)
    ir.op, ir.delroute, ir.nl = "delroute", true, c.RTM.DELROUTE
    r[#r + 1] = ir
    return r
  end,
  [c.RTM.GETROUTE] = function(r, buf, len)
    local ir = decode_route(buf, len)
    ir.op, ir.getroute, ir.nl = "getroute", true, c.RTM.GETROUTE
    r[#r + 1] = ir
    return r
  end,
  [c.RTM.NEWNEIGH] = function(r, buf, len)
    local ir = decode_neigh(buf, len)
    ir.op, ir.newneigh, ir.nl = "newneigh", true, c.RTM.NEWNEIGH
    r[#r + 1] = ir
    return r
  end,
  [c.RTM.DELNEIGH] = function(r, buf, len)
    local ir = decode_neigh(buf, len)
    ir.op, ir.delneigh, ir.nl = "delneigh", true, c.RTM.DELNEIGH
    r[#r + 1] = ir
    return r
  end,
  [c.RTM.GETNEIGH] = function(r, buf, len)
    local ir = decode_neigh(buf, len)
    ir.op, ir.getneigh, ir.nl = "getneigh", true, c.RTM.GETNEIGH
    r[#r + 1] = ir
    return r
  end,
}

function nl.read(s, addr, bufsize, untildone)
  addr = addr or t.sockaddr_nl() -- default to kernel
  bufsize = bufsize or 8192
  local reply = t.buffer(bufsize)
  local ior = t.iovecs{{reply, bufsize}}
  local m = t.msghdr{msg_iov = ior.iov, msg_iovlen = #ior, msg_name = addr, msg_namelen = ffi.sizeof(addr)}

  local done = false -- what should we do if we get a done message but there is some extra buffer? could be next message...
  local r = {}

  while not done do
    local len, err = s:recvmsg(m)
    if not len then return nil, err end
    local buffer = reply

    local msg = pt.nlmsghdr(buffer)

    while not done and nlmsg_ok(msg, len) do
      local tp = tonumber(msg.nlmsg_type)

      if nlmsg_data_decode[tp] then
        r = nlmsg_data_decode[tp](r, buffer + nlmsg_hdrlen, msg.nlmsg_len - nlmsg_hdrlen)

        if r.overrun then return S.read(s, addr, bufsize * 2) end -- TODO add test
        if r.error then return nil, r.error end -- not sure what the errors mean though!
        if r.ack then done = true end

      else error("unknown data " .. tp)
      end

      if tp == c.NLMSG.DONE then done = true end
      msg, buffer, len = nlmsg_next(msg, buffer, len)
    end
    if not untildone then done = true end
  end

  return r
end

-- TODO share with read side
local ifla_msg_types = {
  ifla = {
    -- IFLA.UNSPEC
    [c.IFLA.ADDRESS] = t.macaddr,
    [c.IFLA.BROADCAST] = t.macaddr,
    [c.IFLA.IFNAME] = "asciiz",
    -- TODO IFLA.MAP
    [c.IFLA.MTU] = t.uint32,
    [c.IFLA.LINK] = t.uint32,
    [c.IFLA.MASTER] = t.uint32,
    [c.IFLA.TXQLEN] = t.uint32,
    [c.IFLA.WEIGHT] = t.uint32,
    [c.IFLA.OPERSTATE] = t.uint8,
    [c.IFLA.LINKMODE] = t.uint8,
    [c.IFLA.LINKINFO] = {"ifla_info", c.IFLA_INFO},
    [c.IFLA.NET_NS_PID] = t.uint32,
    [c.IFLA.NET_NS_FD] = t.uint32,
    [c.IFLA.IFALIAS] = "asciiz",
    --[c.IFLA.VFINFO_LIST] = "nested",
    --[c.IFLA.VF_PORTS] = "nested",
    --[c.IFLA.PORT_SELF] = "nested",
    --[c.IFLA.AF_SPEC] = "nested",
  },
  ifla_info = {
    [c.IFLA_INFO.KIND] = "ascii",
    [c.IFLA_INFO.DATA] = "kind",
  },
  ifla_vlan = {
    [c.IFLA_VLAN.ID] = t.uint16,
    -- other vlan params
  },
  ifa = {
    -- IFA.UNSPEC
    [c.IFA.ADDRESS] = "address",
    [c.IFA.LOCAL] = "address",
    [c.IFA.LABEL] = "asciiz",
    [c.IFA.BROADCAST] = "address",
    [c.IFA.ANYCAST] = "address",
    -- IFA.CACHEINFO
  },
  rta = {
    -- RTA_UNSPEC
    [c.RTA.DST] = "address",
    [c.RTA.SRC] = "address",
    [c.RTA.IIF] = t.uint32,
    [c.RTA.OIF] = t.uint32,
    [c.RTA.GATEWAY] = "address",
    [c.RTA.PRIORITY] = t.uint32,
    [c.RTA.METRICS] = t.uint32,
    --          RTA.PREFSRC
    --          RTA.MULTIPATH
    --          RTA.PROTOINFO
    --          RTA.FLOW
    --          RTA.CACHEINFO
  },
  veth_info = {
    -- VETH_INFO_UNSPEC
    [c.VETH_INFO.PEER] = {"ifla", c.IFLA},
  },
  nda = {
    [c.NDA.DST]       = "address",
    [c.NDA.LLADDR]    = t.macaddr,
    [c.NDA.CACHEINFO] = t.nda_cacheinfo,
--    [c.NDA.PROBES] = ,
  },
}

--[[ TODO add
static const struct nla_policy ifla_vfinfo_policy[IFLA_VF_INFO_MAX+1] = {
        [IFLA_VF_INFO]          = { .type = NLA_NESTED },
};

static const struct nla_policy ifla_vf_policy[IFLA_VF_MAX+1] = {
        [IFLA_VF_MAC]           = { .type = NLA_BINARY,
                                    .len = sizeof(struct ifla_vf_mac) },
        [IFLA_VF_VLAN]          = { .type = NLA_BINARY,
                                    .len = sizeof(struct ifla_vf_vlan) },
        [IFLA_VF_TX_RATE]       = { .type = NLA_BINARY,
                                    .len = sizeof(struct ifla_vf_tx_rate) },
        [IFLA_VF_SPOOFCHK]      = { .type = NLA_BINARY,
                                    .len = sizeof(struct ifla_vf_spoofchk) },
};

static const struct nla_policy ifla_port_policy[IFLA_PORT_MAX+1] = {
        [IFLA_PORT_VF]          = { .type = NLA_U32 },
        [IFLA_PORT_PROFILE]     = { .type = NLA_STRING,
                                    .len = PORT_PROFILE_MAX },
        [IFLA_PORT_VSI_TYPE]    = { .type = NLA_BINARY,
                                    .len = sizeof(struct ifla_port_vsi)},
        [IFLA_PORT_INSTANCE_UUID] = { .type = NLA_BINARY,
                                      .len = PORT_UUID_MAX },
        [IFLA_PORT_HOST_UUID]   = { .type = NLA_STRING,
                                    .len = PORT_UUID_MAX },
        [IFLA_PORT_REQUEST]     = { .type = NLA_U8, },
        [IFLA_PORT_RESPONSE]    = { .type = NLA_U16, },
};
]]

local function ifla_getmsg(args, messages, values, tab, lookup, kind, af)
  local msg = table.remove(args, 1)
  local value, len
  local tp

  if type(msg) == "table" then -- for nested attributes
    local nargs = msg
    len = 0
    while #nargs ~= 0 do
      local nlen
      nlen, nargs, messages, values, kind = ifla_getmsg(nargs, messages, values, tab, lookup, kind, af)
      len = len + nlen
    end
    return len, args, messages, values, kind
  end

  if type(msg) == "cdata" or type(msg) == "userdata" then
    tp = msg
    value = table.remove(args, 1)
    if not value then error("not enough arguments") end
    value = mktype(tp, value)
    len = ffi.sizeof(value)
    messages[#messages + 1] = tp
    values[#values + 1] = value
    return len, args, messages, values, kind
  end

  local rawmsg = msg
  msg = lookup[msg]

  tp = ifla_msg_types[tab][msg]
  if not tp then error("unknown message type " .. tostring(rawmsg) .. " in " .. tab) end

  if tp == "kind" then
    local kinds = {
      vlan = {"ifla_vlan", c.IFLA_VLAN},
      veth = {"veth_info", c.VETH_INFO},
    }
    tp = kinds[kind]
  end

  if type(tp) == "table" then
    value = t.rtattr{rta_type = msg} -- missing rta_len, but have reference and can fix

    messages[#messages + 1] = t.rtattr
    values[#values + 1] = value

    tab, lookup = tp[1], tp[2]

    len, args, messages, values, kind = ifla_getmsg(args, messages, values, tab, lookup, kind, af)
    len = nlmsg_align(s.rtattr) + len

    value.rta_len = len

    return len, args, messages, values, kind

  -- recursion base case, just a value, not nested

  else
    value = table.remove(args, 1)
    if not value then error("not enough arguments") end
  end

  if tab == "ifla_info" and msg == c.IFLA_INFO.KIND then
    kind = value
  end

  local slen

  if tp == "asciiz" then -- zero terminated
    tp = t.buffer(#value + 1)
    slen = nlmsg_align(s.rtattr) + #value + 1
  elseif tp == "ascii" then -- not zero terminated
    tp = t.buffer(#value)
    slen = nlmsg_align(s.rtattr) + #value
  else
    if tp == "address" then
      tp = adtt[tonumber(af)]
    end
    value = mktype(tp, value)
  end

  len = nlmsg_align(s.rtattr) + nlmsg_align(ffi.sizeof(tp))
  slen = slen or len

  messages[#messages + 1] = t.rtattr
  messages[#messages + 1] = tp
  values[#values + 1] = t.rtattr{rta_type = msg, rta_len = slen}
  values[#values + 1] = value

  return len, args, messages, values, kind
end

local function ifla_f(tab, lookup, af, ...)
  local len, kind
  local messages, values = {t.nlmsghdr}, {false}

  local args = {...}
  while #args ~= 0 do
    len, args, messages, values, kind = ifla_getmsg(args, messages, values, tab, lookup, kind, af)
  end

  local len = 0
  local offsets = {}
  local alignment = nlmsg_align(1)
  for i, tp in ipairs(messages) do
    local item_alignment = align(ffi.sizeof(tp), alignment)
    offsets[i] = len
    len = len + item_alignment
  end
  local buf = t.buffer(len)

  for i = 2, #offsets do -- skip header
    local value = values[i]
    if type(value) == "string" then
      ffi.copy(buf + offsets[i], value)
    else
      -- slightly nasty
      if ffi.istype(t.uint32, value) then value = t.uint32_1(value) end
      if ffi.istype(t.uint16, value) then value = t.uint16_1(value) end
      if ffi.istype(t.uint8, value) then value = t.uint8_1(value) end
      ffi.copy(buf + offsets[i], value, ffi.sizeof(value))
    end
  end

  return buf, len
end

local rtpref = {
  [c.RTM.NEWLINK] = {"ifla", c.IFLA},
  [c.RTM.GETLINK] = {"ifla", c.IFLA},
  [c.RTM.DELLINK] = {"ifla", c.IFLA},
  [c.RTM.NEWADDR] = {"ifa", c.IFA},
  [c.RTM.GETADDR] = {"ifa", c.IFA},
  [c.RTM.DELADDR] = {"ifa", c.IFA},
  [c.RTM.NEWROUTE] = {"rta", c.RTA},
  [c.RTM.GETROUTE] = {"rta", c.RTA},
  [c.RTM.DELROUTE] = {"rta", c.RTA},
  [c.RTM.NEWNEIGH] = {"nda", c.NDA},
  [c.RTM.DELNEIGH] = {"nda", c.NDA},
  [c.RTM.GETNEIGH] = {"nda", c.NDA},
  [c.RTM.NEWNEIGHTBL] = {"ndtpa", c.NDTPA},
  [c.RTM.GETNEIGHTBL] = {"ndtpa", c.NDTPA},
  [c.RTM.SETNEIGHTBL] = {"ndtpa", c.NDTPA},
}

function nl.socket(tp, addr)
  tp = c.NETLINK[tp]
  local sock, err = S.socket(c.AF.NETLINK, c.SOCK.RAW, tp)
  if not sock then return nil, err end
  if addr then
    if type(addr) == "table" then addr.type = tp end -- need type to convert group names from string
    if not ffi.istype(t.sockaddr_nl, addr) then addr = t.sockaddr_nl(addr) end
    local ok, err = S.bind(sock, addr)
    if not ok then
      S.close(sock)
      return nil, err
    end
  end
  return sock
end

function nl.write(sock, dest, ntype, flags, af, ...)
  local a, err = sock:getsockname() -- to get bound address
  if not a then return nil, err end

  dest = dest or t.sockaddr_nl() -- kernel destination default

  local tl = rtpref[ntype]
  if not tl then error("NYI: ", ntype) end
  local tab, lookup = tl[1], tl[2]

  local buf, len = ifla_f(tab, lookup, af, ...)

  local hdr = pt.nlmsghdr(buf)

  hdr[0] = {nlmsg_len = len, nlmsg_type = ntype, nlmsg_flags = flags, nlmsg_seq = sock:seq(), nlmsg_pid = a.pid}

  local ios = t.iovecs{{buf, len}}
  local m = t.msghdr{msg_iov = ios.iov, msg_iovlen = #ios, msg_name = dest, msg_namelen = s.sockaddr_nl}

  return sock:sendmsg(m)
end

-- TODO "route" should be passed in as parameter, test with other netlink types
local function nlmsg(ntype, flags, af, ...)
  ntype = c.RTM[ntype]
  flags = c.NLM_F[flags]
  local sock, err = nl.socket("route", {}) -- bind to empty sockaddr_nl, kernel fills address
  if not sock then return nil, err end

  local k = t.sockaddr_nl() -- kernel destination

  local ok, err = nl.write(sock, k, ntype, flags, af, ...)
  if not ok then
    sock:close()
    return nil, err
  end

  local r, err = nl.read(sock, k, nil, true) -- true means until get done message
  if not r then
    sock:close()
    return nil, err
  end

  local ok, err = sock:close()
  if not ok then return nil, err end

  return r
end

-- TODO do not have all these different arguments for these functions, pass a table for initialization. See also iplink.

function nl.newlink(index, flags, iflags, change, ...)
  if change == 0 then change = c.IFF.NONE end -- 0 should work, but does not
  flags = c.NLM_F("request", "ack", flags)
  if type(index) == 'table' then index = index.index end
  local ifv = {ifi_index = index, ifi_flags = c.IFF[iflags], ifi_change = c.IFF[change]}
  return nlmsg("newlink", flags, nil, t.ifinfomsg, ifv, ...)
end

function nl.dellink(index, ...)
  if type(index) == 'table' then index = index.index end
  local ifv = {ifi_index = index}
  return nlmsg("dellink", "request, ack", nil, t.ifinfomsg, ifv, ...)
end

-- read interfaces and details.
function nl.getlink(...)
  return nlmsg("getlink", "request, dump", nil, t.rtgenmsg, {rtgen_family = c.AF.PACKET}, ...)
end

-- read routes
function nl.getroute(af, tp, tab, prot, scope, ...)
  local rtm = t.rtmsg{family = af, table = tab, protocol = prot, type = tp, scope = scope}
  local r, err = nlmsg(c.RTM.GETROUTE, "request, dump", af, t.rtmsg, rtm)
  if not r then return nil, err end
  return setmetatable(r, mt.routes)
end

function nl.routes(af, tp)
  af = c.AF[af]
  if not tp then tp = c.RTN.UNICAST end
  tp = c.RTN[tp]
  local r, err = nl.getroute(af, tp)
  if not r then return nil, err end
  local ifs, err = nl.getlink()
  if not ifs then return nil, err end
  local indexmap = {} -- TODO turn into metamethod as used elsewhere
  for i, v in pairs(ifs) do
    v.inet, v.inet6 = {}, {}
    indexmap[v.index] = i
  end
  for k, v in ipairs(r) do
    if ifs[indexmap[v.iif]] then v.input = ifs[indexmap[v.iif]].name end
    if ifs[indexmap[v.oif]] then v.output = ifs[indexmap[v.oif]].name end
    if tp > 0 and v.rtmsg.rtm_type ~= tp then r[k] = nil end -- filter unwanted routes
  end
  r.family = af
  r.tp = tp
  return r
end

local function preftable(tab, prefix)
  for k, v in pairs(tab) do
    if k:sub(1, #prefix) ~= prefix then
      tab[prefix .. k] = v
      tab[k] = nil
    end
  end
  return tab
end

function nl.newroute(flags, rtm, ...)
  flags = c.NLM_F("request", "ack", flags)
  rtm = mktype(t.rtmsg, rtm)
  return nlmsg("newroute", flags, rtm.family, t.rtmsg, rtm, ...)
end

function nl.delroute(rtm, ...)
  rtm = mktype(t.rtmsg, rtm)
  return nlmsg("delroute", "request, ack", rtm.family, t.rtmsg, rtm, ...)
end

-- read addresses from interface TODO flag cleanup
function nl.getaddr(af, ...)
  local family = c.AF[af]
  local ifav = {ifa_family = family}
  return nlmsg("getaddr", "request, root", family, t.ifaddrmsg, ifav, ...)
end

-- TODO may need ifa_scope
function nl.newaddr(index, af, prefixlen, flags, ...)
  if type(index) == 'table' then index = index.index end
  local family = c.AF[af]
  local ifav = {ifa_family = family, ifa_prefixlen = prefixlen or 0, ifa_flags = c.IFA_F[flags], ifa_index = index} --__TODO in __new
  return nlmsg("newaddr", "request, ack", family, t.ifaddrmsg, ifav, ...)
end

function nl.deladdr(index, af, prefixlen, ...)
  if type(index) == 'table' then index = index.index end
  local family = c.AF[af]
  local ifav = {ifa_family = family, ifa_prefixlen = prefixlen or 0, ifa_flags = 0, ifa_index = index}
  return nlmsg("deladdr", "request, ack", family, t.ifaddrmsg, ifav, ...)
end

function nl.getneigh(index, tab, ...)
  if type(index) == 'table' then index = index.index end
  tab.ifindex = index
  local ndm = t.ndmsg(tab)
  return nlmsg("getneigh", "request, dump", ndm.family, t.ndmsg, ndm, ...)
end

function nl.newneigh(index, tab, ...)
  if type(index) == 'table' then index = index.index end
  tab.ifindex = index
  local ndm = t.ndmsg(tab)
  return nlmsg("newneigh", "request, ack, excl, create", ndm.family, t.ndmsg, ndm, ...)
end

function nl.delneigh(index, tab, ...)
  if type(index) == 'table' then index = index.index end
  tab.ifindex = index
  local ndm = t.ndmsg(tab)
  return nlmsg("delneigh", "request, ack", ndm.family, t.ndmsg, ndm, ...)
end

function nl.interfaces() -- returns with address info too.
  local ifs, err = nl.getlink()
  if not ifs then return nil, err end
  local addr4, err = nl.getaddr(c.AF.INET)
  if not addr4 then return nil, err end
  local addr6, err = nl.getaddr(c.AF.INET6)
  if not addr6 then return nil, err end
  local indexmap = {}
  for i, v in pairs(ifs) do
    v.inet, v.inet6 = {}, {}
    indexmap[v.index] = i
  end
  for i = 1, #addr4 do
    local v = ifs[indexmap[addr4[i].index]]
    v.inet[#v.inet + 1] = addr4[i]
  end
  for i = 1, #addr6 do
    local v = ifs[indexmap[addr6[i].index]]
    v.inet6[#v.inet6 + 1] = addr6[i]
  end
  return setmetatable(ifs, mt.iflinks)
end

function nl.interface(i) -- could optimize just to retrieve info for one
  local ifs, err = nl.interfaces()
  if not ifs then return nil, err end
  return ifs[i]
end

local link_process_f
local link_process = { -- TODO very incomplete. generate?
  name = function(args, v) return {"ifname", v} end,
  link = function(args, v) return {"link", v} end,
  address = function(args, v) return {"address", v} end,
  type = function(args, v, tab)
    if v == "vlan" then
      local id = tab.id
      if id then
        tab.id = nil
        return {"linkinfo", {"kind", "vlan", "data", {"id", id}}}
     end
    elseif v == "veth" then
      local peer = tab.peer
      tab.peer = nil
      local peertab = link_process_f(peer)
      return {"linkinfo", {"kind", "veth", "data", {"peer", {t.ifinfomsg, {}, peertab}}}}
    end
    return {"linkinfo", "kind", v}
  end,
}

function link_process_f(tab, args)
  args = args or {}
  for _, k in ipairs{"link", "name", "type"} do
    local v = tab[k]
    if v then
      if link_process[k] then
        local a = link_process[k](args, v, tab)
        for i = 1, #a do args[#args + 1] = a[i] end
      else error("bad iplink command " .. k)
      end
    end
  end
  return args
end

-- TODO better name. even more general, not just newlink. or make this the exposed newlink interface?
-- I think this is generally a nicer interface to expose than the ones above, for all functions
function nl.iplink(tab)
  local args = {tab.index or 0, tab.modifier or 0, tab.flags or 0, tab.change or 0}
  local args = link_process_f(tab, args)
  return nl.newlink(unpack(args))
end

-- TODO iplink may not be appropriate always sort out flags
function nl.create_interface(tab)
  tab.modifier = c.NLM_F.CREATE
  return nl.iplink(tab)
end

return nl

end

return {init = init}

