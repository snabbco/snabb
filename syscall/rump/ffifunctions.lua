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

  cdef = ffi.cdef -- use as provided
end

-- TODO note a few commented out due to types not yet defined
cdef [[
_netbsd_ssize_t rump___sysimpl_read(int, void *, _netbsd_size_t);
_netbsd_ssize_t rump___sysimpl_write(int, const void *, _netbsd_size_t);
int rump___sysimpl_open(const char *, int, _netbsd_mode_t);
int rump___sysimpl_close(int);
int rump___sysimpl_link(const char *, const char *);
int rump___sysimpl_unlink(const char *);
int rump___sysimpl_chdir(const char *);
int rump___sysimpl_fchdir(int);
int rump___sysimpl_mknod(const char *, _netbsd_mode_t, uint32_t);
int rump___sysimpl_chmod(const char *, _netbsd_mode_t);
int rump___sysimpl_chown(const char *, uid_t, gid_t);
pid_t rump___sysimpl_getpid(void);
int rump___sysimpl_unmount(const char *, int);
int rump___sysimpl_setuid(uid_t);
uid_t rump___sysimpl_getuid(void);
uid_t rump___sysimpl_geteuid(void);
_netbsd_ssize_t rump___sysimpl_recvmsg(int, struct _netbsd_msghdr *, int);
_netbsd_ssize_t rump___sysimpl_sendmsg(int, const struct _netbsd_msghdr *, int);
_netbsd_ssize_t rump___sysimpl_recvfrom(int, void *, size_t, int, struct _netbsd_sockaddr *, _netbsd_socklen_t *);
int rump___sysimpl_accept(int, struct _netbsd_sockaddr *, _netbsd_socklen_t *);
int rump___sysimpl_getpeername(int, struct _netbsd_sockaddr *, _netbsd_socklen_t *);
int rump___sysimpl_getsockname(int, struct _netbsd_sockaddr *, _netbsd_socklen_t *);
int rump___sysimpl_access(const char *, int);
int rump___sysimpl_chflags(const char *, unsigned long);
int rump___sysimpl_fchflags(int, unsigned long);
void rump___sysimpl_sync(void);
pid_t rump___sysimpl_getppid(void);
int rump___sysimpl_dup(int);
gid_t rump___sysimpl_getegid(void);
gid_t rump___sysimpl_getgid(void);
int rump___sysimpl___getlogin(char *, _netbsd_size_t);
int rump___sysimpl___setlogin(const char *);
int rump___sysimpl_ioctl(int, unsigned long, ...);
int rump___sysimpl_revoke(const char *);
int rump___sysimpl_symlink(const char *, const char *);
_netbsd_ssize_t rump___sysimpl_readlink(const char *, char *, size_t);
_netbsd_mode_t rump___sysimpl_umask(_netbsd_mode_t);
int rump___sysimpl_chroot(const char *);
int rump___sysimpl_getgroups(int, gid_t *);
int rump___sysimpl_setgroups(int, const gid_t *);
int rump___sysimpl_getpgrp(void);
int rump___sysimpl_setpgid(pid_t, pid_t);
int rump___sysimpl_dup2(int, int);
int rump___sysimpl_fcntl(int, int, ...);
//int rump___sysimpl_select50(int, _netbsd_fd_set *, _netbsd_fd_set *, _netbsd_fd_set *, struct _netbsd_timeval *);
int rump___sysimpl_fsync(int);
int rump___sysimpl_connect(int, const struct _netbsd_sockaddr *, _netbsd_socklen_t);
int rump___sysimpl_bind(int, const struct _netbsd_sockaddr *, _netbsd_socklen_t);
int rump___sysimpl_setsockopt(int, int, int, const void *, _netbsd_socklen_t);
int rump___sysimpl_listen(int, int);
int rump___sysimpl_getsockopt(int, int, int, void *, _netbsd_socklen_t *);
_netbsd_ssize_t rump___sysimpl_readv(int, const struct _netbsd_iovec *, int);
_netbsd_ssize_t rump___sysimpl_writev(int, const struct _netbsd_iovec *, int);
int rump___sysimpl_fchown(int, uid_t, gid_t);
int rump___sysimpl_fchmod(int, _netbsd_mode_t);
int rump___sysimpl_setreuid(uid_t, uid_t);
int rump___sysimpl_setregid(gid_t, gid_t);
int rump___sysimpl_rename(const char *, const char *);
int rump___sysimpl_flock(int, int);
int rump___sysimpl_mkfifo(const char *, _netbsd_mode_t);
_netbsd_ssize_t rump___sysimpl_sendto(int, const void *, size_t, int, const struct _netbsd_sockaddr *, _netbsd_socklen_t);
int rump___sysimpl_shutdown(int, int);
int rump___sysimpl_socketpair(int, int, int, int *);
int rump___sysimpl_mkdir(const char *, _netbsd_mode_t);
int rump___sysimpl_rmdir(const char *);
int rump___sysimpl_utimes(const char *, const struct _netbsd_timeval *);
int rump___sysimpl_setsid(void);
int rump___sysimpl_nfssvc(int, void *);
_netbsd_ssize_t rump___sysimpl_pread(int, void *, size_t, off_t);
_netbsd_ssize_t rump___sysimpl_pwrite(int, const void *, size_t, off_t);
int rump___sysimpl_setgid(gid_t);
int rump___sysimpl_setegid(gid_t);
int rump___sysimpl_seteuid(uid_t);
long rump___sysimpl_pathconf(const char *, int);
long rump___sysimpl_fpathconf(int, int);
int rump___sysimpl_getrlimit(int, struct _netbsd_rlimit *);
int rump___sysimpl_setrlimit(int, const struct _netbsd_rlimit *);
off_t rump___sysimpl_lseek(int, off_t, int);
int rump___sysimpl_truncate(const char *, off_t);
int rump___sysimpl_ftruncate(int, off_t);
int rump___sysimpl___sysctl(const int *, unsigned int, void *, size_t *, const void *, _netbsd_size_t);
int rump___sysimpl_futimes(int, const struct _netbsd_timeval *);
pid_t rump___sysimpl_getpgid(pid_t);
int rump___sysimpl_reboot(int, char *);
int rump___sysimpl_poll(struct _netbsd_pollfd *, unsigned int, int);
int rump___sysimpl_fdatasync(int);
int rump___sysimpl_modctl(int, void *);
int rump___sysimpl__ksem_init(unsigned int, intptr_t *);
int rump___sysimpl__ksem_open(const char *, int, _netbsd_mode_t, unsigned int, intptr_t *);
int rump___sysimpl__ksem_unlink(const char *);
int rump___sysimpl__ksem_close(intptr_t);
int rump___sysimpl__ksem_post(intptr_t);
int rump___sysimpl__ksem_wait(intptr_t);
int rump___sysimpl__ksem_trywait(intptr_t);
int rump___sysimpl__ksem_getvalue(intptr_t, unsigned int *);
int rump___sysimpl__ksem_destroy(intptr_t);
int rump___sysimpl__ksem_timedwait(intptr_t, const struct _netbsd_timespec *);
int rump___sysimpl_lchmod(const char *, _netbsd_mode_t);
int rump___sysimpl_lchown(const char *, uid_t, gid_t);
int rump___sysimpl_lutimes(const char *, const struct _netbsd_timeval *);
pid_t rump___sysimpl_getsid(pid_t);
_netbsd_ssize_t rump___sysimpl_preadv(int, const struct _netbsd_iovec *, int, off_t);
_netbsd_ssize_t rump___sysimpl_pwritev(int, const struct _netbsd_iovec *, int, off_t);
int rump___sysimpl___getcwd(char *, _netbsd_size_t);
int rump___sysimpl_fchroot(int);
int rump___sysimpl_lchflags(const char *, unsigned long);
int rump___sysimpl_issetugid(void);
int rump___sysimpl_kqueue(void);
int rump___sysimpl_kevent(int, const struct _netbsd_kevent *, size_t, struct _netbsd_kevent *, size_t, const struct _netbsd_timespec *);
int rump___sysimpl_fsync_range(int, int, off_t, off_t);
int rump___sysimpl_getvfsstat(struct _netbsd_statvfs *, size_t, int);
int rump___sysimpl_statvfs1(const char *, struct _netbsd_statvfs *, int);
int rump___sysimpl_fstatvfs1(int, struct _netbsd_statvfs *, int);
int rump___sysimpl_extattrctl(const char *, int, const char *, int, const char *);
int rump___sysimpl_extattr_set_file(const char *, int, const char *, const void *, _netbsd_size_t);
_netbsd_ssize_t rump___sysimpl_extattr_get_file(const char *, int, const char *, void *, _netbsd_size_t);
int rump___sysimpl_extattr_delete_file(const char *, int, const char *);
int rump___sysimpl_extattr_set_fd(int, int, const char *, const void *, _netbsd_size_t);
_netbsd_ssize_t rump___sysimpl_extattr_get_fd(int, int, const char *, void *, _netbsd_size_t);
int rump___sysimpl_extattr_delete_fd(int, int, const char *);
int rump___sysimpl_extattr_set_link(const char *, int, const char *, const void *, _netbsd_size_t);
_netbsd_ssize_t rump___sysimpl_extattr_get_link(const char *, int, const char *, void *, _netbsd_size_t);
int rump___sysimpl_extattr_delete_link(const char *, int, const char *);
_netbsd_ssize_t rump___sysimpl_extattr_list_fd(int, int, void *, _netbsd_size_t);
_netbsd_ssize_t rump___sysimpl_extattr_list_file(const char *, int, void *, _netbsd_size_t);
_netbsd_ssize_t rump___sysimpl_extattr_list_link(const char *, int, void *, _netbsd_size_t);
//int rump___sysimpl_pselect50(int, _netbsd_fd_set *, _netbsd_fd_set *, _netbsd_fd_set *, const struct _netbsd_timespec *, const _netbsd_sigset_t *);
int rump___sysimpl_pollts(struct _netbsd_pollfd *, unsigned int, const struct _netbsd_timespec *, const _netbsd_sigset_t *);
int rump___sysimpl_setxattr(const char *, const char *, const void *, _netbsd_size_t, int);
int rump___sysimpl_lsetxattr(const char *, const char *, const void *, _netbsd_size_t, int);
int rump___sysimpl_fsetxattr(int, const char *, const void *, _netbsd_size_t, int);
int rump___sysimpl_getxattr(const char *, const char *, void *, _netbsd_size_t);
int rump___sysimpl_lgetxattr(const char *, const char *, void *, _netbsd_size_t);
int rump___sysimpl_fgetxattr(int, const char *, void *, _netbsd_size_t);
int rump___sysimpl_listxattr(const char *, char *, _netbsd_size_t);
int rump___sysimpl_llistxattr(const char *, char *, _netbsd_size_t);
int rump___sysimpl_flistxattr(int, char *, _netbsd_size_t);
int rump___sysimpl_removexattr(const char *, const char *);
int rump___sysimpl_lremovexattr(const char *, const char *);
int rump___sysimpl_fremovexattr(int, const char *);
int rump___sysimpl_stat50(const char *, struct stat *);
int rump___sysimpl_fstat50(int, struct stat *);
int rump___sysimpl_lstat50(const char *, struct stat *);
int rump___sysimpl_getdents30(int, char *, _netbsd_size_t);
int rump___sysimpl_socket30(int, int, int);
int rump___sysimpl_getfh30(const char *, void *, _netbsd_size_t *);
int rump___sysimpl_fhopen40(const void *, _netbsd_size_t, int);
int rump___sysimpl_fhstatvfs140(const void *, size_t, struct _netbsd_statvfs *, int);
int rump___sysimpl_fhstat50(const void *, _netbsd_size_t, struct _netbsd_stat *);
int rump___sysimpl_mount50(const char *, const char *, int, void *, _netbsd_size_t);
int rump___sysimpl_posix_fadvise50(int, off_t, off_t, int);
int rump___sysimpl_pipe2(int *, int);
int rump___sysimpl_dup3(int, int, int);
int rump___sysimpl_kqueue1(int);
int rump___sysimpl_paccept(int, struct _netbsd_sockaddr *, _netbsd_socklen_t *, const _netbsd_sigset_t *, int);
int rump___sysimpl_linkat(int, const char *, int, const char *, int);
int rump___sysimpl_renameat(int, const char *, int, const char *);
int rump___sysimpl_mkfifoat(int, const char *, _netbsd_mode_t);
int rump___sysimpl_mknodat(int, const char *, _netbsd_mode_t, uint32_t);
int rump___sysimpl_mkdirat(int, const char *, _netbsd_mode_t);
int rump___sysimpl_faccessat(int, const char *, int, int);
int rump___sysimpl_fchmodat(int, const char *, _netbsd_mode_t, int);
int rump___sysimpl_fchownat(int, const char *, uid_t, gid_t, int);
int rump___sysimpl_fexecve(int, char *const *, char *const *);
int rump___sysimpl_fstatat(int, const char *, struct _netbsd_stat *, int);
int rump___sysimpl_utimensat(int, const char *, const struct _netbsd_timespec *, int);
int rump___sysimpl_openat(int, const char *, int, ...);
int rump___sysimpl_readlinkat(int, const char *, char *, _netbsd_size_t);
int rump___sysimpl_symlinkat(const char *, int, const char *);
int rump___sysimpl_unlinkat(int, const char *, int);
int rump___sysimpl_futimens(int, const struct _netbsd_timespec *);
int rump___sysimpl___quotactl(const char *, struct _netbsd_quotactl_args *);
int rump___sysimpl_pipe(int *);
]]

