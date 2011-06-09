local ffi = require "ffi"
local bit = require "bit"

local C = ffi.C

local rt
if pcall(function () rt = ffi.load("rt") end) then end

-- note should wrap more conditionals around stuff that might not be there
-- possibly generate more of this from C program, depending on where it differs.

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
S.O_CLOEXEC   = octal('02000000')
S.O_NOATIME   = octal('01000000')
S.O_DSYNC     = octal('010000')
S.O_RSYNC     = S.O_SYNC

-- these are arch dependent!
if ffi.arch == "x86" or ffi.arch == "x64" then
  S.O_DIRECTORY = octal('0200000')
  S.O_NOFOLLOW  = octal('0400000')
  S.O_DIRECT    = octal('040000')
elseif ffi.arch == "arm" then
  S.O_DIRECTORY = octal('040000')
  S.O_NOFOLLOW  = octal('0100000')
  S.O_DIRECT    = octal('0200000')
end

-- modes
S.S_IFMT   = octal('0170000')
S.S_IFSOCK = octal('0140000')
S.S_IFLNK  = octal('0120000')
S.S_IFREG  = octal('0100000')
S.S_IFBLK  = octal('0060000')
S.S_IFDIR  = octal('0040000')
S.S_IFCHR  = octal('0020000')
S.S_IFIFO  = octal('0010000')
S.S_ISUID  = octal('0004000')
S.S_ISGID  = octal('0002000')
S.S_ISVTX  = octal('0001000')

S.S_IRWXU = octal('00700')
S.S_IRUSR = octal('00400')
S.S_IWUSR = octal('00200')
S.S_IXUSR = octal('00100')
S.S_IRWXG = octal('00070')
S.S_IRGRP = octal('00040')
S.S_IWGRP = octal('00020')
S.S_IXGRP = octal('00010')
S.S_IRWXO = octal('00007')
S.S_IROTH = octal('00004')
S.S_IWOTH = octal('00002')
S.S_IXOTH = octal('00001')

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

-- misc socket constants
S.SCM_RIGHTS = 0x01
S.SCM_CREDENTIALS = 0x02

S.SOL_SOCKET     = 1

S.SOL_RAW        = 255
S.SOL_DECNET     = 261
S.SOL_X25        = 262
S.SOL_PACKET     = 263
S.SOL_ATM        = 264
S.SOL_AAL        = 265
S.SOL_IRDA       = 266

S.SO_DEBUG       = 1
S.SO_REUSEADDR   = 2
S.SO_TYPE        = 3
S.SO_ERROR       = 4
S.SO_DONTROUTE   = 5
S.SO_BROADCAST   = 6
S.SO_SNDBUF      = 7
S.SO_RCVBUF      = 8
S.SO_SNDBUFFORCE = 32
S.SO_RCVBUFFORCE = 33
S.SO_KEEPALIVE   = 9
S.SO_OOBINLINE   = 10
S.SO_NO_CHECK    = 11
S.SO_PRIORITY    = 12
S.SO_LINGER      = 13
S.SO_BSDCOMPAT   = 14
assert(ffi.arch ~= "ppc", "need to fix the values below for ppc")
S.SO_PASSCRED    = 16 -- below here differs for ppc!
S.SO_PEERCRED    = 17
S.SO_RCVLOWAT    = 18
S.SO_SNDLOWAT    = 19
S.SO_RCVTIMEO    = 20
S.SO_SNDTIMEO    = 21

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
S.MSG_TRYHARD         = S.MSG_DONTROUTE
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

-- epoll
S.EPOLL_CLOEXEC = 02000000
S.EPOLL_NONBLOCK = 04000

S.EPOLLIN = 0x001
S.EPOLLPRI = 0x002
S.EPOLLOUT = 0x004
S.EPOLLRDNORM = 0x040
S.EPOLLRDBAND = 0x080
S.EPOLLWRNORM = 0x100
S.EPOLLWRBAND = 0x200
S.EPOLLMSG = 0x400
S.EPOLLERR = 0x008
S.EPOLLHUP = 0x010
S.EPOLLRDHUP = 0x2000
S.EPOLLONESHOT = bit.lshift(1, 30)
S.EPOLLET = bit.lshift(1, 31)

-- file types in directory
S.DT_UNKNOWN = 0
S.DT_FIFO = 1
S.DT_CHR = 2
S.DT_DIR = 4
S.DT_BLK = 6
S.DT_REG = 8
S.DT_LNK = 10
S.DT_SOCK = 12
S.DT_WHT = 14

-- netlink
S.NLM_F_REQUEST = 1
S.NLM_F_MULTI   = 2
S.NLM_F_ACK     = 4
S.NLM_F_ECHO    = 8

S.NLM_F_ROOT    = 0x100
S.NLM_F_MATCH   = 0x200
S.NLM_F_ATOMIC  = 0x400
S.NLM_F_DUMP    = bit.bor(S.NLM_F_ROOT, S.NLM_F_MATCH)

S.NLM_F_REPLACE = 0x100
S.NLM_F_EXCL    = 0x200
S.NLM_F_CREATE  = 0x400
S.NLM_F_APPEND  = 0x800

-- generic types. not defined as enums as overloaded for different protocols, and need to be 16 bit
S.NLMSG_NOOP     = 0x1
S.NLMSG_ERROR    = 0x2
S.NLMSG_DONE     = 0x3
S.NLMSG_OVERRUN  = 0x4
-- routing
S.RTM_NEWLINK     = 16
S.RTM_DELLINK     = 17
S.RTM_GETLINK     = 18
S.RTM_SETLINK     = 19
S.RTM_NEWADDR     = 20
S.RTM_DELADDR     = 21
S.RTM_GETADDR     = 22
S.RTM_NEWROUTE    = 24
S.RTM_DELROUTE    = 25
S.RTM_GETROUTE    = 26
S.RTM_NEWNEIGH    = 28
S.RTM_DELNEIGH    = 29
S.RTM_GETNEIGH    = 30
S.RTM_NEWRULE     = 32
S.RTM_DELRULE     = 33
S.RTM_GETRULE     = 34
S.RTM_NEWQDISC    = 36
S.RTM_DELQDISC    = 37
S.RTM_GETQDISC    = 38
S.RTM_NEWTCLASS   = 40
S.RTM_DELTCLASS   = 41
S.RTM_GETTCLASS   = 42
S.RTM_NEWTFILTER  = 44
S.RTM_DELTFILTER  = 45
S.RTM_GETTFILTER  = 46
S.RTM_NEWACTION   = 48
S.RTM_DELACTION   = 49
S.RTM_GETACTION   = 50
S.RTM_NEWPREFIX   = 52
S.RTM_GETMULTICAST = 58
S.RTM_GETANYCAST  = 62
S.RTM_NEWNEIGHTBL = 64
S.RTM_GETNEIGHTBL = 66
S.RTM_SETNEIGHTBL = 67
S.RTM_NEWNDUSEROPT = 68
S.RTM_NEWADDRLABEL = 72
S.RTM_DELADDRLABEL = 73
S.RTM_GETADDRLABEL = 74
S.RTM_GETDCB = 78
S.RTM_SETDCB = 79

