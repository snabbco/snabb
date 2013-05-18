-- rump kernel ffi functions

local abi = require "syscall.abi"

local ffi = require "ffi"
local cdef

if ffi.os == "netbsd" then
  require "syscall.ffitypes" -- with rump on NetBSD the types are the same
  cdef = function(s)
    s = string.gsub(s, "_netbsd_", "") -- no netbsd types
    ffi.cdef(s)
  end
else
  require "syscall.ffitypes-common"

  local netbsd = require "syscall.netbsd.ffitypes-common"

  netbsd.init(true) -- rump = true

-- TODO delete
ffi.cdef[[
typedef uint32_t _netbsd_mode_t;
typedef unsigned int _netbsd_size_t;
typedef int _netbsd_ssize_t;
]]
  cdef = ffi.cdef -- use as provided
end

cdef [[
_netbsd_ssize_t rump_sys_read(int, void *, _netbsd_size_t);
_netbsd_ssize_t rump_sys_write(int, const void *, _netbsd_size_t);
int rump_sys_open(const char *, int, _netbsd_mode_t);
int rump_sys_close(int);
int rump_sys_link(const char *, const char *);
int rump_sys_unlink(const char *);
int rump_sys_chdir(const char *);
int rump_sys_fchdir(int);
int rump_sys_mknod(const char *, _netbsd_mode_t, uint32_t);
int rump_sys_chmod(const char *, _netbsd_mode_t);
int rump_sys_chown(const char *, uid_t, gid_t);
pid_t rump_sys_getpid(void);
int rump_sys_unmount(const char *, int);
int rump_sys_setuid(uid_t);
uid_t rump_sys_getuid(void);
uid_t rump_sys_geteuid(void);
_netbsd_ssize_t rump_sys_recvmsg(int, struct _netbsd_msghdr *, int);
_netbsd_ssize_t rump_sys_sendmsg(int, const struct _netbsd_msghdr *, int);
_netbsd_ssize_t rump_sys_recvfrom(int, void *, size_t, int, struct _netbsd_sockaddr *, _netbsd_socklen_t *);
int rump_sys_accept(int, struct _netbsd_sockaddr *, _netbsd_socklen_t *);
int rump_sys_getpeername(int, struct _netbsd_sockaddr *, _netbsd_socklen_t *);
int rump_sys_getsockname(int, struct _netbsd_sockaddr *, _netbsd_socklen_t *);
int rump_sys_access(const char *, int);
int rump_sys_chflags(const char *, unsigned long);
int rump_sys_fchflags(int, unsigned long);
void rump_sys_sync(void);
pid_t rump_sys_getppid(void);
int rump_sys_dup(int);
gid_t rump_sys_getegid(void);
gid_t rump_sys_getgid(void);
int rump_sys___getlogin(char *, _netbsd_size_t);
int rump_sys___setlogin(const char *);
int rump_sys_ioctl(int, unsigned long, ...);
int rump_sys_revoke(const char *);
int rump_sys_symlink(const char *, const char *);
_netbsd_ssize_t rump_sys_readlink(const char *, char *, size_t);
mode_t rump_sys_umask(_netbsd_mode_t);
int rump_sys_chroot(const char *);
int rump_sys_getgroups(int, gid_t *);
int rump_sys_setgroups(int, const gid_t *);
int rump_sys_getpgrp(void);
int rump_sys_setpgid(pid_t, pid_t);
int rump_sys_dup2(int, int);
int rump_sys_fcntl(int, int, ...);
int rump_sys_select(int, _netbsd_fd_set *, _netbsd_fd_set *, _netbsd_fd_set *, struct _netbsd_timeval *);
int rump_sys_fsync(int);
int rump_sys_connect(int, const struct _netbsd_sockaddr *, _netbsd_socklen_t);
int rump_sys_bind(int, const struct _netbsd_sockaddr *, _netbsd_socklen_t);
int rump_sys_setsockopt(int, int, int, const void *, _netbsd_socklen_t);
int rump_sys_listen(int, int);
int rump_sys_getsockopt(int, int, int, void *, _netbsd_socklen_t *);
_netbsd_ssize_t rump_sys_readv(int, const struct _netbsd_iovec *, int);
_netbsd_ssize_t rump_sys_writev(int, const struct _netbsd_iovec *, int);
int rump_sys_fchown(int, uid_t, gid_t);
int rump_sys_fchmod(int, _netbsd_mode_t);
int rump_sys_setreuid(uid_t, uid_t);
int rump_sys_setregid(gid_t, gid_t);
int rump_sys_rename(const char *, const char *);
int rump_sys_flock(int, int);
int rump_sys_mkfifo(const char *, _netbsd_mode_t);
_netbsd_ssize_t rump_sys_sendto(int, const void *, size_t, int, const struct _netbsd_sockaddr *, _netbsd_socklen_t);
int rump_sys_shutdown(int, int);
int rump_sys_socketpair(int, int, int, int *);
int rump_sys_mkdir(const char *, _netbsd_mode_t);
int rump_sys_rmdir(const char *);
int rump_sys_utimes(const char *, const struct _netbsd_timeval *);
int rump_sys_setsid(void);
int rump_sys_nfssvc(int, void *);
_netbsd_ssize_t rump_sys_pread(int, void *, size_t, off_t);
_netbsd_ssize_t rump_sys_pwrite(int, const void *, size_t, off_t);
int rump_sys_setgid(gid_t);
int rump_sys_setegid(gid_t);
int rump_sys_seteuid(uid_t);
long rump_sys_pathconf(const char *, int);
long rump_sys_fpathconf(int, int);
int rump_sys_getrlimit(int, struct _netbsd_rlimit *);
int rump_sys_setrlimit(int, const struct _netbsd_rlimit *);
off_t rump_sys_lseek(int, off_t, int);
int rump_sys_truncate(const char *, off_t);
int rump_sys_ftruncate(int, off_t);
int rump_sys___sysctl(const int *, u_int, void *, size_t *, const void *, _netbsd_size_t);
int rump_sys_futimes(int, const struct _netbsd_timeval *);
pid_t rump_sys_getpgid(pid_t);
int rump_sys_reboot(int, char *);
int rump_sys_poll(struct _netbsd_pollfd *, unisgned int, int);
int rump_sys_fdatasync(int);
int rump_sys_modctl(int, void *);
int rump_sys__ksem_init(unsigned int, intptr_t *);
int rump_sys__ksem_open(const char *, int, _netbsd_mode_t, unsigned int, intptr_t *);
int rump_sys__ksem_unlink(const char *);
int rump_sys__ksem_close(intptr_t);
int rump_sys__ksem_post(intptr_t);
int rump_sys__ksem_wait(intptr_t);
int rump_sys__ksem_trywait(intptr_t);
int rump_sys__ksem_getvalue(intptr_t, unsigned int *);
int rump_sys__ksem_destroy(intptr_t);
int rump_sys__ksem_timedwait(intptr_t, const struct _netbsd_timespec *);
int rump_sys_lchmod(const char *, _netbsd_mode_t);
int rump_sys_lchown(const char *, uid_t, gid_t);
int rump_sys_lutimes(const char *, const struct _netbsd_timeval *);
pid_t rump_sys_getsid(pid_t);
_netbsd_ssize_t rump_sys_preadv(int, const struct _netbsd_iovec *, int, off_t);
_netbsd_ssize_t rump_sys_pwritev(int, const struct _netbsd_iovec *, int, off_t);
int rump_sys___getcwd(char *, _netbsd_size_t);
int rump_sys_fchroot(int);
int rump_sys_lchflags(const char *, unsigned long);
int rump_sys_issetugid(void);
int rump_sys_kqueue(void);
int rump_sys_kevent(int, const struct _netbsd_kevent *, size_t, struct _netbsd_kevent *, size_t, const struct _netbsd_timespec *);
int rump_sys_fsync_range(int, int, off_t, off_t);
int rump_sys_getvfsstat(struct _netbsd_statvfs *, size_t, int);
int rump_sys_statvfs1(const char *, struct _netbsd_statvfs *, int);
int rump_sys_fstatvfs1(int, struct _netbsd_statvfs *, int);
int rump_sys_extattrctl(const char *, int, const char *, int, const char *);
int rump_sys_extattr_set_file(const char *, int, const char *, const void *, _netbsd_size_t);
_netbsd_ssize_t rump_sys_extattr_get_file(const char *, int, const char *, void *, _netbsd_size_t);
int rump_sys_extattr_delete_file(const char *, int, const char *);
int rump_sys_extattr_set_fd(int, int, const char *, const void *, _netbsd_size_t);
_netbsd_ssize_t rump_sys_extattr_get_fd(int, int, const char *, void *, _netbsd_size_t);
int rump_sys_extattr_delete_fd(int, int, const char *);
int rump_sys_extattr_set_link(const char *, int, const char *, const void *, _netbsd_size_t);
_netbsd_ssize_t rump_sys_extattr_get_link(const char *, int, const char *, void *, _netbsd_size_t);
int rump_sys_extattr_delete_link(const char *, int, const char *);
_netbsd_ssize_t rump_sys_extattr_list_fd(int, int, void *, _netbsd_size_t);
_netbsd_ssize_t rump_sys_extattr_list_file(const char *, int, void *, _netbsd_size_t);
_netbsd_ssize_t rump_sys_extattr_list_link(const char *, int, void *, _netbsd_size_t);
int rump_sys_pselect(int, _netbsd_fd_set *, _netbsd_fd_set *, _netbsd_fd_set *, const struct _netbsd_timespec *, const _netbsd_sigset_t *);
int rump_sys_pollts(struct _netbsd_pollfd *, unsigned int, const struct _netbsd_timespec *, const _netbsd_sigset_t *);
int rump_sys_setxattr(const char *, const char *, const void *, _netbsd_size_t, int);
int rump_sys_lsetxattr(const char *, const char *, const void *, _netbsd_size_t, int);
int rump_sys_fsetxattr(int, const char *, const void *, _netbsd_size_t, int);
int rump_sys_getxattr(const char *, const char *, void *, _netbsd_size_t);
int rump_sys_lgetxattr(const char *, const char *, void *, _netbsd_size_t);
int rump_sys_fgetxattr(int, const char *, void *, _netbsd_size_t);
int rump_sys_listxattr(const char *, char *, _netbsd_size_t);
int rump_sys_llistxattr(const char *, char *, _netbsd_size_t);
int rump_sys_flistxattr(int, char *, _netbsd_size_t);
int rump_sys_removexattr(const char *, const char *);
int rump_sys_lremovexattr(const char *, const char *);
int rump_sys_fremovexattr(int, const char *);
int rump_sys_stat(const char *, struct stat *);
int rump_sys_fstat(int, struct stat *);
int rump_sys_lstat(const char *, struct stat *);
int rump_sys_getdents(int, char *, _netbsd_size_t);
int rump_sys_socket(int, int, int);
int rump_sys_getfh(const char *, void *, _netbsd_size_t *);
int rump_sys_fhopen(const void *, _netbsd_size_t, int);
int rump_sys_fhstatvfs1(const void *, size_t, struct _netbsd_statvfs *, int);
int rump_sys_fhstat(const void *, _netbsd_size_t, struct _netbsd_stat *);
int rump_sys_mount(const char *, const char *, int, void *, _netbsd_size_t);
int rump_sys_posix_fadvise(int, off_t, off_t, int);
int rump_sys_pipe2(int *, int);
int rump_sys_dup3(int, int, int);
int rump_sys_kqueue1(int);
int rump_sys_paccept(int, struct _netbsd_sockaddr *, _netbsd_socklen_t *, const _netbsd_sigset_t *, int);
int rump_sys_linkat(int, const char *, int, const char *, int);
int rump_sys_renameat(int, const char *, int, const char *);
int rump_sys_mkfifoat(int, const char *, _netbsd_mode_t);
int rump_sys_mknodat(int, const char *, _netbsd_mode_t, uint32_t);
int rump_sys_mkdirat(int, const char *, _netbsd_mode_t);
int rump_sys_faccessat(int, const char *, int, int);
int rump_sys_fchmodat(int, const char *, _netbsd_mode_t, int);
int rump_sys_fchownat(int, const char *, uid_t, gid_t, int);
int rump_sys_fexecve(int, char *const *, char *const *);
int rump_sys_fstatat(int, const char *, struct _netbsd_stat *, int);
int rump_sys_utimensat(int, const char *, const struct _netbsd_timespec *, int);
int rump_sys_openat(int, const char *, int, ...);
int rump_sys_readlinkat(int, const char *, char *, _netbsd_size_t);
int rump_sys_symlinkat(const char *, int, const char *);
int rump_sys_unlinkat(int, const char *, int);
int rump_sys_futimens(int, const struct _netbsd_timespec *);
int rump_sys___quotactl(const char *, struct _netbsd_quotactl_args *);
int rump_sys_pipe(int *);
]]

