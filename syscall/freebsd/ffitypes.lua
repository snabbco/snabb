-- This are the types for FreeBSD

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local abi = require "syscall.abi"

local defs = {}

local function append(str) defs[#defs + 1] = str end

append [[
typedef uint32_t      blksize_t;
typedef int64_t       blkcnt_t;
typedef int32_t       clockid_t;
typedef uint32_t      fflags_t;
typedef uint64_t      fsblkcnt_t;
typedef uint64_t      fsfilcnt_t;
typedef int64_t       id_t;
typedef uint32_t      ino_t;
typedef long          key_t;
typedef int32_t       lwpid_t;
typedef uint16_t      mode_t;
typedef int           accmode_t;
typedef int           nl_item;
typedef uint16_t      nlink_t;
typedef int64_t       rlim_t;
typedef uint8_t       sa_family_t;
typedef long          suseconds_t;
//typedef struct __timer  *__timer_t;
//typedef struct __mq     *__mqd_t;
typedef unsigned int  useconds_t;
typedef int           cpuwhich_t;
typedef int           cpulevel_t;
typedef int           cpusetid_t;
typedef uint32_t      dev_t;
typedef uint32_t      fixpt_t;
]]

local s = table.concat(defs, "")

local ffi = require "ffi"
ffi.cdef(s)

