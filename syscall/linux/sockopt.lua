-- socket options mapping

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

-- TODO add typemap for cmsghdr from syscall/types.lua as very similar
-- like ioctls and so on, socket options are a random interface that needs some help to make it nice to use
-- we need to know the types of the options (in particular those that are not the default int)
-- in fact many ints are really bool, so nicer to know that too.

-- example
--c.SOL.SOCKET, c.SO.PASSCRED - bool

-- note that currently we use c.SOL[level], c.SO[optname] as level, optname for setsockopt and nothing for getsockopt
-- but the second one depends on the first like cmsghdr options and first seems more complex.

-- eg netfilter uses c.IPPROTO.IP or c.IPPROTO.IPV6 as level and eg c.IPT_SO_GET.REVISION_TARGET as level, optname
-- so you need to pass the level of the socket you opened? We can store with fd if you use methods, so get/set sockopt know... that will be easier as we can't know option names otherwise.
-- although you can always use SOL_SOCKET (1 in Linux, ffff BSD), so need to special case. Lucky ICMP (ipproto 1) has no sockets

-- IP supports both IP_ (and MULTI_) and eg IPT_ groups - BSD more consistent I think in that IPT is at raw IP socket level
-- so will need some fudging. Obviously the numbers dont overlap (IPT is >=64) see note /usr/include/linux/netfilter_ipv4/ip_tables.h

-- draft

-- will be more complex than this

--[[
local levelmaps = {
  [c.SOL.SOCKET] = c.SO,



}

local types = {
  SO = {
-- or could use [c.SO.ACCEPTCON] but not as nice
    ACCEPTCONN = "boolean", -- NB read only, potentially useful to add
    BINDTODEVICE = "string",
    BROADCAST = "boolean",
-- ...
  },
  IP = {
    ADD_MEMBERSHIP = t.ip_mreqn, -- IP multicast

  },


}

]]

