-- Linux cgroup API
-- this is all file system operations packaged up to be easier to use

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(S)

local h = require "syscall.helpers"
local split = h.split

local abi, types, c = S.abi, S.types, S.c
local t, pt, s = types.t, types.pt, types.s

local util = S.util

local cgroup = {}

local function mkgroup(name)
  -- append default location, should be tmpfs mount
  if name:sub(1, 1) ~= "/" then return "/sys/fs/cgroup" .. name else return name end
end

function cgroup.mount(tab)
  tab.source = tab.source or "cgroup"
  tab.type = "cgroup"
  tab.target = mkgroup(tab.target)
  return S.mount(tab)
end

function cgroup.cgroups(ps)
  ps = tostring(ps or "self")
  local cgf = util.readfile("/proc/" .. ps .. "/cgroup")
  local lines = split("\n", cgf)
  local cgroups = {}
  for i = 1, #lines - 1 do
    local parts = split( ":", lines[i])
    cgroups[parts[1]] = {name = parts[2], path = parts[3]}
  end
  return cgroups
end

return cgroup

end

return {init = init}



