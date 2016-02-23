-- define general BSD system calls for ffi

-- note that some functions may not be available in all, but so long as prototype is standard they can go here

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local cdef = require "ffi".cdef

-- standard Posix
cdef[[
int open(const char *pathname, int flags, mode_t mode);
int close(int fd);
int chdir(const char *path);
int fchdir(int fd);
int mkdir(const char *pathname, mode_t mode);
int rmdir(const char *pathname);
int unlink(const char *pathname);
int rename(const char *oldpath, const char *newpath);
int chmod(const char *path, mode_t mode);
int fchmod(int fd, mode_t mode);
int chown(const char *path, uid_t owner, gid_t group);
int fchown(int fd, uid_t owner, gid_t group);
int lchown(const char *path, uid_t owner, gid_t group);
int link(const char *oldpath, const char *newpath);
int linkat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath, int flags);
int symlink(const char *oldpath, const char *newpath);
int chroot(const char *path);
mode_t umask(mode_t mask);
void sync(void);
int mknod(const char *pathname, mode_t mode, dev_t dev);
int mkfifo(const char *path, mode_t mode);
ssize_t read(int fd, void *buf, size_t count);
ssize_t readv(int fd, const struct iovec *iov, int iovcnt);
ssize_t write(int fd, const void *buf, size_t count);
ssize_t writev(int fd, const struct iovec *iov, int iovcnt);
ssize_t pread(int fd, void *buf, size_t count, off_t offset);
ssize_t pwrite(int fd, const void *buf, size_t count, off_t offset);
ssize_t preadv(int fd, const struct iovec *iov, int iovcnt, off_t offset);
ssize_t pwritev(int fd, const struct iovec *iov, int iovcnt, off_t offset);
int access(const char *pathname, int mode);
off_t lseek(int fd, off_t offset, int whence);
ssize_t readlink(const char *path, char *buf, size_t bufsiz);
int fsync(int fd);
int fdatasync(int fd);
int fcntl(int fd, int cmd, void *arg); /* arg is long or pointer */
int stat(const char *path, struct stat *sb);
int lstat(const char *path, struct stat *sb);
int fstat(int fd, struct stat *sb);
int truncate(const char *path, off_t length);
int ftruncate(int fd, off_t length);
int shm_open(const char *pathname, int flags, mode_t mode);
int shm_unlink(const char *name);
int flock(int fd, int operation);

int socket(int domain, int type, int protocol);
int socketpair(int domain, int type, int protocol, int sv[2]);
int pipe2(int pipefd[2], int flags);
int dup(int oldfd);
int dup2(int oldfd, int newfd);
int dup3(int oldfd, int newfd, int flags);

ssize_t recv(int sockfd, void *buf, size_t len, int flags);
ssize_t send(int sockfd, const void *buf, size_t len, int flags);
ssize_t sendto(int sockfd, const void *buf, size_t len, int flags, const struct sockaddr *dest_addr, socklen_t addrlen);
ssize_t recvfrom(int sockfd, void *buf, size_t len, int flags, struct sockaddr *src_addr, socklen_t *addrlen);
ssize_t sendmsg(int sockfd, const struct msghdr *msg, int flags);
ssize_t recvmsg(int sockfd, struct msghdr *msg, int flags);
int getsockopt(int sockfd, int level, int optname, void *optval, socklen_t *optlen);
int setsockopt(int sockfd, int level, int optname, const void *optval, socklen_t optlen);
int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
int listen(int sockfd, int backlog);
int connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
int accept(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
int accept4(int sockfd, void *addr, socklen_t *addrlen, int flags);
int getsockname(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
int getpeername(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
int shutdown(int sockfd, int how);
int pipe(int pipefd[2]);
int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, struct timeval *timeout);
int poll(struct pollfd *fds, nfds_t nfds, int timeout);
int pselect(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, const struct timespec *timeout, const sigset_t *sigmask);
int nanosleep(const struct timespec *req, struct timespec *rem);
int getrusage(int who, struct rusage *usage);
int getpriority(int which, int who);
int setpriority(int which, int who, int prio);
int sendmmsg(int sockfd, struct mmsghdr *msgvec, unsigned int vlen, unsigned int flags);
int recvmmsg(int sockfd, struct mmsghdr *msgvec, unsigned int vlen, unsigned int flags, struct timespec *timeout);

uid_t getuid(void);
uid_t geteuid(void);
pid_t getpid(void);
pid_t getppid(void);
gid_t getgid(void);
gid_t getegid(void);
int setuid(uid_t uid);
int setgid(gid_t gid);
int seteuid(uid_t euid);
int setegid(gid_t egid);
pid_t getsid(pid_t pid);
pid_t setsid(void);
int setpgid(pid_t pid, pid_t pgid);
pid_t getpgid(pid_t pid);
pid_t getpgrp(void);

pid_t fork(void);
int execve(const char *filename, const char *argv[], const char *envp[]);
void exit(int status);
void _exit(int status);
int sigaction(int signum, const struct sigaction *act, struct sigaction *oldact);
int sigprocmask(int how, const sigset_t *set, sigset_t *oldset);
int sigpending(sigset_t *set);
int sigsuspend(const sigset_t *mask);
int kill(pid_t pid, int sig);

int getgroups(int size, gid_t list[]);
int setgroups(size_t size, const gid_t *list);

int gettimeofday(struct timeval *tv, void *tz);
int settimeofday(const struct timeval *tv, const void *tz);
int getitimer(int which, struct itimerval *curr_value);
int setitimer(int which, const struct itimerval *new_value, struct itimerval *old_value);

int acct(const char *filename);

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);
int munmap(void *addr, size_t length);
int msync(void *addr, size_t length, int flags);
int madvise(void *addr, size_t length, int advice);
int mlock(const void *addr, size_t len);
int munlock(const void *addr, size_t len);
int mlockall(int flags);
int munlockall(void);

int openat(int dirfd, const char *pathname, int flags, mode_t mode);
int mkdirat(int dirfd, const char *pathname, mode_t mode);
int unlinkat(int dirfd, const char *pathname, int flags);
int renameat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath);
int fchownat(int dirfd, const char *pathname, uid_t owner, gid_t group, int flags);
int symlinkat(const char *oldpath, int newdirfd, const char *newpath);
int mknodat(int dirfd, const char *pathname, mode_t mode, dev_t dev);
int mkfifoat(int dirfd, const char *pathname, mode_t mode);
int fchmodat(int dirfd, const char *pathname, mode_t mode, int flags);
int readlinkat(int dirfd, const char *pathname, char *buf, size_t bufsiz);
int faccessat(int dirfd, const char *pathname, int mode, int flags);
int fstatat(int dirfd, const char *pathname, struct stat *buf, int flags);

int futimens(int fd, const struct timespec times[2]);
int utimensat(int dirfd, const char *pathname, const struct timespec times[2], int flags);

int lchmod(const char *path, mode_t mode);
int fchroot(int fd);
int utimes(const char *filename, const struct timeval times[2]);
int futimes(int, const struct timeval times[2]);
int lutimes(const char *filename, const struct timeval times[2]);
pid_t wait4(pid_t wpid, int *status, int options, struct rusage *rusage);
int posix_openpt(int oflag);

int clock_getres(clockid_t clk_id, struct timespec *res);
int clock_gettime(clockid_t clk_id, struct timespec *tp);
int clock_settime(clockid_t clk_id, const struct timespec *tp);
int clock_nanosleep(clockid_t clock_id, int flags, const struct timespec *request, struct timespec *remain);

int getpagesize(void);

int timer_create(clockid_t clockid, struct sigevent *sevp, timer_t *timerid);
int timer_settime(timer_t timerid, int flags, const struct itimerspec *new_value, struct itimerspec * old_value);
int timer_gettime(timer_t timerid, struct itimerspec *curr_value);
int timer_delete(timer_t timerid);
int timer_getoverrun(timer_t timerid);

int adjtime(const struct timeval *delta, struct timeval *olddelta);

int aio_cancel(int, struct aiocb *);
int aio_error(const struct aiocb *);
int aio_fsync(int, struct aiocb *);
int aio_read(struct aiocb *);
int aio_return(struct aiocb *);
int aio_write(struct aiocb *);
int lio_listio(int, struct aiocb *const *, int, struct sigevent *);
int aio_suspend(const struct aiocb *const *, int, const struct timespec *);
int aio_waitcomplete(struct aiocb **, struct timespec *);
]]