-- need address families as constants too (? derive from enums?)
S.AF_UNSPEC     = 0
S.AF_LOCAL      = 1
S.AF_UNIX       = S.AF_LOCAL
S.AF_FILE       = S.AF_LOCAL
S.AF_INET       = 2
S.AF_AX25       = 3
S.AF_IPX        = 4
S.AF_APPLETALK  = 5
S.AF_NETROM     = 6
S.AF_BRIDGE     = 7
S.AF_ATMPVC     = 8
S.AF_X25        = 9
S.AF_INET6      = 10
S.AF_ROSE       = 11
S.AF_DECnet     = 12
S.AF_NETBEUI    = 13
S.AF_SECURITY   = 14
S.AF_KEY        = 15
S.AF_NETLINK    = 16
S.AF_ROUTE      = S.AF_NETLINK
S.AF_PACKET     = 17
S.AF_ASH        = 18
S.AF_ECONET     = 19
S.AF_ATMSVC     = 20
S.AF_RDS        = 21
S.AF_SNA        = 22
S.AF_IRDA       = 23
S.AF_PPPOX      = 24
S.AF_WANPIPE    = 25
S.AF_LLC        = 26
S.AF_CAN        = 29
S.AF_TIPC       = 30
S.AF_BLUETOOTH  = 31
S.AF_IUCV       = 32
S.AF_RXRPC      = 33
S.AF_ISDN       = 34
S.AF_PHONET     = 35
S.AF_IEEE802154 = 36
S.AF_CAIF       = 37
S.AF_ALG        = 38
S.AF_MAX        = 39

-- constants
local HOST_NAME_MAX = 64 -- Linux. should we export?

-- misc
function S.nogc(d) ffi.gc(d, nil) end
local errorret, retint, retbool, retptr, retfd, getfd

function S.strerror(errno) return ffi.string(C.strerror(errno)), errno end

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

-- OS specific stuff, eg constants
if ffi.os == "Linux" then
ffi.cdef[[
static const int _UTSNAME_LENGTH = 65
]]
elseif ffi.os == "OSX" then
ffi.cdef[[
static const int _UTSNAME_LENGTH = 256
]]
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
typedef int32_t clockid_t;

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

// should be a word, but we use 32 bits as bitops are 32 bit in LuaJIT at the moment
typedef uint32_t fd_mask;

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
// for uname.
struct utsname {
  char sysname[_UTSNAME_LENGTH];
  char nodename[_UTSNAME_LENGTH];
  char release[_UTSNAME_LENGTH];
  char version[_UTSNAME_LENGTH];
  char machine[_UTSNAME_LENGTH];
  char domainname[_UTSNAME_LENGTH]; // may not exist
};
struct iovec {
  void *iov_base;
  size_t iov_len;
};
typedef struct { /* based on Linux/FreeBSD FD_SETSIZE = 1024, the kernel can do more, so can increase, but bad performance so dont! */
  fd_mask fds_bits[1024 / (sizeof (fd_mask) * 8)];
} fd_set;
struct ucred { /* this is Linux specific */
  pid_t pid;
  uid_t uid;
  gid_t gid;
};
struct sysinfo { /* Linux only */
  long uptime;
  unsigned long loads[3];
  unsigned long totalram;
  unsigned long freeram;
  unsigned long sharedram;
  unsigned long bufferram;
  unsigned long totalswap;
  unsigned long freeswap;
  unsigned short procs;
  unsigned short pad;
  unsigned long totalhigh;
  unsigned long freehigh;
  unsigned int mem_unit;
  char _f[20-2*sizeof(long)-sizeof(int)];
};
struct msghdr {
  void *msg_name;
  socklen_t msg_namelen;
  struct iovec *msg_iov;
  size_t msg_iovlen;
  unsigned char *msg_control; /* changed from void* to simplify casts */
  size_t msg_controllen;
  int msg_flags;
};
struct cmsghdr {
  size_t cmsg_len;            /* Length of data in cmsg_data plus length of cmsghdr structure. */
  int cmsg_level;             /* Originating protocol.  */
  int cmsg_type;              /* Protocol specific type.  */
  unsigned char cmsg_data[?]; /* Ancillary data. note VLA in glibc, but macros to access for compatibility */
};
struct sockaddr {
  sa_family_t sa_family;
  char sa_data[14];
};
struct sockaddr_storage {
  sa_family_t ss_family;
  unsigned long int __ss_align;
  char __ss_padding[128 - 2 * sizeof(unsigned long int)]; /* total length 128 */
};
struct in_addr {
  uint32_t       s_addr;
};
struct in6_addr {
  unsigned char  s6_addr[16];
};
struct sockaddr_in {
  sa_family_t    sin_family;
  in_port_t      sin_port;
  struct in_addr sin_addr;
  unsigned char  sin_zero[8]; /* padding, should not vary by arch */
};
struct sockaddr_in6 {
  sa_family_t    sin6_family;
  in_port_t sin6_port;
  uint32_t sin6_flowinfo;
  struct in6_addr sin6_addr;
  uint32_t sin6_scope_id;
};
struct sockaddr_un {
  sa_family_t sun_family;
  char        sun_path[108];
};
struct sockaddr_nl {
  sa_family_t     nl_family;
  unsigned short  nl_pad;
  uint32_t        nl_pid;
  uint32_t        nl_groups;
};
struct nlmsghdr {
  uint32_t           nlmsg_len;
  uint16_t           nlmsg_type;
  uint16_t           nlmsg_flags;
  uint32_t           nlmsg_seq;
  uint32_t           nlmsg_pid;
};
struct rtgenmsg {
  unsigned char           rtgen_family;
};
struct linux_dirent {
  long           d_ino;
  off_t          d_off;
  unsigned short d_reclen;
  char           d_name[];
};
typedef union epoll_data {
  void *ptr;
  int fd;
  uint32_t u32;
  uint64_t u64;
} epoll_data_t;
#pragma pack(push)  /* we need to align these to replace gcc packed attribute */
#pragma pack(4) 
struct epoll_event {
  uint32_t events;      /* Epoll events */
  epoll_data_t data;    /* User data variable */
};   // __attribute__ ((__packed__));
#pragma pack(pop)

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
enum SIG_ { /* maybe not the clearest name */
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
enum CLOCK {
  CLOCK_REALTIME = 0,
  CLOCK_MONOTONIC = 1,
  CLOCK_PROCESS_CPUTIME_ID = 2,
  CLOCK_THREAD_CPUTIME_ID = 3,
  CLOCK_MONOTONIC_RAW = 4,
  CLOCK_REALTIME_COARSE = 5,
  CLOCK_MONOTONIC_COARSE = 6,
};
enum NETLINK {
  NETLINK_ROUTE         = 0,
  NETLINK_UNUSED        = 1,
  NETLINK_USERSOCK      = 2,
  NETLINK_FIREWALL      = 3,
  NETLINK_INET_DIAG     = 4,
  NETLINK_NFLOG         = 5,
  NETLINK_XFRM          = 6,
  NETLINK_SELINUX       = 7,
  NETLINK_ISCSI         = 8,
  NETLINK_AUDIT         = 9,
  NETLINK_FIB_LOOKUP    = 10,      
  NETLINK_CONNECTOR     = 11,
  NETLINK_NETFILTER     = 12,
  NETLINK_IP6_FW        = 13,
  NETLINK_DNRTMSG       = 14,
  NETLINK_KOBJECT_UEVENT= 15,
  NETLINK_GENERIC       = 16,
/* leave room for NETLINK_DM (DM Events) */
  NETLINK_SCSITRANSPORT = 18,
  NETLINK_ECRYPTFS      = 19,
};
enum EPOLL {
  EPOLL_CTL_ADD = 1,
  EPOLL_CTL_DEL = 2,
  EPOLL_CTL_MOD = 3,
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
-- this is the way glibc versions stat via __xstat, may need to change for other libc, eg if define stat as a non inline function
-- uclibc seems to use gnu stat now though, but without versioning
-- could just use the syscall!
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
]]
end

