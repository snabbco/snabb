-- define system calls for ffi, BSD specific calls

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local cdef = require "ffi".cdef

cdef[[
int lchmod(const char *path, mode_t mode);
int fchroot(int fd);
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
int kqueue(void);
int kqueue1(int flags);
int pollts(struct pollfd * restrict fds, nfds_t nfds, const struct timespec * restrict ts, const sigset_t * restrict sigmask);
int issetugid(void);
pid_t wait4(pid_t wpid, int *status, int options, struct rusage *rusage);

int __mount50(const char *type, const char *dir, int flags, void *data, size_t data_len);
int __stat50(const char *path, struct stat *sb);
int __lstat50(const char *path, struct stat *sb);
int __fstat50(int fd, struct stat *sb);
int __getdents30(int fd, char *buf, size_t nbytes);
int __socket30(int domain, int type, int protocol);
int __select50(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, struct timeval *timeout);
int __pselect50(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, const struct timespec *timeout, const sigset_t *sigmask);

int __fhopen40(const void *fhp, size_t fh_size, int flags);
int __fhstat50(const void *fhp, size_t fh_size, struct stat *sb);
int __fhstatvfs140(const void *fhp, size_t fh_size, struct statvfs *buf, int flags);
int __getfh30(const char *path, void *fhp, size_t *fh_size);
int __utimes50(const char *path, const struct timeval times[2]);
int __lutimes50(const char *path, const struct timeval times[2]);
int __futimes50(int fd, const struct timeval times[2]);
int __posix_fadvise50(int fd, off_t offset, off_t size, int hint);
int __kevent50(int kq, const struct kevent *changelist, size_t nchanges, struct kevent *eventlist, size_t nevents, const struct timespec *timeout);

int __getcwd(char *buf, size_t size);

int syscall(int number, ...);
]]

