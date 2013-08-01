-- This mirrors syscall.lua, but some differences

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math

local ffi = require "ffi"

local rumpuser = ffi.load("rumpuser", true)
local rump = ffi.load("rump", true)

local abi = require "syscall.rump.abi"

local unchanged = {
  char = true,
  int = true,
  long = true,
  unsigned = true,
  ["unsigned char"] = true,
  ["unsigned int"] = true,
  ["unsigned long"] = true,
  int8_t = true,
  int16_t = true,
  int32_t = true,
  int64_t = true,
  intptr_t = true,
  uint8_t = true,
  uint16_t = true,
  uint32_t = true,
  uint64_t = true,
  uintptr_t = true,
-- same in all OSs at present
  in_port_t = true,
  uid_t = true,
  gid_t = true,
  id_t = true,
  pid_t = true,
  off_t = true,
  nfds_t = true,
  size_t = true,
  ssize_t = true,
  socklen_t = true,
  ["struct in_addr"] = true,
  ["struct in6_addr"] = true,
  ["struct iovec"] = true,
  ["struct iphdr"] = true,
  ["struct udphdr"] = true,
  ["struct ethhdr"] = true,
  ["struct winsize"] = true,
}

local function rumpfn(tp)
  if unchanged[tp] then return tp end
  if tp == "void (*)(int, siginfo_t *, void *)" then return "void (*)(int, _netbsd_siginfo_t *, void *)" end
  if string.find(tp, "struct") then
    return (string.gsub(tp, "struct (%a)", "struct _netbsd_%1"))
  end
  return "_netbsd_" .. tp
end

local S

if abi.host == abi.os then -- running native
  -- here we need to reuse a lot of stuff, but noting that depends on C
  local SS = require "syscall"
  local C = require "syscall.rump.c".init(abi, c, types)

  c.IOCTL = ioctl -- cannot put in S, needed for tests, cannot be put in c earlier due to deps

  S = require "syscall.syscalls".init(abi, SS.c, C, SS.types, SS.c.IOCTL, SS.__fcntl)

  S.abi, S.c, S.C, S.types, S.t = abi, SS.c, C, SS.types, SS.types.t

  S = require "syscall.compat".init(S)
  S = require "syscall.methods".init(S)
  S.features = require "syscall.features".init(S)
  S.util = require "syscall.util".init(S)
else -- running on another OS
  abi.rumpfn = rumpfn -- mangle NetBSD type names to avoid collisions
  S = require "syscall.init".init(abi)
end

require "syscall.rump.ffirump"

local t, pt = S.types.t, S.types.pt

local modinfo = ffi.typeof("struct modinfo")

local function retbool(ret)
  if ret == -1 then return nil, t.error() end
  return true
end

local function retnum(ret) -- return Lua number where double precision ok, eg file ops etc
  ret = tonumber(ret)
  if ret == -1 then return nil, t.error() end
  return ret
end

S.rump = {}

S.rump.c = require "syscall.rump.constants"

S.rump.__modules = {rump, rumpuser} -- so not garbage collected

local helpers = require "syscall.helpers"
local strflag = helpers.strflag

-- We could also use rump_pub_module_init if loading later
function S.rump.module(s)
  s = string.gsub(s, "%.", "_")
  local mod = ffi.load("rump" .. s, true)
  S.rump.__modules[#S.rump.__modules + 1] = mod
end

function S.rump.init(modules, ...) -- you must load the factions here eg dev, vfs, net, plus modules
  if type(modules) == "string" then modules = {modules, ...} end
  for i, v in ipairs(modules or {}) do
    v = string.gsub(v, "%.", "_")
    local mod = ffi.load("rump" .. v, true)
    S.rump.__modules[#S.rump.__modules + 1] = mod
  end
  local ok = rump.rump_init()
  if ok == -1 then return nil, t.error() end
  return S
end

function S.rump.boot_gethowto() return retnum(ffi.C.rump_boot_gethowto()) end
function S.rump.boot_sethowto(how) ffi.C.rump_boot_sethowto(how) end
function S.rump.boot_setsigmodel(model) ffi.C.rump_boot_etsigmodel(model) end
function S.rump.schedule() ffi.C.rump_schedule() end
function S.rump.unschedule() ffi.C.rump_unschedule() end
function S.rump.printevcnts() ffi.C.rump_printevcnts() end
function S.rump.daemonize_begin() return retbool(ffi.C.rump_daemonize_begin()) end
function S.rump.daemonize_done(err) return retbool(ffi.C.rump_daemonize_done(err)) end
function S.rump.init_server(url) return retbool(ffi.C.rump_init_server(url)) end

function S.rump.getversion() return rump.rump_pub_getversion() end

-- etfs functions
function S.rump.etfs_register(key, hostpath, ftype, begin, size)
  local ret
  ftype = S.rump.c.ETFS[ftype]
  if begin then
    ret = ffi.C.rump_pub_etfs_register_withsize(key, hostpath, ftype, begin, size);
  else
    ret = ffi.C.rump_pub_etfs_register(key, hostpath, ftype);
  end
  return retbool(ret)
end
function S.rump.etfs_remove(key)
  return retbool(ffi.C.rump_pub_etfs_remove(key))
end

-- threading
function S.rump.rfork(flags) return retbool(ffi.C.rump_pub_lwproc_rfork(S.rump.c.RF[flags])) end
function S.rump.newlwp(pid) return retbool(ffi.C.rump_pub_lwproc_newlwp(pid)) end
function S.rump.switchlwp(lwp) ffi.C.rump_pub_lwproc_switch(lwp) end
function S.rump.releaselwp() ffi.C.rump_pub_lwproc_releaselwp() end
function S.rump.curlwp() return ffi.C.rump_pub_lwproc_curlwp() end

return S.rump
 

