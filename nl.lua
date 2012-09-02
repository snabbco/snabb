-- modularize netlink code as it is large and standalone

-- note that the constants are in S still. Could move them.

local function nl()

local nl = {} -- exports

local ffi = require "ffi"
local bit = require "bit"
local S = require "syscall"

local t, pt, s = S.t, S.pt, S.s
local stringflag, stringflags, flaglist = S.stringflag, S.stringflags, S.flaglist

local mt = {} -- metatables
local meth = {}

local function ptt(tp)
  local ptp = ffi.typeof("$ *", tp)
  return function(x) return ffi.cast(ptp, x) end
end

local function align(len, a) return bit.band(tonumber(len) + a - 1, bit.bnot(a - 1)) end

local function tbuffer(a, ...) -- helper function for sequence of types in a buffer
  local function threc(buf, offset, tp, ...)
    if not tp then return nil end
    local p = ptt(tp)
    if select("#", ...) == 0 then return p(buf + offset) end
    return p(buf + offset), threc(buf, offset + align(ffi.sizeof(tp), a), ...)
  end
  local len = 0
  for _, tp in ipairs{...} do
    len = len + align(ffi.sizeof(tp), a)
  end
  local buf = t.buffer(len)
  return buf, len, threc(buf, 0, ...)
end

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

local addrlenmap = { -- map interface type to length of hardware address
  [S.ARPHRD_ETHER] = 6,
  [S.ARPHRD_EETHER] = 6,
  [S.ARPHRD_LOOPBACK] = 6,
}

local ifla_decode = {
  [S.IFLA_IFNAME] = function(ir, buf, len)
    ir.name = ffi.string(buf)
  end,
  [S.IFLA_ADDRESS] = function(ir, buf, len)
    local addrlen = addrlenmap[ir.type]
    if (addrlen) then
      ir.addrlen = addrlen
      ir.macaddr = t.macaddr()
      ffi.copy(ir.macaddr, buf, addrlen)
    end
  end,
  [S.IFLA_BROADCAST] = function(ir, buf, len)
    local addrlen = addrlenmap[ir.type]
    if (addrlen) then
      ir.braddrlen = addrlen
      ir.broadcast = t.macaddr()
      ffi.copy(ir.broadcast, buf, addrlen)
    end
  end,
  [S.IFLA_MTU] = function(ir, buf, len)
    local u = pt.uint(buf)
    ir.mtu = tonumber(u[0])
  end,
  [S.IFLA_LINK] = function(ir, buf, len)
    local i = pt.int(buf)
    ir.link = tonumber(i[0])
  end,
  [S.IFLA_QDISC] = function(ir, buf, len)
    ir.qdisc = ffi.string(buf)
  end,
  [S.IFLA_STATS] = function(ir, buf, len)
    ir.stats = t.rtnl_link_stats() -- despite man page, this is what kernel uses. So only get 32 bit stats here.
    ffi.copy(ir.stats, buf, s.rtnl_link_stats)
  end
}

local ifa_decode = {
  [S.IFA_ADDRESS] = function(ir, buf, len)
    ir.addr = S.addrtype[ir.family]()
    ffi.copy(ir.addr, buf, ffi.sizeof(ir.addr))
  end,
  [S.IFA_LOCAL] = function(ir, buf, len)
    ir.loc = S.addrtype[ir.family]()
    ffi.copy(ir.loc, buf, ffi.sizeof(ir.loc))
  end,
  [S.IFA_BROADCAST] = function(ir, buf, len)
    ir.broadcast = S.addrtype[ir.family]()
    ffi.copy(ir.broadcast, buf, ffi.sizeof(ir.broadcast))
  end,
  [S.IFA_LABEL] = function(ir, buf, len)
    ir.label = ffi.string(buf)
  end,
  [S.IFA_ANYCAST] = function(ir, buf, len)
    ir.anycast = S.addrtype[ir.family]()
    ffi.copy(ir.anycast, buf, ffi.sizeof(ir.anycast))
  end,
  [S.IFA_CACHEINFO] = function(ir, buf, len)
    ir.cacheinfo = t.ifa_cacheinfo()
    ffi.copy(ir.cacheinfo, buf, ffi.sizeof(t.ifa_cacheinfo))
  end,
}

