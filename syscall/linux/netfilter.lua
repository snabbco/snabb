-- module for netfilter code
-- will cover iptables, ip6tables, ebtables, arptables eventually
-- even less documentation than for netlink but it does not look too bad...

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local nf = {} -- exports

local ffi = require "ffi"
local bit = require "syscall.bit"
local S = require "syscall"
local helpers = require "syscall.helpers"
local c = S.c
local types = S.types
local t, pt, s = types.t, types.pt, types.s

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
  local max, err = sock:getsockopt(level[family], c.IPT_SO_GET.REVISION_TARGET, rev, s.xt_get_revision);
  local ok, cerr = sock:close()
  if not ok then return nil, cerr end
  if not max then return nil, err end
  return max
end

return nf

