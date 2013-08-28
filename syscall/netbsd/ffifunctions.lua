-- define system calls for ffi, BSD specific calls

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit

local cdef = require "ffi".cdef

cdef[[
int lchmod(const char *path, mode_t mode);
int fchroot(int fd);
int dup3(int oldfd, int newfd, int flags);
int fsync_range(int fd, int how, off_t start, off_t length);
int paccept(int s, struct sockaddr *addr, socklen_t *addrlen, const sigset_t *sigmask, int flags);
int pipe2(int pipefd[2], int flags);
int unmount(const char *dir, int flags);
int reboot(int howto, char *bootstr);
int futimens(int fd, const struct timespec times[2]);
int utimensat(int dirfd, const char *pathname, const struct timespec times[2], int flags);
int poll(struct pollfd *fds, nfds_t nfds, int timeout);
int revoke(const char *path);
int chflags(const char *path, unsigned long flags);
int lchflags(const char *path, unsigned long flags);
int fchflags(int fd, unsigned long flags);
long pathconf(const char *path, int name);
long fpathconf(int fd, int name);
int ioctl(int d, unsigned long request, ...);
int getvfsstat(struct statvfs *buf, size_t bufsize, int flags);

int __mount50(const char *type, const char *dir, int flags, void *data, size_t data_len);
int __stat50(const char *path, struct stat *sb);
int __lstat50(const char *path, struct stat *sb);
int __fstat50(int fd, struct stat *sb);
int __getdents30(int fd, char *buf, size_t nbytes);

int syscall(int number, ...);
]]

--[[ -- need more types defined
pid_t wait4(pid_t wpid, int *status, int options, struct rusage *rusage);
]]

-- setreuid, setregid are deprecated, implement by other means

-- setpgrp see man pages, may need these for BSD