-- are there issues with 32 on 64, __old_kernel_stat? -- seems that uclibc does not use this
--[[if ffi.arch == 'x86' then
ffi.cdef[[
struct stat {
  unsigned long  st_dev;
  unsigned long  st_ino;
  unsigned short st_mode;
  unsigned short st_nlink;
  unsigned short st_uid;
  unsigned short st_gid;
  unsigned long  st_rdev;
  unsigned long  st_size;
  unsigned long  st_blksize;
  unsigned long  st_blocks;
  unsigned long  st_atime;
  unsigned long  st_atime_nsec;
  unsigned long  st_mtime;
  unsigned long  st_mtime_nsec;
  unsigned long  st_ctime;
  unsigned long  st_ctime_nsec;
  unsigned long  __unused4;
  unsigned long  __unused5;
};
]]
--[[else -- all architectures except x86 the same
ffi.cdef [[
struct stat {
  unsigned long   st_dev;
  unsigned long   st_ino;
  unsigned long   st_nlink;
  unsigned int    st_mode;
  unsigned int    st_uid;
  unsigned int    st_gid;
  unsigned int    __pad0;
  unsigned long   st_rdev;
  long            st_size;
  long            st_blksize;
  long            st_blocks;
  unsigned long   st_atime;
  unsigned long   st_atime_nsec;
  unsigned long   st_mtime;
  unsigned long   st_mtime_nsec;
  unsigned long   st_ctime;
  unsigned long   st_ctime_nsec;
  long            __unused[3];
};
]]
--end

-- completely arch dependent stuff. Note not defining all the syscalls yet
-- note ARM EABI same syscall numbers as x86, not tested on non eabi arm, will need offset added
if ffi.abi("32bit") and (ffi.arch == "x86" or (ffi.arch == "arm" and ffi.abi("eabi"))) then
ffi.cdef[[
enum SYS {
  SYS_getdents = 141,
};
]]
elseif ffi.abi("64bit") and ffi.arch == "x64" then
ffi.cdef[[
enum SYS {
  SYS_getdents = 78,
};
]]
end

-- shared code

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
gid_t getgid(void);
gid_t getegid(void);
pid_t fork(void);
int execve(const char *filename, const char *argv[], const char *envp[]);
pid_t wait(int *status);
pid_t waitpid(pid_t pid, int *status, int options);
void _exit(enum EXIT status);
enum SIG_ signal(enum SIG signum, enum SIG_ handler); /* although deprecated, just using to set SIG_ values */
int gettimeofday(struct timeval *tv, void *tz);   /* not even defining struct timezone */
int settimeofday(const struct timeval *tv, const void *tz);
time_t time(time_t *t);
int clock_getres(enum CLOCK clk_id, struct timespec *res); // was clockid_t clk_id
int clock_gettime(enum CLOCK clk_id, struct timespec *tp); // was clockid_t clk_id
int clock_settime(enum CLOCK clk_id, const struct timespec *tp); // was clockid_t clk_id
int sysinfo(struct sysinfo *info);

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
int getsockopt(int sockfd, int level, int optname, void *optval, socklen_t *optlen);
int setsockopt(int sockfd, int level, int optname, const void *optval, socklen_t optlen);
int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, struct timeval *timeout);
int epoll_create1(int flags);
int epoll_ctl(int epfd, enum EPOLL op, int fd, struct epoll_event *event);
int epoll_wait(int epfd, struct epoll_event *events, int maxevents, int timeout);
ssize_t sendfile(int out_fd, int in_fd, off_t *offset, size_t count);

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

int pipe(int pipefd[2]);
int pipe2(int pipefd[2], int flags);

int unlink(const char *pathname);
int access(const char *pathname, int mode);
char *getcwd(char *buf, size_t size);

int nanosleep(const struct timespec *req, struct timespec *rem);

int syscall(enum SYS number, ...);

// stat glibc internal functions
int __fxstat(int ver, int fd, struct stat *buf);
int __xstat(int ver, const char *path, struct stat *buf);
int __lxstat(int ver, const char *path, struct stat *buf);
// real stat functions, might not exist
int stat(const char *path, struct stat *buf);
int fstat(int fd, struct stat *buf);
int lstat(const char *path, struct stat *buf);

// functions from libc ie man 3 not man 2
void exit(enum EXIT status);
int inet_aton(const char *cp, struct in_addr *inp);
char *inet_ntoa(struct in_addr in);
int inet_pton(enum AF, const char *src, void *dst);
const char *inet_ntop(enum AF, const void *src, char *dst, socklen_t size);

// functions from libc that could be exported as a convenience, used internally
void *calloc(size_t nmemb, size_t size);
void *malloc(size_t size);
void free(void *ptr);
void *realloc(void *ptr, size_t size);
char *strerror(enum E errnum);
]]

-- glibc does not have a stat symbol, has its own struct stat and way of calling
local use_gnu_stat
if pcall(function () local t = C.stat end) then use_gnu_stat = false else use_gnu_stat = true end

-- Lua type constructors corresponding to defined types
local timespec_t = ffi.typeof("struct timespec")
local timeval_t = ffi.typeof("struct timeval")
local sockaddr_t = ffi.typeof("struct sockaddr")
local sockaddr_storage_t = ffi.typeof("struct sockaddr_storage")
local sa_family_t = ffi.typeof("sa_family_t")
local sockaddr_in_t = ffi.typeof("struct sockaddr_in")
local sockaddr_in6_t = ffi.typeof("struct sockaddr_in6")
local in_addr_t = ffi.typeof("struct in_addr")
local in6_addr_t = ffi.typeof("struct in6_addr")
local sockaddr_un_t = ffi.typeof("struct sockaddr_un")
local sockaddr_nl_t = ffi.typeof("struct sockaddr_nl")
local iovec_t = ffi.typeof("struct iovec[?]")
local msghdr_t = ffi.typeof("struct msghdr")
local cmsghdr_t = ffi.typeof("struct cmsghdr")
local ucred_t = ffi.typeof("struct ucred")
local sysinfo_t = ffi.typeof("struct sysinfo")
local fdset_t = ffi.typeof("fd_set")
local fdmask_t = ffi.typeof("fd_mask")
local stat_t = ffi.typeof("struct stat")
local epoll_event_t = ffi.typeof("struct epoll_event")
local epoll_events_t = ffi.typeof("struct epoll_event[?]")
local off_t = ffi.typeof("off_t")
local nlmsghdr_t = ffi.typeof("struct nlmsghdr")
local rtgenmsg_t = ffi.typeof("struct rtgenmsg")

--[[ -- used to generate tests, will refactor into test code later
print("eq (sizeof(struct timespec), " .. ffi.sizeof(timespec_t) .. ");")
print("eq (sizeof(struct timeval), " .. ffi.sizeof(timeval_t) .. ");")
print("eq (sizeof(struct sockaddr_storage), " .. ffi.sizeof(sockaddr_storage_t) .. ");")
print("eq (sizeof(struct sockaddr_in), " .. ffi.sizeof(sockaddr_in_t) .. ");")
print("eq (sizeof(struct sockaddr_in6), " .. ffi.sizeof(sockaddr_in6_t) .. ");")
print("eq (sizeof(struct sockaddr_un), " .. ffi.sizeof(sockaddr_un_t) .. ");")
print("eq (sizeof(struct iovec), " .. ffi.sizeof(iovec_t(1)) .. ");")
print("eq (sizeof(struct msghdr), " .. ffi.sizeof(msghdr_t) .. ");")
print("eq (sizeof(struct cmsghdr), " .. ffi.sizeof(cmsghdr_t(0)) .. ");")
print("eq (sizeof(struct sysinfo), " .. ffi.sizeof(sysinfo_t) .. ");")
]]
--print(ffi.sizeof("struct stat"))
--print(ffi.sizeof("struct gstat"))

local int_t = ffi.typeof("int")
local uint_t = ffi.typeof("unsigned int")
local off1_t = ffi.typeof("off_t[1]") -- used to pass off_t to sendfile etc
local int1_t = ffi.typeof("int[1]") -- used to pass pointer to int
local int2_t = ffi.typeof("int[2]") -- pair of ints, eg for pipe
local ints_t = ffi.typeof("int[?]") -- array of ints
local int64_t = ffi.typeof("int64_t")
local int32_pt = ffi.typeof("int32_t *")
local int64_1t = ffi.typeof("int64_t[1]")
local string_array_t = ffi.typeof("const char *[?]")

-- enums, not sure if there is a betetr way to convert
local enumAF_t = ffi.typeof("enum AF") -- used for converting enum
local enumE_t = ffi.typeof("enum E") -- used for converting error names
local enumCLOCK_t = ffi.typeof("enum CLOCK") -- for clockids
local enumNETTLINK = ffi.typeof("enum NETLINK") -- netlink socket protocols

-- need these for casts
local sockaddr_pt = ffi.typeof("struct sockaddr *")
local cmsghdr_pt = ffi.typeof("struct cmsghdr *")
local uchar_pt = ffi.typeof("unsigned char *")
local int_pt = ffi.typeof("int *")
local linux_dirent_pt = ffi.typeof("struct linux_dirent *")

assert(ffi.sizeof(sockaddr_t) == ffi.sizeof(sockaddr_in_t)) -- inet socket addresses should be padded to same as sockaddr
assert(ffi.sizeof(sockaddr_storage_t) == 128) -- this is the required size in Linux
assert(ffi.sizeof(sockaddr_storage_t) >= ffi.sizeof(sockaddr_t))
assert(ffi.sizeof(sockaddr_storage_t) >= ffi.sizeof(sockaddr_in_t))
assert(ffi.sizeof(sockaddr_storage_t) >= ffi.sizeof(sockaddr_in6_t))
assert(ffi.sizeof(sockaddr_storage_t) >= ffi.sizeof(sockaddr_un_t))
assert(ffi.sizeof(sockaddr_storage_t) >= ffi.sizeof(sockaddr_nl_t))

-- misc
local div = function(a, b) return math.floor(tonumber(a) / tonumber(b)) end -- would be nicer if replaced with shifts, as only powers of 2

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
-- need to set first field for sockaddr. Corrects byte order on port, constructor for addr will do that for addr.
function S.sockaddr_in(port, addr)
  if type(addr) == 'string' then addr = S.inet_aton(addr) end
  if not addr then return nil end
  return sockaddr_in_t(enumAF_t("AF_INET"), S.htons(port), addr)
end
function S.sockaddr_in6(port, addr)
  if type(addr) == 'string' then addr = S.inet_pton("INET6", addr) end
  if not addr then return nil end
  local sa = sockaddr_in6_t()
  sa.sin6_family = enumAF_t("AF_INET6")
  sa.sin6_port = S.htons(port)
  ffi.copy(sa.sin6_addr, addr, ffi.sizeof(in6_addr_t))
  return sa
end
function S.sockaddr_un() -- actually, not using this, not sure it is useful for unix sockets
  local addr = sockaddr_in_t()
  addr.sun_family = enumAF_t("AF_UNIX")
  return addr
end
function S.sockaddr_nl(pid, groups)
  local addr = sockaddr_nl_t()
  addr.nl_family = enumAF_t("AF_NETLINK")
  if pid then addr.nl_pid = pid end -- optional, kernel will set
  if groups then addr.nl_groups = groups end
  return addr
end

local fam = function(s) return tonumber(enumAF_t(s)) end -- convert to Lua number, as tables indexed by number

-- map from socket family to data type
local socket_type = {}
-- AF_UNSPEC
socket_type[fam("AF_LOCAL")] = sockaddr_un_t
socket_type[fam("AF_INET")] = sockaddr_in_t
--  AF_AX25
--  AF_IPX
--  AF_APPLETALK
--  AF_NETROM
--  AF_BRIDGE
--  AF_ATMPVC
--  AF_X25
socket_type[fam("AF_INET6")] = sockaddr_in6_t
--  AF_ROSE
--  AF_DECnet
--  AF_NETBEUI
--  AF_SECURITY
--  AF_KEY
socket_type[fam("AF_NETLINK")] = sockaddr_nl_t
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
    if ffi.istype(sockaddr_in6_t, addr) then return ffi.sizeof(sockaddr_in6_t) end
    if ffi.istype(sockaddr_nl_t, addr) then return ffi.sizeof(sockaddr_nl_t) end
  end
  return addrlen or 0
end

-- helper function for returning socket address types
local saret
saret = function(ss, addrlen, rets) -- return socket address structure, additional values to return in rets
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
    elseif ffi.istype(sockaddr_nl_t, addr) then
      rets.pid = addr.nl_pid
      rets.groups = addr.nl_groups
    end
  end
  return rets
end

-- functions from section 3 that we use for ip addresses
function S.inet_aton(s)
  local addr = in_addr_t()
  local ret = C.inet_aton(s, addr)
  if ret == 0 then return nil end
  return addr
end

function S.inet_ntoa(addr) return ffi.string(C.inet_ntoa(addr)) end

local INET6_ADDRSTRLEN = 46
local INET_ADDRSTRLEN = 16

function S.inet_ntop(af, src)
  local len = INET6_ADDRSTRLEN -- could shorten for ipv4
  local dst = buffer_t(len)
  local ret = C.inet_ntop(af, src, dst, len)
  if ret == nil then return errorret() end
  return ffi.string(dst)
end

function S.inet_pton(af, src)
  local addr
  if fam(af) == fam("AF_INET") then addr = in_addr_t()
  elseif fam(af) == fam("AF_INET6") then addr = in6_addr_t() end
  local ret = C.inet_pton(af, src, addr)
  if ret == -1 then return errorret() end
  if ret == 0 then return nil end -- maybe return string
  return addr
end

-- constants
S.INADDR_ANY = in_addr_t()
S.INADDR_LOOPBACK = assert(S.inet_aton("127.0.0.1"))
S.INADDR_BROADCAST = assert(S.inet_aton("255.255.255.255"))
-- ipv6 versions
S.in6addr_any = in6_addr_t()
S.in6addr_loopback = S.inet_pton("AF_INET6", "::1") -- no assert, may fail if no inet6 support

-- main definitions start here
function S.open(pathname, flags, mode) return retfd(C.open(pathname, flags or 0, mode or 0)) end

function S.dup(oldfd, newfd, flags)
  if newfd == nil then return retfd(C.dup(getfd(oldfd))) end
  if flags == nil then return retfd(C.dup2(getfd(oldfd), getfd(newfd))) end
  return retfd(C.dup3(getfd(oldfd), getfd(newfd), flags))
end
S.dup2 = S.dup
S.dup3 = S.dup

function S.pipe(flags)
  local fd2 = int2_t()
  local ret
  if flags then ret = C.pipe2(fd2, flags) else ret = C.pipe(fd2) end
  if ret == -1 then return errorret() end
  return {fd_t(fd2[0]), fd_t(fd2[1])}
end
S.pipe2 = S.pipe

function S.close(fd)
  local ret = C.close(getfd(fd))
  if ret == -1 then return errorret() end
  if ffi.istype(fd_t, fd) then
    ffi.gc(fd, nil) -- remove gc finalizer as now closed; should we also remove if get EBADF?
  end
  return true
end

function S.creat(pathname, mode) return retfd(C.creat(pathname, mode or 0)) end
function S.unlink(pathname) return retbool(C.unlink(pathname)) end
function S.access(pathname, mode) return retbool(C.access(pathname, mode)) end
function S.chdir(path) return retbool(C.chdir(path)) end
function S.mkdir(path, mode) return retbool(C.mkdir(path, mode)) end
function S.rmdir(path) return retbool(C.rmdir(path)) end
function S.unlink(pathname) return retbool(C.unlink(pathname)) end
function S.acct(filename) return retbool(C.acct(filename)) end
function S.chmod(path, mode) return retbool(C.chmod(path, mode)) end
function S.link(oldpath, newpath) return retbool(C.link(oldpath, newpath)) end

function S.fork() return retint(C.fork()) end
function S.execve(filename, argv, envp)
  local cargv = string_array_t(#argv + 1, argv)
  cargv[#argv] = nil -- LuaJIT does not zero rest of a VLA
  local cenvp = string_array_t(#envp + 1, envp)
  cenvp[#envp] = nil
  return retbool(C.execve(filename, cargv, cenvp))
end

-- best to call C.syscall directly? do not export?
function S.syscall(num, ...)
  -- call with the right types, use at your own risk
  local a, b, c, d, e, f = ...
  local ret = C.syscall(num, a, b, c, d, e, f)
  if ret == -1 then return errorret() end
  return ret
end

function S.getdents(fd, buf, size)
  if not buf then
    size = size or 4096
    buf = buffer_t(size)
  end
  local d = {}
  local ret
  repeat
    ret = C.syscall("SYS_getdents", uint_t(getfd(fd)), buf, uint_t(size))
    if ret == -1 then return errorret() end
    local i = 0
    while i < ret do
      local dp = ffi.cast(linux_dirent_pt, buf + i)
      local t = buf[i + dp.d_reclen - 1]
      local dd = {inode = tonumber(dp.d_ino), offset = tonumber(dp.d_off)}
      for _, f in ipairs{"DT_UNKNOWN", "DT_FIFO", "DT_CHR", "DT_DIR", "DT_BLK", "DT_REG", "DT_LNK", "DT_SOCK", "DT_WHT"} do
        if t == S[f] then dd[f] = true end
      end
      d[ffi.string(dp.d_name)] = dd
      i = i + dp.d_reclen
    end
  until ret == 0
  return d
end

local retwait
function retwait(ret, status)
  if ret == -1 then return errorret() end
  local w = {pid = ret, status = status}
  local WTERMSIG = bit.band(status, 0x7f)
  local EXITSTATUS = bit.rshift(bit.band(status, 0xff00), 8)
  w.WIFEXITED = WTERMSIG == 0
  if w.WIFEXITED then w.EXITSTATUS = EXITSTATUS end
  w.WIFSTOPPED = bit.band(status, 0xff) == 0x7f
  if w.WIFSTOPPED then w.WSTOPSIG = EXITSTATUS end
  w.WIFSIGNALED = not w.WIFEXITED and bit.band(status, 0x7f) ~= 0x7f -- I think this is right????? TODO recheck, cleanup
  if w.WIFSIGNALED then w.WTERMSIG = WTERMSIG end
  return w
end

function S.wait()
  local status = int1_t()
  return retwait(C.wait(status), status[0])
end
function S.waitpid(pid, options)
  local status = int1_t()
  return retwait(C.waitpid(pid, status, options or 0), status[0])
end

function S._exit(status) C._exit(status or 0) end
function S.exit(status) C.exit(status or 0) end

function S.read(fd, buf, count)
  if buf then return retint(C.read(getfd(fd), buf, count)) end -- user supplied a buffer, standard usage
  local buf = buffer_t(count)
  local ret = C.read(getfd(fd), buf, count)
  if ret == -1 then return errorret() end
  return ffi.string(buf, ret) -- user gets a string back, can get length from #string
end

function S.write(fd, buf, count) return retint(C.write(getfd(fd), buf, count or #buf)) end
function S.pread(fd, buf, count, offset) return retint(C.pread(getfd(fd), buf, count, offset)) end
function S.pwrite(fd, buf, count, offset) return retint(C.pwrite(getfd(fd), buf, count, offset)) end
function S.lseek(fd, offset, whence) return retint(C.lseek(getfd(fd), offset, whence)) end
function S.send(fd, buf, count, flags) return retint(C.send(getfd(fd), buf, count or #buf, flags or 0)) end
function S.sendto(fd, buf, count, flags, addr, addrlen)
  return retint(C.sendto(getfd(fd), buf, count or #buf, flags or 0, ffi.cast(sockaddr_pt, addr), getaddrlen(addr)))
end
function S.readv(fd, iov, iovcnt) return retint(C.readv(getfd(fd), iov, iovcnt)) end
function S.writev(fd, iov, iovcnt) return retint(C.writev(getfd(fd), iov, iovcnt)) end

function S.recv(fd, buf, count, flags) return retint(C.recv(getfd(fd), buf, count or #buf, flags or 0)) end
function S.recvfrom(fd, buf, count, flags)
  local ss = sockaddr_storage_t()
  local addrlen = int1_t(ffi.sizeof(sockaddr_storage_t))
  local ret = C.recvfrom(getfd(fd), buf, count, flags or 0, ffi.cast(sockaddr_pt, ss), addrlen)
  if ret == -1 then return errorret() end
  return saret(ss, addrlen[0], {count = ret})
end

function S.setsockopt(fd, level, optname, optval, optlen)
   -- allocate buffer for user, from Lua type if know how, int and bool so far
  if not optlen and type(optval) == 'boolean' then if optval then optval = 1 else optval = 0 end end
  if not optlen and type(optval) == 'number' then
    optval = int1_t(optval)
    optlen = ffi.sizeof(int1_t)
  end
  return retbool(C.setsockopt(getfd(fd), level, optname, optval, optlen))
end

function S.fchdir(fd) return retbool(C.fchdir(getfd(fd))) end
function S.fsync(fd) return retbool(C.fsync(getfd(fd))) end
function S.fdatasync(fd) return retbool(C.fdatasync(getfd(fd))) end
function S.fchmod(fd, mode) return retbool(C.fchmod(getfd(fd), mode)) end

-- glibc does not have these directly
local stat, lstat, fstat

if use_gnu_stat then
  function stat(path, buf) return C.__xstat(STAT_VER_LINUX, path, buf) end
  function lstat(path, buf) return C.__lxstat(STAT_VER_LINUX, path, buf) end
  function fstat(fd, buf) return C.__fxstat(STAT_VER_LINUX, fd, buf) end
else
  stat = C.stat
  lstat = C.lstat
  fstat = C.fstat
end

function S.stat(path, buf)
  if not buf then buf = stat_t() end
  local ret = stat(path, buf)
  if ret == -1 then return errorret() end
  return buf
end
function S.lstat(path, buf)
  if not buf then buf = stat_t() end
  local ret = lstat(path, buf)
  if ret == -1 then return errorret() end
  return buf
end
function S.fstat(fd, buf)
  if not buf then buf = stat_t() end
  local ret = fstat(getfd(fd), buf)
  if ret == -1 then return errorret() end
  return buf
end

function S.getcwd(buf, size)
  local ret = C.getcwd(buf, size or 0)
  if not buf then -- Linux will allocate buffer here, return Lua string and free
    if ret == nil then return errorret() end
    local s = ffi.string(ret) -- guaranteed to be zero terminated if no error
    C.free(ret)
    return s
  end
  -- user allocated buffer
  if ret == nil then return errorret() end
  return true -- no point returning the pointer as it is just the passed buffer
end

function S.nanosleep(req)
  local rem = timespec_t()
  local ret = C.nanosleep(req, rem)
  if ret == -1 then return errorret() end
  return rem -- return second argument, Lua style
end

function S.mmap(addr, length, prot, flags, fd, offset)
  return retptr(C.mmap(addr, length, prot, flags, getfd(fd), offset), function(addr) C.munmap(addr, length) end) -- add munmap gc
end
function S.munmap(addr, length)
  return retbool(C.munmap(ffi.gc(addr, nil), length)) -- remove gc on unmap
end
function S.msync(addr, length, flags) return retbool(C.msync(addr, length, flags)) end
function S.mlock(addr, len) return retbool(C.mlock(addr, len)) end
function S.munlock(addr, len) return retbool(C.munlock(addr, len)) end
function S.mlockall(flags) return retbool(C.mlockall(flags)) end
function S.munlockall() return retbool(C.munlockall()) end
function S.mremap(old_address, old_size, new_size, flags, new_address) return retptr(C.mremap(old_address, old_size, new_size, flags, new_address)) end
function S.madvise(addr, length, advice) return retbool(C.madvise(addr, length, advice)) end

local sproto
function sproto(domain, protocol) -- helper function to cast protocol type depending on domain
  if not protcol then return 0 end
  if domain == "AF_NETLINK" then return emumNETLINK(protocol) end
  return protocol
end

function S.socket(domain, stype, protocol) return retfd(C.socket(domain, stype, sproto(domain, protocol))) end
function S.socketpair(domain, stype, protocol)
  local sv2 = int2_t()
  local ret = C.socketpair(domain, stype, sproto(domain, protocol), sv2)
  if ret == -1 then return errorret() end
  return {fd_t(sv2[0]), fd_t(sv2[1])}
end

function S.bind(sockfd, addr, addrlen)
  return retbool(C.bind(getfd(sockfd), ffi.cast(sockaddr_pt, addr), getaddrlen(addr, addrlen)))
end

function S.listen(sockfd, backlog) return retbool(C.listen(getfd(sockfd), backlog or 0)) end
function S.connect(sockfd, addr, addrlen)
  return retbool(C.connect(getfd(sockfd), ffi.cast(sockaddr_pt, addr), getaddrlen(addr, addrlen)))
end

function S.accept(sockfd)
  local ss = sockaddr_storage_t()
  local addrlen = int1_t(ffi.sizeof(sockaddr_storage_t))
  local ret = C.accept(getfd(sockfd), ffi.cast(sockaddr_pt, ss), addrlen)
  if ret == -1 then return errorret() end
  return saret(ss, addrlen[0], {fd = fd_t(ret)})
end
--S.accept4 = S.accept -- need to add support for flags argument TODO

function S.getsockname(sockfd)
  local ss = sockaddr_storage_t()
  local addrlen = int1_t(ffi.sizeof(sockaddr_storage_t))
  local ret = C.getsockname(getfd(sockfd), ffi.cast(sockaddr_pt, ss), addrlen)
  if ret == -1 then return errorret() end
  return saret(ss, addrlen[0])
end

function S.getpeername(sockfd)
  local ss = sockaddr_storage_t()
  local addrlen = int1_t(ffi.sizeof(sockaddr_storage_t))
  local ret = C.getpeername(getfd(sockfd), ffi.cast(sockaddr_pt, ss), addrlen)
  if ret == -1 then return errorret() end
  return saret(ss, addrlen[0])
end

function S.fcntl(fd, cmd, arg)
  -- some uses have arg as a pointer, need handling TODO
  local ret = C.fcntl(getfd(fd), cmd, arg or 0)
  -- return values differ, some special handling needed
  if cmd == "F_DUPFD" or cmd == "F_DUPFD_CLOEXEC" then return retfd(ret) end
  if cmd == "F_GETFD" or cmd == "F_GETFL" or cmd == "F_GETLEASE" or cmd == "F_GETOWN" or
     cmd == "F_GETSIG" or cmd == "F_GETPIPE_SZ" then return retint(ret) end
  return retbool(ret)
end

local utsname_t = ffi.typeof("struct utsname")
function S.uname()
  local u = utsname_t()
  local ret = C.uname(u)
  if ret == -1 then return errorret() end
  return {sysname = ffi.string(u.sysname), nodename = ffi.string(u.nodename), release = ffi.string(u.release),
          version = ffi.string(u.version), machine = ffi.string(u.machine), domainname = ffi.string(u.domainname)}
end

function S.gethostname()
  local buf = buffer_t(HOST_NAME_MAX + 1)
  local ret = C.gethostname(buf, HOST_NAME_MAX + 1)
  if ret == -1 then return errorret() end
  buf[HOST_NAME_MAX] = 0 -- paranoia here to make sure null terminated, which could happen if HOST_NAME_MAX was incorrect
  return ffi.string(buf)
end

function S.sethostname(s) -- only accept Lua string, do not see use case for buffer as well
  return retbool(C.sethostname(s, #s))
end

function S.signal(signum, handler) return retbool(C.signal(signum, handler)) end

function S.gettimeofday(tv)
  if not tv then tv = timeval_t() end -- note it is faster to pass your own tv if you call a lot
  local ret = C.gettimeofday(tv, nil)
  if ret == -1 then return errorret() end
  return tv
end

function S.settimeofday(tv) return retbool(C.settimeofday(tv, nil)) end

function S.time()
  -- local ret = C.time(nil)
  -- if ret == -1 then return errorret() end -- impossible with nil argument
  return tonumber(C.time(nil))
end

function S.sysinfo(info)
  if not info then info = sysinfo_t() end
  local ret = C.sysinfo(info)
  if ret == -1 then return errorret() end
  return info
end

local mkfdset, fdisset
function mkfdset(fds, nfds) -- should probably check fd is within range (1024), or just expand structure size
  local set = fdset_t()
  for i, v in ipairs(fds) do
    local fd = getfd(v)
    if fd + 1 > nfds then nfds = fd + 1 end
    local fdelt = bit.rshift(fd, 5) -- always 32 bits
    set.fds_bits[fdelt] = bit.bor(set.fds_bits[fdelt], bit.lshift(1, fd % 32)) -- always 32 bit words
  end
  return set, nfds
end

function fdisset(fds, set)
  local f = {}
  for i, v in ipairs(fds) do
    local fd = getfd(v)
    local fdelt = bit.rshift(fd, 5) -- always 32 bits
    if bit.band(set.fds_bits[fdelt], bit.lshift(1, fd % 32)) ~= 0 then table.insert(f, v) end -- careful not to duplicate fd objects
  end
  return f
end

function S.select(s) -- note same structure as returned
  local r, w, e
  local nfds = 0
  local timeout2
  if s.timeout then timeout2 = timeval_t(s.timeout.tv_sec, s.timeout.tv_usec) end -- copy so never updated
  r, nfds = mkfdset(s.readfds or {}, nfds or 0)
  w, nfds = mkfdset(s.writefds or {}, nfds)
  e, nfds = mkfdset(s.exceptfds or {}, nfds)
  local ret = C.select(nfds, r, w, e, timeout2)
  if ret == -1 then return errorret() end
  return {readfds = fdisset(s.readfds or {}, r), writefds = fdisset(s.writefds or {}, w),
          exceptfds = fdisset(s.exceptfds or {}, e), count = tonumber(ret)}
end

-- Linux only. use epoll1
function S.epoll_create(flags)
  return retfd(C.epoll_create1(flags or 0))
end

function S.epoll_ctl(epfd, op, fd, events, data)
  local event = epoll_event_t()
  event.events = events
  if data then event.data.u64 = data else event.data.fd = getfd(fd) end
  return retbool(C.epoll_ctl(getfd(epfd), op, getfd(fd), event))
end

local getflags -- make more generic and use elsewhere, and for constructing
function getflags(e)
  local r= {}
  for i, f in ipairs{"EPOLLIN", "EPOLLOUT", "EPOLLRDHUP", "EPOLLPRI", "EPOLLERR", "EPOLLHUP"} do
    if bit.band(e, S[f]) ~= 0 then r[f] = true end
  end
  return r
end

function S.epoll_wait(epfd, events, maxevents, timeout)
  if not maxevents then maxevents = 1 end
  if not events then events = epoll_events_t(maxevents) end
  local ret = C.epoll_wait(getfd(epfd), events, maxevents, timeout or 0)
  if ret == -1 then return errorret() end
  local r = {}
  for i = 1, ret do -- put in Lua array
    local e = events[i - 1]
    local rr = getflags(e.events)
    rr.fd = e.data.fd
    rr.data = e.data.u64
    r[i] = rr
  end
  return r
end

function S.sendfile(out_fd, in_fd, offset, count) -- bit odd having two different return types...
  if not offset then return retint(C.sendfile(getfd(out_fd), getfd(in_fd), nil, count)) end
  local off = off1_t()
  off[0] = offset
  local ret = C.sendfile(getfd(out_fd), getfd(in_fd), off, count)
  if ret == -1 then return errorret() end
  return {count = tonumber(ret), offset = off[0]}
end

if rt then -- real time functions not in glibc in Linux, check if available. N/A on OSX.
  function S.clock_getres(clk_id, ts)
    if not ts then ts = timespec_t() end
    local ret = rt.clock_getres(clk_id, ts)
    if ret == -1 then return errorret() end
    return ts
  end

  function S.clock_gettime(clk_id, ts)
    if not ts then ts = timespec_t() end
    local ret = rt.clock_gettime(clk_id, ts)
    if ret == -1 then return errorret() end
    return ts
  end

  function S.clock_settime(clk_id, ts) return retbool(rt.clock_settime(clk_id, ts)) end
end

-- straight passthroughs, as no failure possible
S.getuid = C.getuid
S.geteuid = C.geteuid
S.getpid = C.getpid
S.getppid = C.getppid
S.getgid = C.getgid
S.getegid = C.getegid
S.umask = C.umask

-- 'macros' and helper functions etc

-- LuaJIT does not provide 64 bit bitops at the moment
local b64
function b64(n)
  local t64 = int64_1t(n)
  local t32 = ffi.cast(int32_pt, t64)
  if ffi.abi("le") then
    return tonumber(t32[1]), tonumber(t32[0]) -- return high, low
  else
    return tonumber(t32[0]), tonumber(t32[1])
  end
end

function S.major(dev)
  h, l = b64(dev)
  return bit.bor(bit.band(bit.rshift(l, 8), 0xfff), bit.band(h, bit.bnot(0xfff)));
end

-- minor and makedev assume minor numbers 20 bit so all in low byte, currently true
-- would be easier to fix if LuaJIT had native 64 bit bitops
function S.minor(dev)
  h, l = b64(dev)
  return bit.bor(bit.band(l, 0xff), bit.band(bit.rshift(l, 12), bit.bnot(0xff)));
end

function S.makedev(major, minor)
  local dev = int64_t()
  dev = bit.bor(bit.band(minor, 0xff), bit.lshift(bit.band(major, 0xfff), 8), bit.lshift(bit.band(minor, bit.bnot(0xff)), 12)) + 0x100000000LL * bit.band(major, bit.bnot(0xfff))
  return dev
end

function S.S_ISREG(m)  return bit.band(m, S.S_IFREG)  ~= 0 end
function S.S_ISDIR(m)  return bit.band(m, S.S_IFDIR)  ~= 0 end
function S.S_ISCHR(m)  return bit.band(m, S.S_IFCHR)  ~= 0 end
function S.S_ISBLK(m)  return bit.band(m, S.S_IFBLK)  ~= 0 end
function S.S_ISFIFO(m) return bit.band(m, S.S_IFFIFO) ~= 0 end
function S.S_ISLNK(m)  return bit.band(m, S.S_IFLNK)  ~= 0 end
function S.S_ISSOCK(m) return bit.band(m, S.S_IFSOCK) ~= 0 end

-- cmsg functions, try to hide some of this nasty stuff from the user
local cmsg_align, cmsg_space, cmsg_len, cmsg_firsthdr, cmsg_nxthdr
local cmsg_hdrsize = ffi.sizeof(cmsghdr_t(0))
if ffi.abi('32bit') then
  function cmsg_align(len) return bit.band(tonumber(len) + 3, bit.bnot(3)) end
else
  function cmsg_align(len) return bit.band(tonumber(len) + 7, bit.bnot(7)) end
end
local cmsg_ahdr = cmsg_align(cmsg_hdrsize)
function cmsg_space(len) return cmsg_ahdr + cmsg_align(len) end
function cmsg_len(len) return cmsg_ahdr + len end

-- msg_control is a bunch of cmsg structs, but these are all different lengths, as they have variable size arrays

-- these functions also take and return a raw char pointer to msg_control, to make life easier, as well as the cast cmsg
function cmsg_firsthdr(msg)
  if msg.msg_controllen < cmsg_hdrsize then return nil end
  local mc = msg.msg_control
  local cmsg = ffi.cast(cmsghdr_pt, mc)
  return mc, cmsg
end

function cmsg_nxthdr(msg, mc, cmsg)
  if cmsg.cmsg_len < cmsg_hdrsize then return nil end -- invalid cmsg
  mc = mc + cmsg_align(cmsg.cmsg_len) -- find next cmsg
  if mc + cmsg_hdrsize > msg.msg_control + msg.msg_controllen then return nil end -- header would not fit
  cmsg = ffi.cast(cmsghdr_pt, mc)
  if mc + cmsg_align(cmsg.cmsg_len) > msg.msg_control + msg.msg_controllen then return nil end -- whole cmsg would not fit
  return mc, cmsg
end

-- similar functions for netlink messages
-- nlmsg_length is just length, as the header is already a multiple of the alignment
 

function S.sendmsg(fd, msg, flags)
  if not msg then -- send a single byte message, eg enough to send credentials
    msg = msghdr_t()
    local buf1 = buffer_t(1)
    io = iovec_t(1)
    io[0].iov_base = buf1
    io[0].iov_len = 1
    msg.msg_iov = io
    msg.msg_iovlen = 1
  end
  return retbool(C.sendmsg(getfd(fd), msg, flags or 0))
end

function S.recvmsg(fd, io, iolen, flags, bufsize) -- takes iovec, or nil in which case assume want to receive cmsg
  if not io then 
    local buf1 = buffer_t(1) -- if no iovec, assume user wants to receive single byte
    io = iovec_t(1)
    io[0].iov_base = buf1
    io[0].iov_len = 1
    iolen = 1
  end
  bufsize = bufsize or 512 -- reasonable default
  local buf = buffer_t(bufsize)
  local msg = msghdr_t()
  msg.msg_iov = io
  msg.msg_iovlen = iolen
  msg.msg_control = buf
  msg.msg_controllen = bufsize
  local ret = C.recvmsg(getfd(fd), msg, flags or 0)
  if ret == -1 then return errorret() end
  local ret = {count = ret, iovec = io} -- thats the basic return value, and the iovec
  local mc, cmsg = cmsg_firsthdr(msg)
  while cmsg do
    if cmsg.cmsg_level == S.SOL_SOCKET then
      if cmsg.cmsg_type == S.SCM_CREDENTIALS then
        local cred = ucred_t() -- could just cast to ucred pointer
        ffi.copy(cred, cmsg.cmsg_data, ffi.sizeof(ucred_t))
        ret.pid = cred.pid
        ret.uid = cred.uid
        ret.gid = cred.gid
      elseif cmsg.cmsg_type == S.SCM_RIGHTS then
      local fda = ffi.cast(int_pt, cmsg.cmsg_data)
      local fdc = div(cmsg.cmsg_len - cmsg_ahdr, ffi.sizeof(int1_t))
      ret.fd = {}
      for i = 1, fdc do ret.fd[i] = fd_t(fda[i - 1]) end

      end -- add other SOL_SOCKET messages
    end -- add other processing for different types
    mc, cmsg = cmsg_nxthdr(msg, mc, cmsg)
  end
  return ret
end

-- helper functions
function S.sendcred(fd, pid, uid, gid) -- only needed for root to send incorrect credentials?
  if not pid then pid = C.getpid() end
  if not uid then uid = C.getuid() end
  if not gid then gid = C.getgid() end
  local ucred = ucred_t()
  ucred.pid = pid
  ucred.uid = uid
  ucred.gid = gid
  local buf1 = buffer_t(1) -- need to send one byte
  local io = iovec_t(1)
  io[0].iov_base = buf1
  io[0].iov_len = 1
  local iolen = 1
  local usize = ffi.sizeof(ucred_t)
  local bufsize = cmsg_space(usize)
  local buflen = cmsg_len(usize)
  local buf = buffer_t(bufsize) -- this is our cmsg buffer
  local msg = msghdr_t() -- assume socket connected and so does not need address
  msg.msg_iov = io
  msg.msg_iovlen = iolen
  msg.msg_control = buf
  msg.msg_controllen = bufsize
  local mc, cmsg = cmsg_firsthdr(msg)
  cmsg.cmsg_level = S.SOL_SOCKET
  cmsg.cmsg_type = S.SCM_CREDENTIALS
  cmsg.cmsg_len = buflen
  ffi.copy(cmsg.cmsg_data, ucred, usize)
  msg.msg_controllen = cmsg.cmsg_len -- set to sum of all controllens
  return S.sendmsg(fd, msg, 0)
end

function S.sendfds(fd, ...)
  local buf1 = buffer_t(1) -- need to send one byte
  local io = iovec_t(1)
  io[0].iov_base = buf1
  io[0].iov_len = 1
  local iolen = 1
  local fds = {}
  for i, v in ipairs{...} do fds[i] = getfd(v) end
  local fa = ints_t(#fds, fds)
  local fasize = ffi.sizeof(fa)
  local bufsize = cmsg_space(fasize)
  local buflen = cmsg_len(fasize)
  local buf = buffer_t(bufsize) -- this is our cmsg buffer
  local msg = msghdr_t() -- assume socket connected and so does not need address
  msg.msg_iov = io
  msg.msg_iovlen = iolen
  msg.msg_control = buf
  msg.msg_controllen = bufsize
  local mc, cmsg = cmsg_firsthdr(msg)
  cmsg.cmsg_level = S.SOL_SOCKET
  cmsg.cmsg_type = S.SCM_RIGHTS
  cmsg.cmsg_len = buflen -- could set from a constructor
  ffi.copy(cmsg.cmsg_data, fa, fasize)
  msg.msg_controllen = cmsg.cmsg_len -- set to sum of all controllens
  return S.sendmsg(fd, msg, 0)
end

function S.nonblock(s)
  local fl, err, errno = assert(s:fcntl("F_GETFL"))
  if not fl then return nil, err, errno end
  fl, err, errno = s:fcntl("F_SETFL", bit.bor(fl, S.O_NONBLOCK))
  if not fl then return nil, err, errno end
  return true
end

function S.readfile(name, length) -- convenience for reading short files into strings, eg for /proc etc, silently ignores short reads
  local f, err, errno = S.open(name, S.O_RDONLY)
  if not f then return nil, err, errno end
  local r, err, errno = f:read(nil, length or 4096)
  if not r then return nil, err, errno end
  local t, err, errno = f:close()
  if not t then return nil, err, errno end
  return r
end

function S.writefile(name, string, mode) -- write string to named file. specify mode if want to create file, silently ignore short writes
  local f, err, errno
  if mode then f, err, errno = S.creat(name, mode) else f, err, errno = S.open(name, S.O_WRONLY) end
  if not f then return nil, err, errno end
  local n, err, errno = f:write(string)
  if not n then return nil, err, errno end
  local t, err, errno = f:close()
  if not t then return nil, err, errno end
  return true
end

function S.dirfile(name) -- return the directory entries in a file
  local fd, d, _, err, errno
  fd, err, errno = S.open(name, S.O_DIRECTORY + S.O_RDONLY)
  if err then return nil, err, errno end
  d, err, errno = fd:getdents()
  if err then return nil, err, errno end
  _, err, errno = fd:close()
  if err then return nil, err, errno end
  return d
end

-- use string types for now
local threc -- helper for returning varargs
function threc(buf, offset, t, ...) -- alignment issues, need to round up to minimum alignment
  if not t then return nil end
  if select("#", ...) == 0 then return ffi.cast(ffi.typeof(t .. "*"), buf + offset) end
  return ffi.cast(ffi.typeof(t .. "*"), buf + offset), threc(buf, offset + ffi.sizeof(t), ...)
end
function S.tbuffer(...) -- helper function for sequence of types in a buffer
  local len = 0
  for i, t in ipairs{...} do
    len = len + ffi.sizeof(ffi.typeof(t)) -- alignment issues, need to round up to minimum alignment
  end
  local buf = buffer_t(len)
  return buf, len, threc(buf, 0, ...)
end

-- methods on an fd
local fdmethods = {'nogc', 'nonblock', 'sendfds', 'sendcred',
                   'close', 'dup', 'dup2', 'dup3', 'read', 'write', 'pread', 'pwrite',
                   'lseek', 'fchdir', 'fsync', 'fdatasync', 'fstat', 'fcntl', 'fchmod',
                   'bind', 'listen', 'connect', 'accept', 'getsockname', 'getpeername',
                   'send', 'sendto', 'recv', 'recvfrom', 'readv', 'writev', 'sendmsg',
                   'recvmsg', 'setsockopt', "epoll_ctl", "epoll_wait", "sendfile", "getdents"
                   }
local fmeth = {}
for i, v in ipairs(fdmethods) do fmeth[v] = S[v] end

fd_t = ffi.metatype("struct {int fd;}", {__index = fmeth, __gc = S.close})

-- we could just return as S.timespec_t etc, not sure which is nicer?
-- think we are missing some, as not really using them
S.t = {
  fd = fd_t, timespec = timespec_t, buffer = buffer_t, stat = stat_t, -- not clear if type for fd useful
  sockaddr = sockaddr_t, sockaddr_in = sockaddr_in_t, in_addr = in_addr_t, utsname = utsname_t, sockaddr_un = sockaddr_un_t,
  iovec = iovec_t, msghdr = msghdr_t, cmsghdr = cmsghdr_t, timeval = timeval_t, sysinfo = sysinfo_t, fdset = fdset_t, off = off_t,
  sockaddr_nl = sockaddr_nl_t, nlmsghdr = nlmsghdr_t, rtgenmsg = rtgenmsg_t
}

return S


