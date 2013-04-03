-- module for netfilter code
-- will cover iptables, ip6tables, ebtables, arptables eventually
-- even less documentation than for netlink but it does not look too bad...

local nf = {} -- exports

local ffi = require "ffi"
local bit = require "bit"
local S = require "syscall"
local h = require "syscall.helpers"
local t, pt, s, c = S.t, S.pt, S.s, S.c

function nf.socket(family)
  return S.socket(family, "raw", "raw")
end

local level = {
  [c.AF.INET] = c.IPPROTO.IP,
  [c.AF.INET6] = c.IPPROTO.IPV6,
}

function nf.version(family)
  family = family or c.AF.INET
  local sock, err = nf.socket(family)
  if not sock then return nil, err end
  local rev = t.xt_get_revision()
  max, err = sock:getsockopt(level[family], c.IPT_SO_GET.REVISION_TARGET, rev, s.xt_get_revision);
  if not max then return nil, err end
  local ok, err = sock:close()
  if not ok then return nil, err end
  return max
end

return nf

