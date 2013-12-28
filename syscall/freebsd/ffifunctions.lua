-- define system calls for ffi, FreeBSD specific calls

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

int connectat(int fd, int s, const struct sockaddr *name, socklen_t namelen);
int bindat(int fd, int s, const struct sockaddr *addr, socklen_t addrlen);
int pdfork(int *fdp, int flags);
int pdgetpid(int fd, pid_t *pidp);
int pdkill(int fd, int signum);
int pdwait4(int fd, int *status, int options, struct rusage *rusage);
int cap_fcntls_limit(int fd, uint32_t fcntlrights);
int cap_fcntls_get(int fd, uint32_t *fcntlrightsp);

int __sys_utimes(const char *filename, const struct timeval times[2]);
int __sys_futimes(int, const struct timeval times[2]);
int __sys_lutimes(const char *filename, const struct timeval times[2]);
pid_t __sys_wait4(pid_t wpid, int *status, int options, struct rusage *rusage);
]]

