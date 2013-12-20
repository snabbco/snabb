-- define system calls for ffi, OSX specific calls

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local cdef = require "ffi".cdef

cdef[[
int getdirentries(int fd, char *buf, int nbytes, long *basep);
int ioctl(int d, unsigned long request, void *arg);

int stat64(const char *path, struct stat *sb);
int lstat64(const char *path, struct stat *sb);
int fstat64(int fd, struct stat *sb);
]]

