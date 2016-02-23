-- This mirrors syscall.lua, but some differences

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local ffi = require "ffi"

local abi = require "syscall.abi"

abi.rump = true

local modules = {
  rump = ffi.load("rump", true),
  rumpuser = ffi.load("rumpuser", true),
}

_G[{}] = modules -- if you unload rump kernel crashes are likely, so hang on to them

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
  pid_t = true,
  off_t = true,
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
  ["struct {int count; struct iovec iov[?];}"] = true,
}

local function rumpfn(tp)
  if unchanged[tp] then return tp end
  if tp == "void (*)(int, siginfo_t *, void *)" then return "void (*)(int, _netbsd_siginfo_t *, void *)" end
  if tp == "struct {dev_t dev;}" then return "struct {_netbsd_dev_t dev;}" end
  if tp == "struct {timer_t timerid[1];}" then return "struct {_netbsd_timer_t timerid[1];}" end
  if tp == "union sigval" then return "union _netbsd_sigval" end
  if tp == "struct {int count; struct mmsghdr msg[?];}" then return "struct {int count; struct _netbsd_mmsghdr msg[?];}" end
  if string.find(tp, "struct") then
    return (string.gsub(tp, "struct (%a)", "struct _netbsd_%1"))
  end
  return "_netbsd_" .. tp
end

local S

if abi.types == "linux" then -- load Linux compat module
  modules.rumpvfs = ffi.load("rumpvfs", true)
  modules.rumpnet = ffi.load("rumpnet", true)
  modules.rumpnetnet = ffi.load("rumpnet_net", true)
  modules.rumpcompat = ffi.load("rumpkern_sys_linux", true)
end

abi.rumpfn = nil

if abi.host == "netbsd" and abi.types == "netbsd" then -- running native (NetBSD on NetBSD)
  local SS = require "syscall"
  local C = require "syscall.rump.c"
  S = require "syscall.syscalls".init(C, SS.c, SS.types)
  S.abi, S.c, S.types, S.t = abi, SS.c, SS.types, SS.types.t
  S = require "syscall.compat".init(S)
  S = require "syscall.methods".init(S)
  S.util = require "syscall.util".init(S)
elseif abi.types == "linux" then -- running Linux types, just need to use rump C which it will do if abi.rump set
  S = require "syscall"
  -- TODO lots of syscalls simply don't exist, so make some do ENOSYS
  local function nosys()
    ffi.errno(S.c.E.NOSYS)
    return -1
  end
  local C = require "syscall.rump.c"
  local nolist = {"io_setup"} -- TODO can add more here
  for _, sys in ipairs(nolist) do C[sys] = nosys end

  -- add a few netbsd types so can use mount
  -- TODO ideally we would require netbsd.ffitypes but this is somewhat complex now
  ffi.cdef [[
typedef uint32_t _netbsd_mode_t;
typedef uint64_t _netbsd_ino_t;
struct _netbsd_ufs_args {
  char *fspec;
};
struct _netbsd_tmpfs_args {
  int ta_version;
  _netbsd_ino_t ta_nodes_max;
  off_t ta_size_max;
  uid_t ta_root_uid;
  gid_t ta_root_gid;
  _netbsd_mode_t ta_root_mode;
};
struct _netbsd_ptyfs_args {
  int version;
  gid_t gid;
  _netbsd_mode_t mode;
  int flags;
};
]]

  local addtype = require "syscall.helpers".addtype
  local addstructs = {
    ufs_args = "struct _netbsd_ufs_args",
    tmpfs_args = "struct _netbsd_tmpfs_args",
    ptyfs_args = "struct _netbsd_ptyfs_args",
  }
  for k, v in pairs(addstructs) do addtype(S.types, k, v, {}) end
elseif abi.types == "netbsd" then -- run NetBSD types on another OS
  abi.rumpfn = rumpfn -- mangle NetBSD type names to avoid collisions
  S = require "syscall"
else
  error "unsupported ABI"
end

require "syscall.rump.ffirump"

local t, pt = S.types.t, S.types.pt

local modinfo = ffi.typeof("struct modinfo")

-- TODO make this explcitly refer to NetBSD error codes
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

local h = require "syscall.helpers"
local octal, multiflags, charflags, swapflags, strflag, atflag, modeflags
  = h.octal, h.multiflags, h.charflags, h.swapflags, h.strflag, h.atflag, h.modeflags

local c = {}

c.ETFS = strflag {
  REG = 0,
  BLK = 1,
  CHR = 2,
  DIR = 3,
  DIR_SUBDIRS = 4,
}

c.RUMPUIO = strflag {
  READ = 0,
  WRITE = 1,
}

c.SIGMODEL = strflag {
  PANIC = 0,
  IGNORE = 1,
  HOST = 2,
  RAISE = 3,
  RECORD = 4,
};

c.RF = strflag {
  NONE    = 0x00, -- not named, see issue https://github.com/anttikantee/buildrump.sh/issues/19
  FDG     = 0x01,
  CFDG    = 0x02,
}

c.CN_FREECRED = 0x02
c.ETFS_SIZE_ENDOFF = h.uint64_max

S.rump.c = c

-- We could also use rump_pub_module_init if loading later
function S.rump.module(s)
  s = "rump" .. string.gsub(s, "%.", "_")
  local mod = ffi.load(s, true)
  modules[s] = mod
end

local function loadmodules(ms)
  local len = #ms
  local remains = #ms
  local succeeded = true
  while remains > 0 do
    succeeded = false
    for i = 1, #ms do
      local v = ms[i]
      if v then
        v = "rump" .. string.gsub(v, "%.", "_")
        local ok, mod = pcall(ffi.load, v, true)
        if ok then
          modules[v] = mod
          ms[i] = nil
          succeeded = true
          remains = remains - 1
        end
      end
    end
    if not succeeded then break end
  end
  if not succeeded then error "cannot load rump modules" end
end

function S.rump.init(ms, ...) -- you must load the factions here eg dev, vfs, net, plus modules
  if type(ms) == "string" then ms = {ms, ...} end
  if ms then loadmodules(ms) end
  local ok = ffi.C.rump_init()
  if ok == -1 then return nil, t.error() end
  S.abi = abi
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

function S.rump.i_know_what_i_am_doing_sysent_usenative()
  ffi.C.rump_i_know_what_i_am_doing_with_sysents = 1
  ffi.C.rump_pub_lwproc_sysent_usenative();
end

function S.rump.getversion() return ffi.C.rump_pub_getversion() end

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

-- revert so can load non rump again
abi.rump = false
abi.os = abi.host

S.__rump = true

return S.rump
 

