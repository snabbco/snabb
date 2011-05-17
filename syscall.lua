local ffi = require "ffi"
local bit = require "bit"

-- note should wrap more conditionals around stuff that might not be there

local S = {} -- exported functions

local octal = function (s) return tonumber(s, 8) end

-- open, fcntl
S.O_ACCMODE   = octal('0003')
S.O_RDONLY    = octal('00')
S.O_WRONLY    = octal('01')
S.O_RDWR      = octal('02')
S.O_CREAT     = octal('0100')
S.O_EXCL      = octal('0200')
S.O_NOCTTY    = octal('0400')
S.O_TRUNC     = octal('01000')
S.O_APPEND    = octal('02000')
S.O_NONBLOCK  = octal('04000')
S.O_NDELAY    = S.O_NONBLOCK
S.O_SYNC      = octal('04010000')
S.O_FSYNC     = S.O_SYNC
S.O_ASYNC     = octal('020000')
S.O_DIRECTORY = octal('0200000')
S.O_NOFOLLOW  = octal('0400000')
S.O_CLOEXEC   = octal('02000000')
S.O_DIRECT    = octal('040000')
S.O_NOATIME   = octal('01000000')
S.O_DSYNC     = octal('010000')
S.O_RSYNC     = S.O_SYNC

-- modes
S.S_IFMT   = octal('0170000') -- bit mask for the file type bit fields
S.S_IFSOCK = octal('0140000') -- socket
S.S_IFLNK  = octal('0120000') -- symbolic link
S.S_IFREG  = octal('0100000') -- regular file
S.S_IFBLK  = octal('0060000') -- block device
S.S_IFDIR  = octal('0040000') -- directory
S.S_IFCHR  = octal('0020000') -- character device
S.S_IFIFO  = octal('0010000') -- FIFO
S.S_ISUID  = octal('0004000') -- set UID bit
S.S_ISGID  = octal('0002000') -- set-group-ID bit
S.S_ISVTX  = octal('0001000') -- sticky bit

S.S_IRWXU = octal('00700') -- user (file owner) has read, write and execute permission
S.S_IRUSR = octal('00400') -- user has read permission
S.S_IWUSR = octal('00200') -- user has write permission
S.S_IXUSR = octal('00100') -- user has execute permission
S.S_IRWXG = octal('00070') -- group has read, write and execute permission
S.S_IRGRP = octal('00040') -- group has read permission
S.S_IWGRP = octal('00020') -- group has write permission
S.S_IXGRP = octal('00010') -- group has execute permission
S.S_IRWXO = octal('00007') -- others have read, write and execute permission
S.S_IROTH = octal('00004') -- others have read permission
S.S_IWOTH = octal('00002') -- others have write permission
S.S_IXOTH = octal('00001') -- others have execute permission

if ffi.abi('32bit') then S.O_LARGEFILE = octal('0100000') else S.O_LARGEFILE = 0 end -- not supported yet

-- access
S.R_OK = 4
S.W_OK = 2
S.X_OK = 1
S.F_OK = 0

--mmap
S.PROT_READ  = 0x1
S.PROT_WRITE = 0x2
S.PROT_EXEC  = 0x4
S.PROT_NONE  = 0x0
S.PROT_GROWSDOWN = 0x01000000
S.PROT_GROWSUP   = 0x02000000

-- Sharing types
S.MAP_SHARED  = 0x01
S.MAP_PRIVATE = 0x02
S.MAP_TYPE    = 0x0f
S.MAP_FIXED     = 0x10
S.MAP_FILE      = 0
S.MAP_ANONYMOUS = 0x20
S.MAP_ANON      = S.MAP_ANONYMOUS
S.MAP_32BIT     = 0x40
-- These are Linux-specific.
S.MAP_GROWSDOWN  = 0x00100
S.MAP_DENYWRITE  = 0x00800
S.MAP_EXECUTABLE = 0x01000
S.MAP_LOCKED     = 0x02000
S.MAP_NORESERVE  = 0x04000
S.MAP_POPULATE   = 0x08000
S.MAP_NONBLOCK   = 0x10000
S.MAP_STACK      = 0x20000
S.MAP_HUGETLB    = 0x40000

-- Flags to `msync'.
S.MS_ASYNC       = 1
S.MS_SYNC        = 4
S.MS_INVALIDATE  = 2

-- Flags for `mlockall'.
S.MCL_CURRENT    = 1
S.MCL_FUTURE     = 2

