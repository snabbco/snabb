-- define system calls for ffi, OpenBSD specific calls

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local cdef = require "ffi".cdef

cdef[[
int reboot(int howto);
int ioctl(int d, unsigned long request, void *arg);

/* not syscalls, but using for now */
int grantpt(int fildes);
int unlockpt(int fildes);
char *ptsname(int fildes);
int getdents(int fd, void *buf, size_t nbytes);
]]

