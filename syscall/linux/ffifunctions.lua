-- define Linux system calls for ffi

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local cdef = require "ffi".cdef

-- as we just use syscall for Linux there is not much here

cdef[[
long syscall(int number, ...);

int gettimeofday(struct timeval *tv, void *tz);

]]