local rta_decode = {
  [S.RTA_DST] = function(ir, buf, len)
    ir.dst = S.addrtype[ir.family]()
    ffi.copy(ir.dst, buf, ffi.sizeof(ir.dst))
  end,
  [S.RTA_SRC] = function(ir, buf, len)
    ir.src = S.addrtype[ir.family]()
    ffi.copy(ir.src, buf, ffi.sizeof(ir.src))
  end,
  [S.RTA_IIF] = function(ir, buf, len)
    local i = pt.int(buf)
    ir.iif = tonumber(i[0])
  end,
  [S.RTA_OIF] = function(ir, buf, len)
    local i = pt.int(buf)
    ir.oif = tonumber(i[0])
  end,
  [S.RTA_GATEWAY] = function(ir, buf, len)
    ir.gateway = S.addrtype[ir.family]()
    ffi.copy(ir.gateway, buf, ffi.sizeof(ir.gateway))
  end,
  [S.RTA_PRIORITY] = function(ir, buf, len)
    local i = pt.int(buf)
    ir.priority = tonumber(i[0])
  end,
  [S.RTA_PREFSRC] = function(ir, buf, len)
    local i = pt.uint32(buf)
    ir.prefsrc = tonumber(i[0])
  end,
  [S.RTA_METRICS] = function(ir, buf, len)
    local i = pt.int(buf)
    ir.metrics = tonumber(i[0])
  end,
  [S.RTA_TABLE] = function(ir, buf, len)
    local i = pt.uint32(buf)
    ir.table = tonumber(i[0])
  end,
  [S.RTA_CACHEINFO] = function(ir, buf, len)
    ir.cacheinfo = t.rta_cacheinfo()
    ffi.copy(ir.cacheinfo, buf, s.rta_cacheinfo)
  end,
  -- TODO some missing
}

