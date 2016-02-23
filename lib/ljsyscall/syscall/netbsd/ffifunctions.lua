-- define system calls for ffi, NetBSD specific calls

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

require "syscall.bsd.ffi"

local cdef = require "ffi".cdef

cdef[[
int fsync_range(int fd, int how, off_t start, off_t length);
int paccept(int s, struct sockaddr *addr, socklen_t *addrlen, const sigset_t *sigmask, int flags);
int reboot(int howto, char *bootstr);
int ioctl(int d, unsigned long request, void *arg);
int getvfsstat(struct statvfs *buf, size_t bufsize, int flags);
int utrace(const char *label, void *addr, size_t len);
int fktrace(int fd, int ops, int trpoints, pid_t pid);

ssize_t listxattr(const char *path, char *list, size_t size);
ssize_t llistxattr(const char *path, char *list, size_t size);
ssize_t flistxattr(int fd, char *list, size_t size);
ssize_t getxattr(const char *path, const char *name, void *value, size_t size);
ssize_t lgetxattr(const char *path, const char *name, void *value, size_t size);
ssize_t fgetxattr(int fd, const char *name, void *value, size_t size);
int setxattr(const char *path, const char *name, const void *value, size_t size, int flags);
int lsetxattr(const char *path, const char *name, const void *value, size_t size, int flags);
int fsetxattr(int fd, const char *name, const void *value, size_t size, int flags);
int removexattr(const char *path, const char *name);
int lremovexattr(const char *path, const char *name);
int fremovexattr(int fd, const char *name);

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
int __mknod50(const char *path, mode_t mode, dev_t dev);
int __pollts50(struct pollfd * restrict fds, nfds_t nfds, const struct timespec * restrict ts, const sigset_t * restrict sigmask);

int __getcwd(char *buf, size_t size);
int __libc_sigaction14(int signum, const struct sigaction *act, struct sigaction *oldact);

int _ksem_init(unsigned int, intptr_t *);
int _ksem_open(const char *, int, mode_t, unsigned int, intptr_t *);
int _ksem_unlink(const char *);
int _ksem_close(intptr_t);
int _ksem_post(intptr_t);
int _ksem_wait(intptr_t);
int _ksem_trywait(intptr_t);
int _ksem_getvalue(intptr_t, unsigned int *);
int _ksem_destroy(intptr_t);
int _ksem_timedwait(intptr_t, const struct timespec *);

int __gettimeofday50(struct timeval *tv, void *tz);
int __settimeofday50(const struct timeval *tv, const void *tz);
int __getitimer50(int which, struct itimerval *curr_value);
int __setitimer50(int which, const struct itimerval *new_value, struct itimerval *old_value);
int __clock_getres50(clockid_t clk_id, struct timespec *res);
int __clock_gettime50(clockid_t clk_id, struct timespec *tp);
int __clock_settime50(clockid_t clk_id, const struct timespec *tp);
int __nanosleep50(const struct timespec *req, struct timespec *rem);
int __timer_settime50(timer_t timerid, int flags, const struct itimerspec *new_value, struct itimerspec * old_value);
int __timer_gettime50(timer_t timerid, struct itimerspec *curr_value);
int __adjtime50(const struct timeval *delta, struct timeval *olddelta);
]]

