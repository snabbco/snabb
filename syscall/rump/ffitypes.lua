-- rump ffi types
-- these are generally NetBSD kernel types not exposed to userspace so not in NetBSD types file

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit

local cdef = require "ffi".cdef

cdef[[
typedef struct modinfo {
  unsigned int    mi_version;
  int             mi_class;
  int             (*mi_modcmd)(int, void *);
  const char      *mi_name;
  const char      *mi_required;
} const modinfo_t;
]]