mt.iff = {
  __tostring = function(f)
    local s = {}
    local flags = {"UP", "BROADCAST", "DEBUG", "LOOPBACK", "POINTOPOINT", "NOTRAILERS", "RUNNING", "NOARP", "PROMISC",
                   "ALLMULTI", "MASTER", "SLAVE", "MULTICAST", "PORTSEL", "AUTOMEDIA", "DYNAMIC", "LOWER_UP", "DORMANT", "ECHO"}
    for _, i in pairs(flags) do if f[i] then s[#s + 1] = i end end
    return table.concat(s, ' ')
  end,
  __index = function(f, k)
    local prefix = "IFF_"
    if k:sub(1, #prefix) ~= prefix then k = prefix .. k:upper() end
    if S[k] then return bit.band(f.flags, S[k]) ~= 0 end
  end
}

nl.encapnames = {
  [S.ARPHRD_ETHER] = "Ethernet",
  [S.ARPHRD_LOOPBACK] = "Local Loopback",
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
      local ok, err = nl.newlink(i, 0, flags, change or S.IFF_ALL)
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
      if type(address) == "string" then address, netmask = S.inet_name(address, netmask) end
      if not address then return nil end
      local af
      if ffi.istype(t.in6_addr, address) then af = S.AF_INET6 else af = S.AF_INET end
      local ok, err = nl.newaddr(i.index, af, netmask, "permanent", "address", address)
      if not ok then return nil, err end
      return i:refresh()
    end,
    deladdr = function(i, address, netmask)
      if type(address) == "string" then address, netmask = S.inet_name(address, netmask) end
      if not address then return nil end
      local af
      if ffi.istype(t.in6_addr, address) then af = S.AF_INET6 else af = S.AF_INET end
      local ok, err = nl.deladdr(i.index, af, netmask, "address", address)
      if not ok then return nil, err end
      return i:refresh()
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
    local prefix = "ARPHRD_"
    if k:sub(1, #prefix) ~= prefix then k = prefix .. k:upper() end
    if S[k] then return i.ifinfo.ifi_type == S[k] end
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
    dest = function(i) return i.dst or S.addrtype[i.family]() end,
    source = function(i) return i.src or S.addrtype[i.family]() end,
    gw = function(i) return i.gateway or S.addrtype[i.family]() end,
    -- might not be set in Lua table, so return nil
    iif = function() return nil end,
    oif = function() return nil end,
    src = function() return nil end,
    dst = function() return nil end,
  },
  flags = { -- TODO rework so iterates in fixed order. TODO Do not seem to be set, find how to retrieve.
    [S.RTF_UP] = "U",
    [S.RTF_GATEWAY] = "G",
    [S.RTF_HOST] = "H",
    [S.RTF_REINSTATE] = "R",
    [S.RTF_DYNAMIC] = "D",
    [S.RTF_MODIFIED] = "M",
    [S.RTF_REJECT] = "!",
  }
}

mt.rtmsg = {
  __index = function(i, k)
    if meth.rtmsg.index[k] then return meth.rtmsg.index[k](i) end
    local prefix = "RTF_"
    if k:sub(1, #prefix) ~= prefix then k = prefix .. k:upper() end
    if S[k] then return bit.band(i.flags, S[k]) ~= 0 end
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
        if rs.family == S.AF_INET6 then addr = t.in6_addr(addr) else addr = t.in_addr(addr) end
      end
      local matches = {}
      for _, v in ipairs(rs) do
        if len == v.dst_len then
          if v.family == S.AF_INET then
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
    local prefix = "IFA_F_"
    if k:sub(1, #prefix) ~= prefix then k = prefix .. k:upper() end
    if S[k] then return bit.band(i.ifaddr.ifa_flags, S[k]) ~= 0 end
  end
}

local function decode_link(r, buf, len)
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

  r[ir.name] = ir
  r[#r + 1] = ir -- array and names

  return r
end

local nlmsg_data_decode = {
  [S.NLMSG_NOOP] = function(r, buf, len) return r end,
  [S.NLMSG_ERROR] = function(r, buf, len)
    local e = pt.nlmsgerr(buf)
    if e.error ~= 0 then r.error = t.error(-e.error) else r.ack = true end -- error zero is ACK, others negative
    return r
  end,
  [S.NLMSG_DONE] = function(r, buf, len) return r end,
  [S.NLMSG_OVERRUN] = function(r, buf, len)
    r.overrun = true
    return r
  end,
  [S.RTM_NEWADDR] = function(r, buf, len)
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

   r[#r + 1] = ir

   return r
  end,
  [S.RTM_NEWLINK] = decode_link,
  [S.RTM_DELLINK] = decode_link,
  [S.RTM_NEWROUTE] = function(r, buf, len)
    local rt = pt.rtmsg(buf)
    buf = buf + nlmsg_align(s.rtmsg)
    len = len - nlmsg_align(s.rtmsg)
    local rtattr = pt.rtattr(buf)
    local ir = setmetatable({rtmsg = t.rtmsg()}, mt.rtmsg)
    ffi.copy(ir.rtmsg, rt, s.rtmsg)
    while rta_ok(rtattr, len) do
      if rta_decode[rtattr.rta_type] then
        rta_decode[rtattr.rta_type](ir, buf + rta_length(0), rta_align(rtattr.rta_len) - rta_length(0))
      else print("NYI", rtattr.rta_type)
      end
      rtattr, buf, len = rta_next(rtattr, buf, len)
    end

    r[#r + 1] = ir

    return r
  end,
}

function nl.read(s, addr, bufsize, untildone)
  if not bufsize then bufsize = 8192 end
  local reply = t.buffer(bufsize)
  local ior = t.iovecs{{reply, bufsize}}
  local m = t.msghdr{msg_iov = ior.iov, msg_iovlen = #ior, msg_name = addr, msg_namelen = ffi.sizeof(addr)}

  local done = false -- what should we do if we get a done message but there is some extra buffer? could be next message...
  local r = {}

  while not done do
    local n, err = s:recvmsg(m)
    if not n then return nil, err end
    local len = tonumber(n.count)
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

      if tp == S.NLMSG_DONE then done = true end
      msg, buffer, len = nlmsg_next(msg, buffer, len)
    end
    if not untildone then done = true end
  end

  return r
end

local function nlmsgbuffer(...)
  return tbuffer(nlmsg_align(1), t.nlmsghdr, ...)
end

-- TODO share with read side
local ifla_msg_types = {
  ifla = {
    -- IFLA_UNSPEC
    [S.IFLA_ADDRESS] = t.macaddr,
    [S.IFLA_BROADCAST] = t.macaddr,
    [S.IFLA_IFNAME] = "asciiz",
    -- TODO IFLA_MAP
    [S.IFLA_MTU] = t.uint32,
    [S.IFLA_LINK] = t.uint32,
    [S.IFLA_MASTER] = t.uint32,
    [S.IFLA_TXQLEN] = t.uint32,
    [S.IFLA_WEIGHT] = t.uint32,
    [S.IFLA_OPERSTATE] = t.uint8,
    [S.IFLA_LINKMODE] = t.uint8,
    [S.IFLA_LINKINFO] = {"ifla_info", "IFLA_INFO_"},
    [S.IFLA_NET_NS_PID] = t.uint32,
    [S.IFLA_NET_NS_FD] = t.uint32,
    [S.IFLA_IFALIAS] = "asciiz",
    --[S.IFLA_VFINFO_LIST] = "nested",
    --[S.IFLA_VF_PORTS] = "nested",
    --[S.IFLA_PORT_SELF] = "nested",
    --[S.IFLA_AF_SPEC] = "nested",
  },
  ifla_info = {
    [S.IFLA_INFO_KIND] = "ascii",
    [S.IFLA_INFO_DATA] = "kind",
  },
  ifla_vlan = {
    [S.IFLA_VLAN_ID] = t.uint16,
    -- other vlan params
  },
  ifa = {
    -- IFA_UNSPEC
    [S.IFA_ADDRESS] = "address",
    [S.IFA_LOCAL] = "address",
    [S.IFA_LABEL] = "asciiz",
    [S.IFA_BROADCAST] = "address",
    [S.IFA_ANYCAST] = "address",
    -- IFA_CACHEINFO
  },
  rta = {
    -- RTA_UNSPEC
    [S.RTA_DST] = "address",
    [S.RTA_SRC] = "address",
    [S.RTA_IIF] = t.uint32,
    [S.RTA_OIF] = t.uint32,
    [S.RTA_GATEWAY] = "address",
    [S.RTA_PRIORITY] = t.uint32,
    [S.RTA_METRICS] = t.uint32,
    --          RTA_PREFSRC
    --          RTA_MULTIPATH
    --          RTA_PROTOINFO
    --          RTA_FLOW
    --          RTA_CACHEINFO
  },
  veth_info = {
    -- VETH_INFO_UNSPEC
    [S.VETH_INFO_PEER] = {"ifla", "IFLA_"},
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

  if type(msg) == "cdata" then
    tp = msg
    value = table.remove(args, 1)
    if not value then error("not enough arguments") end
    if not ffi.istype(tp, value) then value = tp(value) end
    len = ffi.sizeof(value)
    messages[#messages + 1] = tp
    values[#values + 1] = value
    return len, args, messages, values, kind
  end

  local rawmsg = msg

  msg = stringflag(msg, lookup)
  tp = ifla_msg_types[tab][msg]
  if not tp then error("unknown message type " .. rawmsg .. " in " .. tab .. " lookup " .. lookup) end

  if tp == "kind" then
    local kinds = {
      vlan = {"ifla_vlan", "IFLA_VLAN_"},
      veth = {"veth_info", "VETH_INFO_"},
    }
    tp = kinds[kind]
  end

  if type(tp) == "table" then
    value = {rta_type = msg} -- missing rta_len, but have reference and can fix

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

  if tab == "ifla_info" and msg == S.IFLA_INFO_KIND then
    kind = value
  end

  local slen

  if tp == "asciiz" then
    tp = t.buffer(#value + 1)
    slen = nlmsg_align(s.rtattr) + #value + 1
  elseif tp == "ascii" then -- not zero terminated
    tp = t.buffer(#value)
    slen = nlmsg_align(s.rtattr) + #value
  else
    if tp == "address" then
      tp = S.addrtype[af]
    end
    if not ffi.istype(tp, value) then
      value = tp(value)
    end
  end

  len = nlmsg_align(s.rtattr) + nlmsg_align(ffi.sizeof(tp))
  slen = slen or len

  messages[#messages + 1] = t.rtattr
  messages[#messages + 1] = tp
  values[#values + 1] = {rta_type = msg, rta_len = slen}
  values[#values + 1] = value

  return len, args, messages, values, kind
end

local function ifla_f(tab, lookup, af, ...)
  local len, kind
  local messages, values = {}, {}

  local args = {...}
  while #args ~= 0 do
    len, args, messages, values, kind = ifla_getmsg(args, messages, values, tab, lookup, kind, af)
  end

  local results = {nlmsgbuffer(unpack(messages))}

  local buf, len, hdr = table.remove(results, 1), table.remove(results, 1), table.remove(results, 1)

  while #results ~= 0 do
    local result, value = table.remove(results, 1), table.remove(values, 1)
    if type(value) == "string" then
      ffi.copy(result, value)
    else
      result[0] = value
    end
  end

  return buf, len
end

local rtpref = {
  [S.RTM_NEWLINK] = {"ifla", "IFLA_"},
  [S.RTM_GETLINK] = {"ifla", "IFLA_"},
  [S.RTM_DELLINK] = {"ifla", "IFLA_"},
  [S.RTM_NEWADDR] = {"ifa", "IFA_"},
  [S.RTM_GETADDR] = {"ifa", "IFA_"},
  [S.RTM_DELADDR] = {"ifa", "IFA_"},
  [S.RTM_NEWROUTE] = {"rta", "RTA_"},
  [S.RTM_GETROUTE] = {"rta", "RTA_"},
  [S.RTM_DELROUTE] = {"rta", "RTA_"},
}

function nl.socket(tp, addr)
  tp = S.stringflag(tp, "NETLINK_")
  local sock, err = S.socket("netlink", "raw", tp)
  if not sock then return nil, err end
  if addr then
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
  if change == 0 then change = S.IFF_NONE end -- 0 should work, but does not
  flags = stringflag(flags, "NLM_F_") -- for replace, excl, create, append, TODO only allow these
  if type(index) == 'table' then index = index.index end
  local ifv = {ifi_index = index, ifi_flags = stringflags(iflags, "IFF_"), ifi_change = stringflags(change, "IFF_")}
  return nlmsg(S.RTM_NEWLINK, S.NLM_F_REQUEST + S.NLM_F_ACK + flags, nil, t.ifinfomsg, ifv, ...)
end

function nl.dellink(index, ...)
  if type(index) == 'table' then index = index.index end
  local ifv = {ifi_index = index}
  return nlmsg(S.RTM_DELLINK, S.NLM_F_REQUEST + S.NLM_F_ACK, nil, t.ifinfomsg, ifv, ...)
end

-- read interfaces and details.
function nl.getlink(...)
  return nlmsg(S.RTM_GETLINK, S.NLM_F_REQUEST + S.NLM_F_DUMP, nil, t.rtgenmsg, {rtgen_family = S.AF_PACKET}, ...)
end

-- read routes
function nl.getroute(af, tp, tab, prot, scope, ...)
  af = stringflag(af, "AF_")
  tp = stringflag(tp, "RTN_")
  tab = stringflag(tab, "RT_TABLE_")
  prot = stringflag(prot, "RTPROT_")
  scope = stringflag(scope, "RT_SCOPE_")
  local r, err = nlmsg(S.RTM_GETROUTE, S.NLM_F_REQUEST + S.NLM_F_DUMP, af, t.rtmsg,
                   {rtm_family = af, rtm_table = tab, rtm_protocol = prot, rtm_type = tp, rtm_scope = scope})
  if not r then return nil, err end
  return setmetatable(r, mt.routes)
end

function nl.routes(af, tp)
  af = stringflag(af, "AF_")
  if not tp then tp = S.RTN_UNICAST end
  tp = stringflag(tp, "RTN_")
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

local function rtm_table(tab)
  tab = preftable(tab, "rtm_")
  tab.rtm_family = stringflag(tab.rtm_family, "AF_")
  tab.rtm_protocol = stringflag(tab.rtm_protocol, "RTPROT_")
  tab.rtm_type = stringflag(tab.rtm_type, "RTN_")
  tab.rtm_scope = stringflag(tab.rtm_scope, "RT_SCOPE_")
  tab.rtm_flags = stringflag(tab.rtm_flags, "RTM_F_")
  tab.rtm_table = stringflag(tab.rtm_table, "RT_TABLE_")
  return tab
end

-- this time experiment using table as so many params, plus they are just to init struct.
function nl.newroute(flags, tab, ...)
  tab = rtm_table(tab)
  flags = stringflag(flags, "NLM_F_") -- for replace, excl, create, append, TODO only allow these
  return nlmsg(S.RTM_NEWROUTE, S.NLM_F_REQUEST + S.NLM_F_ACK + flags, tab.rtm_family, t.rtmsg, tab, ...)
end

function nl.delroute(tp, ...)
  tp = rtm_table(tp)
  return nlmsg(S.RTM_DELROUTE, S.NLM_F_REQUEST + S.NLM_F_ACK, tp.rtm_family, t.rtmsg, tp, ...)
end

-- read addresses from interface
function nl.getaddr(af, ...)
  local family = stringflag(af, "AF_")
  local ifav = {ifa_family = family}
  return nlmsg(S.RTM_GETADDR, S.NLM_F_REQUEST + S.NLM_F_ROOT, family, t.ifaddrmsg, ifav, ...)
end

-- TODO may need ifa_scope
function nl.newaddr(index, af, prefixlen, flags, ...)
  if type(index) == 'table' then index = index.index end
  local family = stringflag(af, "AF_")
  local ifav = {ifa_family = family, ifa_prefixlen = prefixlen or 0, ifa_flags = stringflag(flags, "IFA_F_"), ifa_index = index}
  return nlmsg(S.RTM_NEWADDR, S.NLM_F_REQUEST + S.NLM_F_ACK, family, t.ifaddrmsg, ifav, ...)
end

function nl.deladdr(index, af, prefixlen, ...)
  if type(index) == 'table' then index = index.index end
  local family = stringflag(af, "AF_")
  local ifav = {ifa_family = family, ifa_prefixlen = prefixlen or 0, ifa_flags = 0, ifa_index = index}
  return nlmsg(S.RTM_DELADDR, S.NLM_F_REQUEST + S.NLM_F_ACK, family, t.ifaddrmsg, ifav, ...)
end

function nl.interfaces() -- returns with address info too.
  local ifs, err = nl.getlink()
  if not ifs then return nil, err end
  local addr4, err = nl.getaddr(S.AF_INET)
  if not addr4 then return nil, err end
  local addr6, err = nl.getaddr(S.AF_INET6)
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

function nl.create_interface(tab)
  tab.modifier = S.NLM_F_CREATE
  return nl.iplink(tab)
end

return nl

end

return nl()