-- BSD specific
cdef[[
int getdirentries(int fd, char *buf, int nbytes, long *basep);
int unmount(const char *dir, int flags);
int revoke(const char *path);
int chflags(const char *path, unsigned long flags);
int lchflags(const char *path, unsigned long flags);
int fchflags(int fd, unsigned long flags);
int chflagsat(int fd, const char *path, unsigned long flags, int atflag);
long pathconf(const char *path, int name);
long lpathconf(const char *path, int name);
long fpathconf(int fd, int name);
int kqueue(void);
int kqueue1(int flags);
int kevent(int kq, const struct kevent *changelist, size_t nchanges, struct kevent *eventlist, size_t nevents, const struct timespec *timeout);
int issetugid(void);
int ktrace(const char *tracefile, int ops, int trpoints, pid_t pid);

int     extattrctl(const char *path, int cmd, const char *filename, int attrnamespace, const char *attrname);
int     extattr_delete_fd(int fd, int attrnamespace, const char *attrname);
int     extattr_delete_file(const char *path, int attrnamespace, const char *attrname);
int     extattr_delete_link(const char *path, int attrnamespace, const char *attrname);
ssize_t extattr_get_fd(int fd, int attrnamespace, const char *attrname, void *data, size_t nbytes);
ssize_t extattr_get_file(const char *path, int attrnamespace, const char *attrname, void *data, size_t nbytes);
ssize_t extattr_get_link(const char *path, int attrnamespace, const char *attrname, void *data, size_t nbytes);
ssize_t extattr_list_fd(int fd, int attrnamespace, void *data, size_t nbytes);
ssize_t extattr_list_file(const char *path, int attrnamespace, void *data, size_t nbytes);
ssize_t extattr_list_link(const char *path, int attrnamespace, void *data, size_t nbytes);
ssize_t extattr_set_fd(int fd, int attrnamespace, const char *attrname, const void *data, size_t nbytes);
ssize_t extattr_set_file(const char *path, int attrnamespace, const char *attrname, const void *data, size_t nbytes);
ssize_t extattr_set_link(const char *path, int attrnamespace, const char *attrname, const void *data, size_t nbytes);
]]
