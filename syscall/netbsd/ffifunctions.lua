-- define system calls for ffi, BSD specific calls

local cdef = require "ffi".cdef

require "syscall.ffitypes"

cdef[[
int lchmod(const char *path, mode_t mode);
int fchroot(int fd);
int dup3(int oldfd, int newfd, int flags);
int fsync_range(int fd, int how, off_t start, off_t length);
int paccept(int s, struct sockaddr *addr, socklen_t *addrlen, const sigset_t *sigmask, int flags);

int syscall(int number, ...);
//quad_t __syscall(quad_t number, ...);
]]

--[[ -- need more types defined
pid_t wait4(pid_t wpid, int *status, int options, struct rusage *rusage);
]]

-- in BSD these are in man(3) but that is ok as we require standard libc; however not in rump kernel of course
-- some however could implement ourself, using sysctl etc

--[[ -- need more types defined
int uname(struct utsname *buf);
time_t time(time_t *t);
]]

cdef[[
int gethostname(char *name, size_t namelen);
int sethostname(const char *name, size_t len);
int getdomainname(char *name, size_t namelen);
int setdomainname(const char *name, size_t len);
void exit(int status);
char *getcwd(char *buf, size_t size);
]]

-- setreuid, setregid are deprecated, implement by other means

-- setpgrp see man pages, may need these for BSD