-- Flags for `mremap'.
S.MREMAP_MAYMOVE = 1
S.MREMAP_FIXED   = 2

-- sockets -- linux has flags against this, so provided as enum and constants
S.SOCK_STREAM    = 1
S.SOCK_DGRAM     = 2
S.SOCK_RAW       = 3
S.SOCK_RDM       = 4
S.SOCK_SEQPACKET = 5
S.SOCK_DCCP      = 6
S.SOCK_PACKET    = 10

S.SOCK_CLOEXEC = octal('02000000') -- flag
S.SOCK_NONBLOCK = octal('04000')   -- flag

-- misc socket constants -- move to enum??
S.SOL_RAW        = 255
S.SOL_DECNET     = 261
S.SOL_X25        = 262
S.SOL_PACKET     = 263
S.SOL_ATM        = 264
S.SOL_AAL        = 265
S.SOL_IRDA       = 266

-- Maximum queue length specifiable by listen.
S.SOMAXCONN = 128

-- waitpid 3rd arg
S.WNOHANG       = 1
S.WUNTRACED     = 2

--waitid 4th arg
S.WSTOPPED      = 2
S.WEXITED       = 4
S.WCONTINUED    = 8
S.WNOWAIT       = 0x01000000

-- send, recv etc
S.MSG_OOB             = 0x01
S.MSG_PEEK            = 0x02
S.MSG_DONTROUTE       = 0x04
S.MSG_TRYHARD         = MSG_DONTROUTE
S.MSG_CTRUNC          = 0x08
S.MSG_PROXY           = 0x10
S.MSG_TRUNC           = 0x20
S.MSG_DONTWAIT        = 0x40
S.MSG_EOR             = 0x80
S.MSG_WAITALL         = 0x100
S.MSG_FIN             = 0x200
S.MSG_SYN             = 0x400
S.MSG_CONFIRM         = 0x800
S.MSG_RST             = 0x1000
S.MSG_ERRQUEUE        = 0x2000
S.MSG_NOSIGNAL        = 0x4000
S.MSG_MORE            = 0x8000
S.MSG_WAITFORONE      = 0x10000
S.MSG_CMSG_CLOEXEC    = 0x40000000

-- constants
local HOST_NAME_MAX = 64 -- Linux. should we export?

-- misc
function S.nogc(d) ffi.gc(d, nil) end
local errorret, retint, retbool, retptr, retfd, getfd

function S.strerror(errno) return ffi.string(ffi.C.strerror(errno)), errno end

-- standard error return
function errorret()
  return nil, S.strerror(ffi.errno())
end

function retint(ret)
  if ret == -1 then
    return errorret()
  end
  return ret
end

-- used for no return value, return true for use of assert
function retbool(ret)
  if ret == -1 then
    return errorret()
  end
  return true
end

-- used for pointer returns, -1 is failure, optional gc function
function retptr(ret, f)
  if ffi.cast("long", ret) == -1 then
     return errorret()
  end
  if f then return ffi.gc(ret, f) end
  return ret
end

local fd_t -- type for a file descriptor

-- char buffer type
local buffer_t = ffi.typeof("char[?]")

S.string = ffi.string -- convenience for converting buffers
S.sizeof = ffi.sizeof -- convenience so user need not require ffi
S.cast = ffi.cast -- convenience so user need not require ffi

--get fd from standard string, integer, or cdata
function getfd(fd)
  if type(fd) == 'number' then return fd end
  if ffi.istype(fd_t, fd) then return fd.fd end
  if type(fd) == 'string' then
    if fd == 'stdin' or fd == 'STDIN_FILENO' then return 0 end
    if fd == 'stdout' or fd == 'STDOUT_FILENO' then return 1 end
    if fd == 'stderr' or fd == 'STDERR_FILENO' then return 2 end
  end
end

function retfd(ret)
  if ret == -1 then return errorret() end
  return fd_t(ret)
end

-- define C types
ffi.cdef[[
// typedefs for word size independent types

// 16 bit
typedef uint16_t in_port_t;

// 32 bit
typedef uint32_t mode_t;
typedef uint32_t uid_t;
typedef uint32_t gid_t;
typedef uint32_t socklen_t;
typedef int32_t pid_t;

// 64 bit
typedef uint64_t dev_t;

// posix standards
typedef unsigned short int sa_family_t;

// typedefs which are word length
typedef unsigned long size_t;
typedef long ssize_t;
typedef long off_t;
typedef long time_t;
typedef unsigned long ino_t;
typedef unsigned long nlink_t;
typedef long blksize_t;
typedef long blkcnt_t;

// misc
typedef void (*sighandler_t) (int);

// structs
struct timeval {
  long    tv_sec;         /* seconds */
  long    tv_usec;        /* microseconds */
};
struct timespec {
  time_t tv_sec;        /* seconds */
  long   tv_nsec;       /* nanoseconds */
};
// for uname. may well differ by OS
struct utsname {
  char sysname[65];
  char nodename[65];
  char release[65];
  char version[65];
  char machine[65];
  char domainname[65];
};
struct iovec {
  void *iov_base;
  size_t iov_len;
};
struct msghdr {
  void *msg_name;
  socklen_t msg_namelen;
  struct iovec *msg_iov;
  size_t msg_iovlen;
  void *msg_control;
  size_t msg_controllen;
  int msg_flags;
};
struct sockaddr {
  sa_family_t sa_family;
  char sa_data[14];
};
// ipv4 sockets
struct in_addr {
  uint32_t       s_addr;
};
struct sockaddr_in {
  sa_family_t    sin_family;  /* address family: AF_INET */
  in_port_t      sin_port;    /* port in network byte order */
  struct in_addr sin_addr;    /* internet address */
  unsigned char  sin_zero[8]; /* padding, should not vary by arch */
};
struct sockaddr_un {
  sa_family_t sun_family;     /* AF_UNIX */
  char        sun_path[108];  /* pathname */
};

// enums, LuaJIT will allow strings to be used, so we provide for appropriate parameters
enum SEEK {
  SEEK_SET,
  SEEK_CUR,
  SEEK_END
};
enum EXIT {
  EXIT_SUCCESS,
  EXIT_FAILURE
};
enum F {
  F_DUPFD       = 0,
  F_GETFD       = 1,
  F_SETFD       = 2,
  F_GETFL       = 3,
  F_SETFL       = 4,
  F_GETLK       = 5,
  F_SETLK       = 6,
  F_SETLKW      = 7,
  F_SETOWN      = 8,
  F_GETOWN      = 9,
  F_SETSIG      = 10,
  F_GETSIG      = 11,
//F_GETLK64     = 12,      -- 64 on 32 file ops still TODO
//F_SETLK64     = 13,      -- 64 on 32 file ops still TODO
//F_SETLKW64    = 14,      -- 64 on 32 file ops still TODO
  F_SETOWN_EX   = 15,
  F_GETOWN_EX   = 16,
  F_SETLEASE    = 1024,
  F_GETLEASE    = 1025,
  F_NOTIFY      = 1026,
  F_SETPIPE_SZ  = 1031,
  F_GETPIPE_SZ  = 1032,
  F_DUPFD_CLOEXEC = 1030
};
enum MADV {
  MADV_NORMAL      = 0,
  MADV_RANDOM      = 1,
  MADV_SEQUENTIAL  = 2,
  MADV_WILLNEED    = 3,
  MADV_DONTNEED    = 4,
  MADV_REMOVE      = 9,
  MADV_DONTFORK    = 10,
  MADV_DOFORK      = 11,
  MADV_MERGEABLE   = 12,
  MADV_UNMERGEABLE = 13,
  MADV_HUGEPAGE    = 14,
  MADV_NOHUGEPAGE  = 15,
  MADV_HWPOISON    = 100,
  // POSIX madvise names
  POSIX_MADV_NORMAL      = 0,
  POSIX_MADV_RANDOM      = 1,
  POSIX_MADV_SEQUENTIAL  = 2,
  POSIX_MADV_WILLNEED    = 3,
  POSIX_MADV_DONTNEED    = 4,
};
enum SIG_ { /* maybe not te clearest name */
  SIG_ERR = -1,
  SIG_DFL =  0,
  SIG_IGN =  1,
  SIG_HOLD = 2,
};
enum SIG {
  SIGHUP        = 1,
  SIGINT        = 2,
  SIGQUIT       = 3,
  SIGILL        = 4,
  SIGTRAP       = 5,
  SIGABRT       = 6,
  SIGIOT        = 6,
  SIGBUS        = 7,
  SIGFPE        = 8,
  SIGKILL       = 9,
  SIGUSR1       = 10,
  SIGSEGV       = 11,
  SIGUSR2       = 12,
  SIGPIPE       = 13,
  SIGALRM       = 14,
  SIGTERM       = 15,
  SIGSTKFLT     = 16,
  SIGCHLD       = 17,
  SIGCLD        = SIGCHLD,
  SIGCONT       = 18,
  SIGSTOP       = 19,
  SIGTSTP       = 20,
  SIGTTIN       = 21,
  SIGTTOU       = 22,
  SIGURG        = 23,
  SIGXCPU       = 24,
  SIGXFSZ       = 25,
  SIGVTALRM     = 26,
  SIGPROF       = 27,
  SIGWINCH      = 28,
  SIGIO         = 29,
  SIGPOLL       = SIGIO,
  SIGPWR        = 30,
  SIGSYS        = 31,
  SIGUNUSED     = 31
};
enum SCM {
  SCM_RIGHTS = 0x01,
  SCM_CREDENTIALS = 0x02
};
enum SOCK {
  SOCK_STREAM    = 1,
  SOCK_DGRAM     = 2,
  SOCK_RAW       = 3,
  SOCK_RDM       = 4,
  SOCK_SEQPACKET = 5,
  SOCK_DCCP      = 6,
  SOCK_PACKET    = 10,
};
enum AF {
  AF_UNSPEC     = 0,
  AF_LOCAL      = 1,
  AF_UNIX       = AF_LOCAL,
  AF_FILE       = AF_LOCAL,
  AF_INET       = 2,
  AF_AX25       = 3,
  AF_IPX        = 4,
  AF_APPLETALK  = 5,
  AF_NETROM     = 6,
  AF_BRIDGE     = 7,
  AF_ATMPVC     = 8,
  AF_X25        = 9,
  AF_INET6      = 10,
  AF_ROSE       = 11,
  AF_DECnet     = 12,
  AF_NETBEUI    = 13,
  AF_SECURITY   = 14,
  AF_KEY        = 15,
  AF_NETLINK    = 16,
  AF_ROUTE      = AF_NETLINK,
  AF_PACKET     = 17,
  AF_ASH        = 18,
  AF_ECONET     = 19,
  AF_ATMSVC     = 20,
  AF_RDS        = 21,
  AF_SNA        = 22,
  AF_IRDA       = 23,
  AF_PPPOX      = 24,
  AF_WANPIPE    = 25,
  AF_LLC        = 26,
  AF_CAN        = 29,
  AF_TIPC       = 30,
  AF_BLUETOOTH  = 31,
  AF_IUCV       = 32,
  AF_RXRPC      = 33,
  AF_ISDN       = 34,
  AF_PHONET     = 35,
  AF_IEEE802154 = 36,
  AF_CAIF       = 37,
  AF_ALG        = 38,
  AF_MAX        = 39,
};

enum E {
  EPERM          =  1,
  ENOENT         =  2,
  ESRCH          =  3,
  EINTR          =  4,
  EIO            =  5,
  ENXIO          =  6,
  E2BIG          =  7,
  ENOEXEC        =  8,
  EBADF          =  9,
  ECHILD         = 10,
  EAGAIN         = 11,
  ENOMEM         = 12,
  EACCES         = 13,
  EFAULT         = 14,
  ENOTBLK        = 15,
  EBUSY          = 16,
  EEXIST         = 17,
  EXDEV          = 18,
  ENODEV         = 19,
  ENOTDIR        = 20,
  EISDIR         = 21,
  EINVAL         = 22,
  ENFILE         = 23,
  EMFILE         = 24,
  ENOTTY         = 25,
  ETXTBSY        = 26,
  EFBIG          = 27,
  ENOSPC         = 28,
  ESPIPE         = 29,
  EROFS          = 30,
  EMLINK         = 31,
  EPIPE          = 32,
  EDOM           = 33,
  ERANGE         = 34,
  EDEADLK        = 35,
  ENAMETOOLONG   = 36,
  ENOLCK         = 37,
  ENOSYS         = 38,
  ENOTEMPTY      = 39,
  ELOOP          = 40,
  EWOULDBLOCK    = EAGAIN,
  ENOMSG         = 42,
  EIDRM          = 43,
  ECHRNG         = 44,
  EL2NSYNC       = 45,
  EL3HLT         = 46,
  EL3RST         = 47,
  ELNRNG         = 48,
  EUNATCH        = 49,
  ENOCSI         = 50,
  EL2HLT         = 51,
  EBADE          = 52,
  EBADR          = 53,
  EXFULL         = 54,
  ENOANO         = 55,
  EBADRQC        = 56,
  EBADSLT        = 57,
  EDEADLOCK      = EDEADLK,
  EBFONT         = 59,
  ENOSTR         = 60,
  ENODATA        = 61,
  ETIME          = 62,
  ENOSR          = 63,
  ENONET         = 64,
  ENOPKG         = 65,
  EREMOTE        = 66,
  ENOLINK        = 67,
  EADV           = 68,
  ESRMNT         = 69,
  ECOMM          = 70,
  EPROTO         = 71,
  EMULTIHOP      = 72,
  EDOTDOT        = 73,
  EBADMSG        = 74,
  EOVERFLOW      = 75,
  ENOTUNIQ       = 76,
  EBADFD         = 77,
  EREMCHG        = 78,
  ELIBACC        = 79,
  ELIBBAD        = 80,
  ELIBSCN        = 81,
  ELIBMAX        = 82,
  ELIBEXEC       = 83,
  EILSEQ         = 84,
  ERESTART       = 85,
  ESTRPIPE       = 86,
  EUSERS         = 87,
  ENOTSOCK       = 88,
  EDESTADDRREQ   = 89,
  EMSGSIZE       = 90,
  EPROTOTYPE     = 91,
  ENOPROTOOPT    = 92,
  EPROTONOSUPPORT= 93,
  ESOCKTNOSUPPORT= 94,
  EOPNOTSUPP     = 95,
  EPFNOSUPPORT   = 96,
  EAFNOSUPPORT   = 97,
  EADDRINUSE     = 98,
  EADDRNOTAVAIL  = 99,
  ENETDOWN       = 100,
  ENETUNREACH    = 101,
  ENETRESET      = 102,
  ECONNABORTED   = 103,
  ECONNRESET     = 104,
  ENOBUFS        = 105,
  EISCONN        = 106,
  ENOTCONN       = 107,
  ESHUTDOWN      = 108,
  ETOOMANYREFS   = 109,
  ETIMEDOUT      = 110,
  ECONNREFUSED   = 111,
  EHOSTDOWN      = 112,
  EHOSTUNREACH   = 113,
  EINPROGRESS    = 115,
  ESTALE         = 116,
  EUCLEAN        = 117,
  ENOTNAM        = 118,
  ENAVAIL        = 119,
  EISNAM         = 120,
  EREMOTEIO      = 121,
  EDQUOT         = 122,
  ENOMEDIUM      = 123,
  EMEDIUMTYPE    = 124,
  ECANCELED      = 125,
  ENOKEY         = 126,
  EKEYEXPIRED    = 127,
  EKEYREVOKED    = 128,
  EKEYREJECTED   = 129,
  EOWNERDEAD     = 130,
  ENOTRECOVERABLE= 131,
  ERFKILL        = 132,
};
]]

-- stat structure is architecture dependent in Linux
-- also sockaddr_storage (just about), due to way it forces alignment
-- this is the way glibc versions stat via __xstat, may need to change for other libc, eg if define stat as a non inline function
local STAT_VER_LINUX

if ffi.abi("32bit") then
STAT_VER_LINUX = 3
ffi.cdef[[
struct stat {
  dev_t st_dev;
  unsigned short int __pad1;
  ino_t __st_ino;
  mode_t st_mode;
  nlink_t st_nlink;
  uid_t st_uid;
  gid_t st_gid;
  dev_t st_rdev;
  unsigned short int __pad2;
  off_t st_size;
  blksize_t st_blksize;
  blkcnt_t st_blocks;
  struct timespec st_atim;
  struct timespec st_mtim;
  struct timespec st_ctim;
  unsigned long int __unused4;
  unsigned long int __unused5;
};
struct sockaddr_storage {
  sa_family_t ss_family;
  unsigned long int __ss_align;
  char __ss_padding[120];
};
]]
else -- 64 bit arch
STAT_VER_LINUX = 1
ffi.cdef[[
struct stat {
  dev_t st_dev;
  ino_t st_ino;
  nlink_t st_nlink;
  mode_t st_mode;
  uid_t st_uid;
  gid_t st_gid;
  int __pad0;
  dev_t st_rdev;
  off_t st_size;
  blksize_t st_blksize;
  blkcnt_t st_blocks;
  struct timespec st_atim;
  struct timespec st_mtim;
  struct timespec st_ctim;
  long int __unused[3];
};
struct sockaddr_storage {
  sa_family_t ss_family;
  unsigned long int __ss_align;
  char __ss_padding[112];
};
]]
end

ffi.cdef[[
int close(int fd);
int open(const char *pathname, int flags, mode_t mode);
int creat(const char *pathname, mode_t mode);
int chdir(const char *path);
int mkdir(const char *pathname, mode_t mode);
int rmdir(const char *pathname);
int unlink(const char *pathname);
int acct(const char *filename);
int chmod(const char *path, mode_t mode);
int link(const char *oldpath, const char *newpath);
mode_t umask(mode_t mask);
int uname(struct utsname *buf);
int gethostname(char *name, size_t len);
int sethostname(const char *name, size_t len);
uid_t getuid(void);
uid_t geteuid(void);
pid_t getpid(void);
pid_t getppid(void);
pid_t fork(void);
int execve(const char *filename, const char *argv[], const char *envp[]);
pid_t wait(int *status);
pid_t waitpid(pid_t pid, int *status, int options);
void _exit(enum EXIT status);
enum SIG_ signal(enum SIG signum, enum SIG_ handler); /* although deprecated, just using to set SIG_ values */

ssize_t read(int fd, void *buf, size_t count);
ssize_t write(int fd, const void *buf, size_t count);
ssize_t pread(int fd, void *buf, size_t count, off_t offset);
ssize_t pwrite(int fd, const void *buf, size_t count, off_t offset);
off_t lseek(int fd, off_t offset, enum SEEK whence); 
ssize_t send(int sockfd, const void *buf, size_t len, int flags);
ssize_t sendto(int sockfd, const void *buf, size_t len, int flags, const struct sockaddr *dest_addr, socklen_t addrlen);
ssize_t sendmsg(int sockfd, const struct msghdr *msg, int flags);
ssize_t recv(int sockfd, void *buf, size_t len, int flags);
ssize_t recvfrom(int sockfd, void *buf, size_t len, int flags, struct sockaddr *src_addr, socklen_t *addrlen);
ssize_t recvmsg(int sockfd, struct msghdr *msg, int flags);
ssize_t readv(int fd, const struct iovec *iov, int iovcnt);
ssize_t writev(int fd, const struct iovec *iov, int iovcnt);

int dup(int oldfd);
int dup2(int oldfd, int newfd);
int dup3(int oldfd, int newfd, int flags);
int fchdir(int fd);
int fsync(int fd);
int fdatasync(int fd);
int fcntl(int fd, enum F cmd, long arg); /* arg can be a pointer though */
int fchmod(int fd, mode_t mode);

int socket(enum AF domain, enum SOCK type, int protocol);
int socketpair(enum AF domain, enum SOCK type, int protocol, int sv[2]);
int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
int listen(int sockfd, int backlog);
int connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
int accept(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
int accept4(int sockfd, struct sockaddr *addr, socklen_t *addrlen, int flags);
int getsockname(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
int getpeername(int sockfd, struct sockaddr *addr, socklen_t *addrlen);

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);
int munmap(void *addr, size_t length);
int msync(void *addr, size_t length, int flags);
int mlock(const void *addr, size_t len);
int munlock(const void *addr, size_t len);
int mlockall(int flags);
int munlockall(void);
void *mremap(void *old_address, size_t old_size, size_t new_size, int flags, void *new_address);
int madvise(void *addr, size_t length, enum MADV advice);

int pipe2(int pipefd[2], int flags);

int unlink(const char *pathname);
int access(const char *pathname, int mode);
char *getcwd(char *buf, size_t size);

int nanosleep(const struct timespec *req, struct timespec *rem);

// stat glibc internal functions
int __fxstat(int ver, int fd, struct stat *buf);
int __xstat(int ver, const char *path, struct stat *buf);
int __lxstat(int ver, const char *path, struct stat *buf);
int gnu_dev_major(dev_t dev);
int gnu_dev_minor(dev_t dev);


// functions from libc ie man 3 not man 2
void exit(enum EXIT status);
int inet_aton(const char *cp, struct in_addr *inp);
char *inet_ntoa(struct in_addr in);

// functions from libc that could be exported as a convenience, used internally
void *calloc(size_t nmemb, size_t size);
void *malloc(size_t size);
void free(void *ptr);
void *realloc(void *ptr, size_t size);
char *strerror(enum E errnum);
]]

-- Lua type constructors corresponding to defined types
local timespec_t = ffi.typeof("struct timespec")
local stat_t = ffi.typeof("struct stat")
local sockaddr_t = ffi.typeof("struct sockaddr")
local sockaddr_storage_t = ffi.typeof("struct sockaddr_storage")
local sa_family_t = ffi.typeof("sa_family_t")
local sockaddr_in_t = ffi.typeof("struct sockaddr_in")
local in_addr_t = ffi.typeof("struct in_addr")
local sockaddr_un_t = ffi.typeof("struct sockaddr_un")
local iovec_t = ffi.typeof("struct iovec[?]")
local msghdr_t = ffi.typeof("struct msghdr")
local int1_t = ffi.typeof("int[1]") -- used to pass pointer to int
local int2_t = ffi.typeof("int[2]") -- pair of ints, eg for pipe
local enumAF_t = ffi.typeof("enum AF") -- used for converting enum
local enumE_t = ffi.typeof("enum E") -- used for converting error names
local string_array_t = ffi.typeof("const char *[?]")
-- need these for casts
local sockaddr_pt = ffi.typeof("struct sockaddr *")

assert(ffi.sizeof(sockaddr_t) == ffi.sizeof(sockaddr_in_t)) -- inet socket addresses should be padded to same as sockaddr
assert(ffi.sizeof(sockaddr_storage_t) == 128) -- this is the required size
assert(ffi.sizeof(sockaddr_storage_t) >= ffi.sizeof(sockaddr_t))
assert(ffi.sizeof(sockaddr_storage_t) >= ffi.sizeof(sockaddr_in_t))
assert(ffi.sizeof(sockaddr_storage_t) >= ffi.sizeof(sockaddr_un_t))

-- endian conversion
if ffi.abi("be") then -- nothing to do
  function S.htonl(b) return b end
else
  function S.htonl(b)
  if ffi.istype(in_addr_t, b) then return in_addr_t(bit.bswap(b.s_addr)) end -- not sure we need this, actually not using this function
  return bit.bswap(b)
end
  function S.htons(b) return bit.rshift(bit.bswap(b), 16) end
end
S.ntohl = S.htonl -- reverse is the same
S.ntohs = S.htons -- reverse is the same

-- initialisers
-- need to set first field. Corrects byte order on port, constructor for addr will do that for addr.
function S.sockaddr_in(port, addr)
  if type(addr) == 'string' then addr = S.inet_aton(addr) end
  if not addr then return nil end
  return sockaddr_in_t(enumAF_t("AF_INET"), S.htons(port), addr)
end

local n = function(s) return tonumber(enumAF_t(s)) end -- convert to Lua number, as tables indexed by number

-- map from socket family to data type
local socket_type = {}
-- AF_UNSPEC
socket_type[n("AF_LOCAL")] = sockaddr_un_t
socket_type[n("AF_INET")] = sockaddr_in_t
--  AF_AX25
--  AF_IPX
--  AF_APPLETALK
--  AF_NETROM
--  AF_BRIDGE
--  AF_ATMPVC
--  AF_X25
--  AF_INET6
--  AF_ROSE
--  AF_DECnet
--  AF_NETBEUI
--  AF_SECURITY
--  AF_KEY
--  AF_NETLINK
--  AF_PACKET
--  AF_ASH
--  AF_ECONET
--  AF_ATMSVC
--  AF_RDS
--  AF_SNA
--  AF_IRDA
--  AF_PPPOX
--  AF_WANPIPE
--  AF_LLC
--  AF_CAN
--  AF_TIPC
--  AF_BLUETOOTH
--  AF_IUCV
--  AF_RXRPC
--  AF_ISDN
--  AF_PHONET
--  AF_IEEE802154
--  AF_CAIF
--  AF_ALG
--  AF_MAX

-- convert error symbolic name to errno
function S.errno(name) return tonumber(enumE_t(name)) end

-- helper function to make setting addrlen optional
local getaddrlen
function getaddrlen(addr, addrlen)
  if not addr then return 0 end
  if addrlen == nil then
    if ffi.istype(sockaddr_t, addr) then return ffi.sizeof(sockaddr_t) end
    if ffi.istype(sockaddr_in_t, addr) then return ffi.sizeof(sockaddr_in_t) end
  end
  return addrlen or 0
end

-- helper function for returning socket address types
local saret
saret = function(ss, addrlen, rets) -- return socket address structure, additional values to return in rets
  if ret == -1 then return errorret() end
  if not rets then rets = {} end
  local afamily = tonumber(ss.ss_family)
  rets.addrlen = addrlen
  rets.sa_family = afamily
  rets.ss = ss
  local atype = socket_type[afamily]
  if atype then
    local addr = atype()
    ffi.copy(addr, ss, addrlen) -- note we copy rather than cast so it is safe for ss to be garbage collected.
    rets.addr = addr
    -- helpers to make it easier to get peer info
    if ffi.istype(sockaddr_un_t, addr) then
      local namelen = addrlen - ffi.sizeof(sa_family_t)
      if namelen > 0 then
        rets.name = ffi.string(addr.sun_path, namelen)
        if addr.sun_path[0] == 0 then rets.abstract = true end -- Linux only
      end
    elseif ffi.istype(sockaddr_in_t, addr) then
      rets.port = S.ntohs(addr.sin_port)
      rets.ipv4 = addr.sin_addr
    end
  end
  return rets
end

-- functions from section 3 that we use for ip addresses
function S.inet_aton(s)
  local addr = in_addr_t()
  local ret = ffi.C.inet_aton(s, addr)
  if ret == 0 then return nil end
  return addr
end

function S.inet_ntoa(addr) return ffi.string(ffi.C.inet_ntoa(addr)) end

-- constants
S.INADDR_ANY = in_addr_t()
S.INADDR_LOOPBACK = assert(S.inet_aton("127.0.0.1"))
S.INADDR_BROADCAST = assert(S.inet_aton("255.255.255.255"))

-- main definitions start here
function S.open(pathname, flags, mode) return retfd(ffi.C.open(pathname, flags or 0, mode or 0)) end

function S.dup(oldfd, newfd, flags)
  if newfd == nil then return retfd(ffi.C.dup(getfd(oldfd))) end
  if flags == nil then return retfd(ffi.C.dup2(getfd(oldfd), getfd(newfd))) end
  return retfd(ffi.C.dup3(getfd(oldfd), getfd(newfd), flags))
end
S.dup2 = S.dup
S.dup3 = S.dup

function S.pipe(flags)
  local fd2 = int2_t()
  local ret = ffi.C.pipe2(fd2, flags or 0)
  if ret == -1 then
    return errorret()
  end
  return {fd_t(fd2[0]), fd_t(fd2[1])}
end
S.pipe2 = S.pipe

function S.close(fd)
  local ret = ffi.C.close(getfd(fd))
  if ret == -1 then return errorret() end
  if ffi.istype(fd_t, fd) then
    ffi.gc(fd, nil) -- remove gc finalizer as now closed; should we also remove if get EBADF?
  end
  return true
end

function S.creat(pathname, mode) return retfd(ffi.C.creat(pathname, mode or 0)) end
function S.unlink(pathname) return retbool(ffi.C.unlink(pathname)) end
function S.access(pathname, mode) return retbool(ffi.C.access(pathname, mode)) end
function S.chdir(path) return retbool(ffi.C.chdir(path)) end
function S.mkdir(path, mode) return retbool(ffi.C.mkdir(path, mode)) end
function S.rmdir(path) return retbool(ffi.C.rmdir(path)) end
function S.unlink(pathname) return retbool(ffi.C.unlink(pathname)) end
function S.acct(filename) return retbool(ffi.C.acct(filename)) end
function S.chmod(path, mode) return retbool(ffi.C.chmod(path, mode)) end
function S.link(oldpath, newpath) return retbool(ffi.C.link(oldpath, newpath)) end

function S.fork() return retint(ffi.C.fork()) end
function S.execve(filename, argv, envp)
  local cargv = string_array_t(#argv + 1, argv)
  cargv[#argv] = nil -- not entirely clear why not initialised to zero
  local cenvp = string_array_t(#envp + 1, envp)
  cenvp[#envp] = nil
  return retbool(ffi.C.execve(filename, cargv, cenvp))
end

-- cleanup wait, waitpid to return one value, but need to work out what exactly...
function S.wait() -- we always get and return the status value, need to add helpers
  local status = int1_t()
  local ret = ffi.C.wait(status)
  if ret == -1 then return nil, errorret() end -- extra padding where we would return status
  return ret, status[0]
end
function S.waitpid(pid, options) -- we always get and return the status value, need to add helpers
  local status = int1_t()
  local ret = ffi.C.waitpid(pid, status, options or 0)
  if ret == -1 then return nil, errorret() end -- extra padding where we would return status
  return ret, status[0]
end

function S._exit(status) ffi.C._exit(status or 0) end
function S.exit(status) ffi.C.exit(status or 0) end

function S.read(fd, buf, count) return retint(ffi.C.read(getfd(fd), buf, count)) end
function S.write(fd, buf, count) return retint(ffi.C.write(getfd(fd), buf, count or #buf)) end
function S.pread(fd, buf, count, offset) return retint(ffi.C.pread(getfd(fd), buf, count, offset)) end
function S.pwrite(fd, buf, count, offset) return retint(ffi.C.pwrite(getfd(fd), buf, count, offset)) end
function S.lseek(fd, offset, whence) return retint(ffi.C.lseek(getfd(fd), offset, whence)) end
function S.send(fd, buf, count, flags) return retint(ffi.C.send(getfd(fd), buf, count or #buf, flags or 0)) end
function S.sendto(fd, buf, count, flags, addr, addrlen)
  return retint(ffi.C.sendto(getfd(fd), buf, count or #buf, flags or 0, ffi.cast(sockaddr_pt, addr), getaddrlen(addr)))
end
function S.readv(fd, iov, iovcnt) return retint(ffi.C.readv(getfd(fd), iov, iovcnt)) end
function S.writev(fd, iov, iovcnt) return retint(ffi.C.writev(getfd(fd), iov, iovcnt)) end

function S.recv(fd, buf, count, flags) return retint(ffi.C.recv(getfd(fd), buf, count or #buf, flags or 0)) end
function S.recvfrom(fd, buf, count, flags)
  local ss = sockaddr_storage_t()
  local addrlen = int1_t(ffi.sizeof(sockaddr_storage_t))
  local ret = ffi.C.recvfrom(getfd(fd), buf, count, flags or 0, ffi.cast(sockaddr_pt, ss), addrlen)
  if ret == -1 then return errorret() end
  return saret(ss, addrlen[0], {count = ret})
end

function S.fchdir(fd) return retbool(ffi.C.fchdir(getfd(fd))) end
function S.fsync(fd) return retbool(ffi.C.fsync(getfd(fd))) end
function S.fdatasync(fd) return retbool(ffi.C.fdatasync(getfd(fd))) end
function S.fchmod(fd, mode) return retbool(ffi.C.fchmod(getfd(fd), mode)) end

function S.stat(path)
  local buf = stat_t()
  local ret = ffi.C.__xstat(STAT_VER_LINUX, path, buf)
  if ret == -1 then return errorret() end
  return buf
end
function S.lstat(path)
  local buf = stat_t()
  local ret = ffi.C.__lxstat(STAT_VER_LINUX, path, buf)
  if ret == -1 then return errorret() end
  return buf
end
function S.fstat(fd)
  local buf = stat_t()
  local ret = ffi.C.__fxstat(STAT_VER_LINUX, getfd(fd), buf)
  if ret == -1 then return errorret() end
  return buf
end

function S.getcwd(buf, size)
  local ret = ffi.C.getcwd(buf, size or 0)
  if not buf then -- Linux will allocate buffer here, return Lua string and free
    if ret == nil then return errorret() end
    local s = ffi.string(ret) -- guaranteed to be zero terminated if no error
    ffi.C.free(ret)
    return s
  end
  -- user allocated buffer
  if ret == nil then return errorret() end
  return true -- no point returning the pointer as it is just the passed buffer
end

function S.nanosleep(req)
  local rem = timespec_t()
  local ret = ffi.C.nanosleep(req, rem)
  if ret == -1 then return errorret() end
  return rem -- return second argument, Lua style
end

function S.mmap(addr, length, prot, flags, fd, offset)
  return retptr(ffi.C.mmap(addr, length, prot, flags, getfd(fd), offset), function(addr) ffi.C.munmap(addr, length) end) -- add munmap gc
end
function S.munmap(addr, length)
  return retbool(ffi.C.munmap(ffi.gc(addr, nil), length)) -- remove gc on unmap
end
function S.msync(addr, length, flags) return retbool(ffi.C.msync(addr, length, flags)) end
function S.mlock(addr, len) return retbool(ffi.C.mlock(addr, len)) end
function S.munlock(addr, len) return retbool(ffi.C.munlock(addr, len)) end
function S.mlockall(flags) return retbool(ffi.C.mlockall(flags)) end
function S.munlockall() return retbool(ffi.C.munlockall()) end
function S.mremap(old_address, old_size, new_size, flags, new_address) return retptr(ffi.C.mremap(old_address, old_size, new_size, flags, new_address)) end
function S.madvise(addr, length, advice) return retbool(ffi.C.madvise(addr, length, advice)) end

function S.socket(domain, stype, protocol) return retfd(ffi.C.socket(domain, stype, protocol or 0)) end
function S.socketpair(domain, stype, protocol)
  local sv2 = int2_t()
  local ret = ffi.C.socketpair(domain, stype, protocol or 0, sv2)
  if ret == -1 then return errorret() end
  return {fd_t(sv2[0]), fd_t(sv2[1])}
end

function S.bind(sockfd, addr, addrlen)
  return retbool(ffi.C.bind(getfd(sockfd), ffi.cast(sockaddr_pt, addr), getaddrlen(addr, addrlen)))
end

function S.listen(sockfd, backlog) return retbool(ffi.C.listen(getfd(sockfd), backlog or 0)) end
function S.connect(sockfd, addr, addrlen)
  return retbool(ffi.C.connect(getfd(sockfd), ffi.cast(sockaddr_pt, addr), getaddrlen(addr, addrlen)))
end

function S.accept(sockfd)
  local ss = sockaddr_storage_t()
  local addrlen = int1_t(ffi.sizeof(sockaddr_storage_t))
  local ret = ffi.C.accept(getfd(sockfd), ffi.cast(sockaddr_pt, ss), addrlen)
  if ret == -1 then return errorret() end
  return saret(ss, addrlen[0], {fd = fd_t(ret)})
end
--S.accept4 = S.accept -- need to add support for flags argument TODO

function S.getsockname(sockfd)
  local ss = sockaddr_storage_t()
  local addrlen = int1_t(ffi.sizeof(sockaddr_storage_t))
  local ret = ffi.C.getsockname(getfd(sockfd), ffi.cast(sockaddr_pt, ss), addrlen)
  if ret == -1 then return errorret() end
  return saret(ss, addrlen[0])
end

function S.getpeername(sockfd)
  local ss = sockaddr_storage_t()
  local addrlen = int1_t(ffi.sizeof(sockaddr_storage_t))
  local ret = ffi.C.getpeername(getfd(sockfd), ffi.cast(sockaddr_pt, ss), addrlen)
  if ret == -1 then return errorret() end
  return saret(ss, addrlen[0])
end

function S.fcntl(fd, cmd, arg)
  -- some uses have arg as a pointer, need handling TODO
  local ret = ffi.C.fcntl(getfd(fd), cmd, arg or 0)
  -- return values differ, some special handling needed
  if cmd == "F_DUPFD" or cmd == "F_DUPFD_CLOEXEC" then return retfd(ret) end
  if cmd == "F_GETFD" or cmd == "F_GETFL" or cmd == "F_GETLEASE" or cmd == "F_GETOWN" or cmd == "F_GETSIG" or cmd == "F_GETPIPE_SZ" then return retint(ret) end
  return retbool(ret)
end

local utsname_t = ffi.typeof("struct utsname")
function S.uname()
  local u = utsname_t()
  local ret = ffi.C.uname(u)
  if ret == -1 then return errorret() end
  return {sysname = ffi.string(u.sysname), nodename = ffi.string(u.nodename), release = ffi.string(u.release),
          version = ffi.string(u.version), machine = ffi.string(u.machine), domainname = ffi.string(u.domainname)}
end

function S.gethostname()
  local buf = buffer_t(HOST_NAME_MAX + 1)
  local ret = ffi.C.gethostname(buf, HOST_NAME_MAX + 1)
  if ret == -1 then return errorret() end
  buf[HOST_NAME_MAX] = 0 -- paranoia here to make sure null terminated, which could happen if HOST_NAME_MAX was incorrect
  return ffi.string(buf)
end

function S.sethostname(s) -- only accept Lua string, do not see use case for buffer as well
  return retbool(ffi.C.sethostname(s, #s))
end

function S.signal(signum, handler) return retbool(ffi.C.signal(signum, handler)) end

-- straight passthroughs, as no failure possible
S.getuid = ffi.C.getuid
S.geteuid = ffi.C.geteuid
S.getpid = ffi.C.getpid
S.getppid = ffi.C.getppid
S.umask = ffi.C.umask

-- 'macros' and helper functions etc

-- note that major and minor are inline in glibc, gnu provides these real symbols, else you might have to parse yourself
function S.major(dev) return ffi.C.gnu_dev_major(dev) end
function S.minor(dev) return ffi.C.gnu_dev_minor(dev) end

function S.S_ISREG(m)  return bit.band(m, S.S_IFREG)  ~= 0 end
function S.S_ISDIR(m)  return bit.band(m, S.S_IFDIR)  ~= 0 end
function S.S_ISCHR(m)  return bit.band(m, S.S_IFCHR)  ~= 0 end
function S.S_ISBLK(m)  return bit.band(m, S.S_IFBLK)  ~= 0 end
function S.S_ISFIFO(m) return bit.band(m, S.S_IFFIFO) ~= 0 end
function S.S_ISLNK(m)  return bit.band(m, S.S_IFLNK)  ~= 0 end
function S.S_ISSOCK(m) return bit.band(m, S.S_IFSOCK) ~= 0 end

-- non standard helpers
function S.nonblock(s)
  local fl, err, errno = assert(s:fcntl("F_GETFL"))
  if not fl then return nil, err, errno end
  fl, err, errno = s:fcntl("F_SETFL", bit.bor(fl, S.O_NONBLOCK))
  if not fl then return nil, err, errno end
  return true
end

-- methods on an fd
local fdmethods = {'nogc', 'nonblock', 
                   'close', 'dup', 'dup2', 'dup3', 'read', 'write', 'pread', 'pwrite',
                   'lseek', 'fchdir', 'fsync', 'fdatasync', 'fstat', 'fcntl', 'fchmod',
                   'bind', 'listen', 'connect', 'accept', 'getsockname', 'getpeername',
                   'send', 'sendto', 'recv', 'recvfrom', 'readv', 'writev'}
local fmeth = {}
for i, v in ipairs(fdmethods) do fmeth[v] = S[v] end

fd_t = ffi.metatype("struct {int fd;}", {__index = fmeth, __gc = S.close})

-- we could just return as S.timespec_t etc, not sure which is nicer?
S.t = {
  fd = fd_t, timespec = timespec_t, buffer = buffer_t, stat = stat_t, -- not clear if type for fd useful
  sockaddr = sockaddr_t, sockaddr_in = sockaddr_in_t, in_addr = in_addr_t, utsname = utsname_t, sockaddr_un = sockaddr_un_t,
  iovec = iovec_t, msghdr = msghdr_t
}

return S


