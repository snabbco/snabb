-- define system calls for ffi, BSD specific calls

local cdef = require "ffi".cdef

cdef[[
int lchmod(const char *path, mode_t mode);
int fchroot(int fd);
int dup3(int oldfd, int newfd, int flags);
int fsync_range(int fd, int how, off_t start, off_t length);
int paccept(int s, struct sockaddr *addr, socklen_t *addrlen, const sigset_t *sigmask, int flags);
int pipe2(int pipefd[2], int flags);
int mount(const char *type, const char *dir, int flags, void *data, size_t data_len);
int unmount(const char *dir, int flags);
int reboot(int howto, char *bootstr);

int syscall(int number, ...);
//quad_t __syscall(quad_t number, ...);
]]

--[[ -- need more types defined
pid_t wait4(pid_t wpid, int *status, int options, struct rusage *rusage);
]]

-- setreuid, setregid are deprecated, implement by other means

-- setpgrp see man pages, may need these for BSD

