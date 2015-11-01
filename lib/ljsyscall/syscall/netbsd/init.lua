-- NetBSD init

-- This returns NetBSD types and constants (but no syscalls) under any OS.
-- Also returns util, which is a bit of a problem, as some of these will use syscalls
-- Currently used by kdump example to get NetBSD ktrace types

local require = require

local abi = require "syscall.abi"

local oldos, oldbsd = abi.os, abi.bsd

abi.os = "netbsd"
abi.bsd = true

-- TODO this should be shared with rump! temporarily here
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
  if string.find(tp, "struct") then
    return (string.gsub(tp, "struct (%a)", "struct _netbsd_%1"))
  end
  return "_netbsd_" .. tp
end

abi.rumpfn = rumpfn

abi.types = "netbsd"

local S = {}

require "syscall.netbsd.ffitypes"

local ostypes = require "syscall.netbsd.types"
local c = require "syscall.netbsd.constants"
local bsdtypes = require "syscall.bsd.types"
local types = require "syscall.types".init(c, ostypes, bsdtypes)

c.IOCTL = require("syscall." .. abi.os .. ".ioctl").init(types)
S.c = c
S.types = types
S.t = types.t
S.abi = abi
S.util = require "syscall.util".init(S)

abi.os, abi.bsd = oldos, oldbsd
abi.rumpfn = nil

return S



