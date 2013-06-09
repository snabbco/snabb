
-- This mirrors syscall.lua, but some differences

local ffi = require "ffi"

local rumpuser = ffi.load("rumpuser")
local rump = ffi.load("rump")

local hostabi = require "syscall.abi"

local abi = {}
for k, v in pairs(hostabi) do abi[k] = v end
abi.rump = true
abi.host = abi.os
abi.os = "netbsd"

local errors = require "syscall.netbsd.errors"
local c, types

if abi.host == "netbsd" then
  -- if running rump on netbsd just return normal NetBSD types
  -- note that we get these by calling the whole thing so we do not get type redefinition erros
  local S = require "syscall"
  c = S.c
  types = S.types
else
  -- running on another OS
  require "syscall.netbsd.ffitypes".init(abi)
  c = require "syscall.netbsd.constants"
  local ostypes = require "syscall.netbsd.types"
  types = require "syscall.rump.types".init(abi, c, errors, ostypes)
end

local C = require "syscall.rump.c".init(abi, c, types, rump)
local ioctl = require("syscall.netbsd.ioctl")(abi, types)
local fcntl = require("syscall.netbsd.fcntl")(abi, c, types)

c.IOCTL = ioctl -- cannot put in S, needed for tests, cannot be put in c earlier due to deps

local S = require "syscall.syscalls".init(abi, c, C, types, ioctl, fcntl)

S.abi, S.c, S.C, S.types, S.t = abi, c, C, types, types.t -- add to main table returned

-- add methods
S = require "syscall.methods".init(S)

-- add feature tests
S.features = require "syscall.features".init(S)

-- rump functions, constants

-- note that modinfo is kernel only so not in ffitypes
ffi.cdef[[
int rump_init(void);

int rump_pub_getversion(void);

typedef struct modinfo {
  unsigned int    mi_version;
  int             mi_class;
  int             (*mi_modcmd)(int, void *);
  const char      *mi_name;
  const char      *mi_required;
} const modinfo_t;

int rump_pub_etfs_register(const char *key, const char *hostpath, int ftype);
int rump_pub_etfs_register_withsize(const char *key, const char *hostpath, int ftype, uint64_t begin, uint64_t size);
int rump_pub_etfs_remove(const char *key);

int rump_pub_module_init(const struct modinfo * const *, size_t);
int rump_pub_module_fini(const struct modinfo *);
]]

local pt = types.pt

local modinfo = ffi.typeof("struct modinfo")

-- I think these return errors in errno
local function retbool(ret)
  if ret == -1 then return nil, t.error() end
  return true
end

S.rump = {}

S.rump.__modules = {rump, rumpuser} -- so not garbage collected

local helpers = require "syscall.helpers"
local strflag = helpers.strflag

local RUMP_ETFS = strflag {
  REG = 0,
  BLK = 1,
  CHR = 2,
  DIR = 3,
  DIR_SUBDIRS = 4,
}

function S.rump.init(...) -- you must load the factions here eg dev, vfs, net, plus modules
  for i, v in ipairs{...} do
    v = string.gsub(v, "%.", "_")
    local mod = ffi.load("rump" .. v, true)
    S.rump.__modules[#S.rump.__modules + 1] = mod
  end
  return retbool(rump.rump_init())
end

function S.rump.version() return rump.rump_pub_getversion() end

-- We could also use rump_pub_module_init if loading later
function S.rump.module(s)
  s = string.gsub(s, "%.", "_")
  local mod = ffi.load("rump" .. s, true)
  S.rump.__modules[#S.rump.__modules + 1] = mod
end

function S.rump.etfs_register(key, hostpath, ftype, begin, size)
  ftype = RUMP_ETFS[ftype]
  if begin then
    local ret = ffi.C.rump_pub_etfs_register_withsize(key, hostpath, ftype, begin, size);
  else
    local ret = ffi.C.rump_pub_etfs_register(key, hostpath, ftype);
  end
  return retbool(ret)
end

function S.rump.etfs_remove(key)
  return retbool(rump.rump_pub_etfs_remove(key))
end

return S

