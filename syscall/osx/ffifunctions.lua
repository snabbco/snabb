-- define system calls for ffi, OSX specific calls

local cdef = require "ffi".cdef

cdef[[
int lchmod(const char *path, mode_t mode);
int fchroot(int fd);
int stat64(const char *path, struct stat *sb);
int lstat64(const char *path, struct stat *sb);
int fstat64(int fd, struct stat *sb);
]]

