-- these are helper functions, basically things that are in man(3) not syscalls
-- plan is to replace all with pure Lua code, as can then be optimised by Luajit

-- TODO broken dependecies. need to move core code to types, make into methods of types.

local util = {} -- exports

local ffi = require "ffi"
local bit = require "bit"

local c = require "include.constants"

local S = require "syscall"

local t, pt, s = S.t, S.pt, S.s -- TODO get from types once not requiring S

local C = S.C -- should be able to avoid

-- functions from section 3 that we use for ip addresses etc





function util.inet_aton(s)
  return util.inet_pton(c.AF.INET, s)
end

function util.inet_ntoa(addr)
  return util.inet_ntop(c.AF.INET, addr)
end

-- generic inet name to ip, also with netmask support TODO think of better name?
-- convert to a type
local function inet_name(src, netmask)
  local addr
  if not netmask then
    local a, b = src:find("/", 1, true)
    if a then
      netmask = tonumber(src:sub(b + 1))
      src = src:sub(1, a - 1)
    end
  end
  if src:find(":", 1, true) then -- ipv6
    addr = t.in6_addr(src)
    if not addr then return nil end
    if not netmask then netmask = 128 end
  else
    addr = t.in_addr(src)
    if not addr then return nil end
    if not netmask then netmask = 32 end
  end
  return addr, netmask
end

return util

