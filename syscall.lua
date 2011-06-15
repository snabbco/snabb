local ffi = require "ffi"
local bit = require "bit"

local C = ffi.C

local rt
if pcall(function () rt = ffi.load("rt") end) then end

-- note should wrap more conditionals around stuff that might not be there
-- possibly generate more of this from C program, depending on where it differs.

local S = {} -- exported functions

local octal = function (s) return tonumber(s, 8) end

-- cleaner to read
local cast = ffi.cast
local sizeof = ffi.sizeof
local istype = ffi.istype
local arch = ffi.arch
local string = ffi.string
local typeof = ffi.typeof

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
if arch == "x86" or arch == "x64" then
  S.O_DIRECTORY = octal('0200000')
  S.O_NOFOLLOW  = octal('0400000')
  S.O_DIRECT    = octal('040000')
elseif arch == "arm" then
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

S.F_DUPFD       = 0
S.F_GETFD       = 1
S.F_SETFD       = 2
S.F_GETFL       = 3
S.F_SETFL       = 4
S.F_GETLK       = 5
S.F_SETLK       = 6
S.F_SETLKW      = 7
S.F_SETOWN      = 8
S.F_GETOWN      = 9
S.F_SETSIG      = 10
S.F_GETSIG      = 11
S.F_GETLK64     = 12      -- 64 on 32 file ops still TODO
S.F_SETLK64     = 13      -- 64 on 32 file ops still TODO
S.F_SETLKW64    = 14      -- 64 on 32 file ops still TODO
S.F_SETOWN_EX   = 15
S.F_GETOWN_EX   = 16
S.F_SETLEASE    = 1024
S.F_GETLEASE    = 1025
S.F_NOTIFY      = 1026
S.F_SETPIPE_SZ  = 1031
S.F_GETPIPE_SZ  = 1032
S.F_DUPFD_CLOEXEC = 1030

S.FD_CLOEXEC = 1

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

-- flags to `msync'.
S.MS_ASYNC       = 1
S.MS_SYNC        = 4
S.MS_INVALIDATE  = 2

-- flags for `mlockall'.
S.MCL_CURRENT    = 1
S.MCL_FUTURE     = 2

-- flags for `mremap'.
S.MREMAP_MAYMOVE = 1
S.MREMAP_FIXED   = 2

-- madvise advice parameter
S.MADV_NORMAL      = 0
S.MADV_RANDOM      = 1
S.MADV_SEQUENTIAL  = 2
S.MADV_WILLNEED    = 3
S.MADV_DONTNEED    = 4
S.MADV_REMOVE      = 9
S.MADV_DONTFORK    = 10
S.MADV_DOFORK      = 11
S.MADV_MERGEABLE   = 12
S.MADV_UNMERGEABLE = 13
S.MADV_HUGEPAGE    = 14
S.MADV_NOHUGEPAGE  = 15
S.MADV_HWPOISON    = 100

-- getpriority, setpriority flags
S.PRIO_PROCESS = 0
S.PRIO_PGRP = 1
S.PRIO_USER = 2

-- lseek
S.SEEK_SET = 0
S.SEEK_CUR = 1
S.SEEK_END = 2

-- exit
S.EXIT_SUCCESS = 0
S.EXIT_FAILURE = 1

S.SIG_ERR = -1
S.SIG_DFL =  0
S.SIG_IGN =  1
S.SIG_HOLD = 2

signals = {
"SIGHUP",
"SIGINT",
"SIGQUIT",
"SIGILL",
"SIGTRAP",
"SIGABRT",
"SIGBUS",
"SIGFPE",
"SIGKILL",
"SIGUSR1",
"SIGSEGV",
"SIGUSR2",
"SIGPIPE",
"SIGALRM",
"SIGTERM",
"SIGSTKFLT",
"SIGCHLD",
"SIGCONT",
"SIGSTOP",
"SIGTSTP",
"SIGTTIN",
"SIGTTOU",
"SIGURG",
"SIGXCPU",
"SIGXFSZ",
"SIGVTALRM",
"SIGPROF",
"SIGWINCH",
"SIGIO",
"SIGPWR",
"SIGSYS",
}

for i, v in ipairs(signals) do S[v] = i end
assert(S.SIGSYS == 31)

S.SIGIOT = 6
S.SIGUNUSED     = 31
S.SIGCLD        = S.SIGCHLD
S.SIGPOLL       = S.SIGIO

S.NSIG          = 32

-- sigprocmask
S.SIG_BLOCK     = 0
S.SIG_UNBLOCK   = 1
S.SIG_SETMASK   = 2

-- sockets
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
assert(arch ~= "ppc", "need to fix the values below for ppc")
S.SO_PASSCRED    = 16 -- below here differs for ppc!
S.SO_PEERCRED    = 17
S.SO_RCVLOWAT    = 18
S.SO_SNDLOWAT    = 19
S.SO_RCVTIMEO    = 20
S.SO_SNDTIMEO    = 21

-- Maximum queue length specifiable by listen.
S.SOMAXCONN = 128

-- shutdown
S.SHUT_RD = 0
S.SHUT_WR = 1
S.SHUT_RDWR = 2

-- waitpid 3rd arg
S.WNOHANG       = 1
S.WUNTRACED     = 2

-- waitid
S.P_ALL  = 0
S.P_PID  = 1
S.P_PGID = 2

S.WSTOPPED      = 2
S.WEXITED       = 4
S.WCONTINUED    = 8
S.WNOWAIT       = 0x01000000

-- struct siginfo, eg waitid
S.SI_ASYNCNL = -60
S.SI_TKILL = -6
S.SI_SIGIO = -5
S.SI_ASYNCIO = -4
S.SI_MESGQ = -3
S.SI_TIMER = -2
S.SI_QUEUE = -1
S.SI_USER = 0
S.SI_KERNEL = 0x80

S.ILL_ILLOPC = 1
S.ILL_ILLOPN = 2
S.ILL_ILLADR = 3
S.ILL_ILLTRP = 4
S.ILL_PRVOPC = 5
S.ILL_PRVREG = 6
S.ILL_COPROC = 7
S.ILL_BADSTK = 8

S.FPE_INTDIV = 1
S.FPE_INTOVF = 2
S.FPE_FLTDIV = 3
S.FPE_FLTOVF = 4
S.FPE_FLTUND = 5
S.FPE_FLTRES = 6
S.FPE_FLTINV = 7
S.FPE_FLTSUB = 8

S.SEGV_MAPERR = 1
S.SEGV_ACCERR = 2

S.BUS_ADRALN = 1
S.BUS_ADRERR = 2
S.BUS_OBJERR = 3

S.TRAP_BRKPT = 1
S.TRAP_TRACE = 2

S.CLD_EXITED    = 1
S.CLD_KILLED    = 2
S.CLD_DUMPED    = 3
S.CLD_TRAPPED   = 4
S.CLD_STOPPED   = 5
S.CLD_CONTINUED = 6

S.POLL_IN  = 1
S.POLL_OUT = 2
S.POLL_MSG = 3
S.POLL_ERR = 4
S.POLL_PRI = 5
S.POLL_HUP = 6

-- clocks
S.CLOCK_REALTIME = 0
S.CLOCK_MONOTONIC = 1
S.CLOCK_PROCESS_CPUTIME_ID = 2
S.CLOCK_THREAD_CPUTIME_ID = 3
S.CLOCK_MONOTONIC_RAW = 4
S.CLOCK_REALTIME_COARSE = 5
S.CLOCK_MONOTONIC_COARSE = 6

-- adjtimex
S.ADJ_OFFSET             = 0x0001
S.ADJ_FREQUENCY          = 0x0002
S.ADJ_MAXERROR           = 0x0004
S.ADJ_ESTERROR           = 0x0008
S.ADJ_STATUS             = 0x0010
S.ADJ_TIMECONST          = 0x0020
S.ADJ_TAI                = 0x0080
S.ADJ_MICRO              = 0x1000
S.ADJ_NANO               = 0x2000
S.ADJ_TICK               = 0x4000
S.ADJ_OFFSET_SINGLESHOT  = 0x8001
S.ADJ_OFFSET_SS_READ     = 0xa001

S.STA_PLL         = 0x0001
S.STA_PPSFREQ     = 0x0002
S.STA_PPSTIME     = 0x0004
S.STA_FLL         = 0x0008
S.STA_INS         = 0x0010
S.STA_DEL         = 0x0020
S.STA_UNSYNC      = 0x0040
S.STA_FREQHOLD    = 0x0080
S.STA_PPSSIGNAL   = 0x0100
S.STA_PPSJITTER   = 0x0200
S.STA_PPSWANDER   = 0x0400
S.STA_PPSERROR    = 0x0800
S.STA_CLOCKERR    = 0x1000
S.STA_NANO        = 0x2000
S.STA_MODE        = 0x4000
S.STA_CLK         = 0x8000

S.TIME_OK         = 0
S.TIME_INS        = 1
S.TIME_DEL        = 2
S.TIME_OOP        = 3
S.TIME_WAIT       = 4
S.TIME_ERROR      = 5
S.TIME_BAD        = S.TIME_ERROR

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

-- rlimit
S.RLIMIT_CPU = 0
S.RLIMIT_FSIZE = 1
S.RLIMIT_DATA = 2
S.RLIMIT_STACK = 3
S.RLIMIT_CORE = 4
S.RLIMIT_RSS = 5
S.RLIMIT_NPROC = 6
S.RLIMIT_NOFILE = 7
S.RLIMIT_OFILE = S.RLIMIT_NOFILE
S.RLIMIT_MEMLOCK = 8
S.RLIMIT_AS = 9
S.RLIMIT_LOCKS = 10
S.RLIMIT_SIGPENDING = 11
S.RLIMIT_MSGQUEUE = 12
S.RLIMIT_NICE = 13
S.RLIMIT_RTPRIO = 14
S.RLIMIT_NLIMITS = 15

-- epoll
S.EPOLL_CLOEXEC = octal("02000000")
S.EPOLL_NONBLOCK = octal("04000")

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

S.EPOLL_CTL_ADD = 1
S.EPOLL_CTL_DEL = 2
S.EPOLL_CTL_MOD = 3

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
S.NETLINK_ROUTE         = 0
S.NETLINK_UNUSED        = 1
S.NETLINK_USERSOCK      = 2
S.NETLINK_FIREWALL      = 3
S.NETLINK_INET_DIAG     = 4
S.NETLINK_NFLOG         = 5
S.NETLINK_XFRM          = 6
S.NETLINK_SELINUX       = 7
S.NETLINK_ISCSI         = 8
S.NETLINK_AUDIT         = 9
S.NETLINK_FIB_LOOKUP    = 10      
S.NETLINK_CONNECTOR     = 11
S.NETLINK_NETFILTER     = 12
S.NETLINK_IP6_FW        = 13
S.NETLINK_DNRTMSG       = 14
S.NETLINK_KOBJECT_UEVENT= 15
S.NETLINK_GENERIC       = 16
S.NETLINK_SCSITRANSPORT = 18
S.NETLINK_ECRYPTFS      = 19

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

-- generic types.
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

local nlmsglist = {
"NLMSG_NOOP", "NLMSG_ERROR", "NLMSG_DONE", "NLMSG_OVERRUN",
"RTM_NEWLINK", "RTM_DELLINK", "RTM_GETLINK", "RTM_SETLINK", "RTM_NEWADDR", "RTM_DELADDR", "RTM_GETADDR", "RTM_NEWROUTE", "RTM_DELROUTE", 
"RTM_GETROUTE", "RTM_NEWNEIGH", "RTM_DELNEIGH", "RTM_GETNEIGH", "RTM_NEWRULE", "RTM_DELRULE", "RTM_GETRULE", "RTM_NEWQDISC", 
"RTM_DELQDISC", "RTM_GETQDISC", "RTM_NEWTCLASS", "RTM_DELTCLASS", "RTM_GETTCLASS", "RTM_NEWTFILTER", "RTM_DELTFILTER", 
"RTM_GETTFILTER", "RTM_NEWACTION", "RTM_DELACTION", "RTM_GETACTION", "RTM_NEWPREFIX", "RTM_GETMULTICAST", "RTM_GETANYCAST", 
"RTM_NEWNEIGHTBL", "RTM_GETNEIGHTBL", "RTM_SETNEIGHTBL", "RTM_NEWNDUSEROPT", "RTM_NEWADDRLABEL", "RTM_DELADDRLABEL", "RTM_GETADDRLABEL",
"RTM_GETDCB", "RTM_SETDCB"
}
local nlmsgtypes = {} -- lookup table by value
for _, v in ipairs(nlmsglist) do
  assert(S[v], "message " .. v .. " should exist")
  nlmsgtypes[S[v]] = v
end

-- linux/if_link.h
S.IFLA_UNSPEC    = 0
S.IFLA_ADDRESS   = 1
S.IFLA_BROADCAST = 2
S.IFLA_IFNAME    = 3
S.IFLA_MTU       = 4
S.IFLA_LINK      = 5
S.IFLA_QDISC     = 6
S.IFLA_STATS     = 7
S.IFLA_COST      = 8
S.IFLA_PRIORITY  = 9
S.IFLA_MASTER    = 10
S.IFLA_WIRELESS  = 11
S.IFLA_PROTINFO  = 12
S.IFLA_TXQLEN    = 13
S.IFLA_MAP       = 14
S.IFLA_WEIGHT    = 15
S.IFLA_OPERSTATE = 16
S.IFLA_LINKMODE  = 17
S.IFLA_LINKINFO  = 18
S.IFLA_NET_NS_PID= 19
S.IFLA_IFALIAS   = 20
S.IFLA_NUM_VF    = 21
S.IFLA_VFINFO_LIST = 22
S.IFLA_STATS64   = 23
S.IFLA_VF_PORTS  = 24
S.IFLA_PORT_SELF = 25
S.IFLA_AF_SPEC   = 26
S.__IFLA_MAX     = 27

-- address families
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

-- eventfd
S.EFD_SEMAPHORE = 1
S.EFD_CLOEXEC = octal("02000000")
S.EFD_NONBLOCK = octal("04000")

-- mount and umount
S.MS_RDONLY = 1
S.MS_NOSUID = 2
S.MS_NODEV = 4
S.MS_NOEXEC = 8
S.MS_SYNCHRONOUS = 16
S.MS_REMOUNT = 32
S.MS_MANDLOCK = 64
S.MS_DIRSYNC = 128
S.MS_NOATIME = 1024
S.MS_NODIRATIME = 2048
S.MS_BIND = 4096
S.MS_MOVE = 8192
S.MS_REC = 16384
S.MS_SILENT = 32768
S.MS_POSIXACL = bit.lshift(1, 16)
S.MS_UNBINDABLE = bit.lshift(1, 17)
S.MS_PRIVATE = bit.lshift(1, 18)
S.MS_SLAVE = bit.lshift(1, 19)
S.MS_SHARED = bit.lshift(1, 20)
S.MS_RELATIME = bit.lshift(1, 21)
S.MS_KERNMOUNT = bit.lshift(1, 22)
S.MS_I_VERSION = bit.lshift(1, 23)
S.MS_STRICTATIME = bit.lshift(1, 24)
S.MS_ACTIVE = bit.lshift(1, 30)
S.MS_NOUSER = bit.lshift(1, 31)

S.MNT_FORCE = 1
S.MNT_DETACH = 2
S.MNT_EXPIRE = 4
S.UMOUNT_NOFOLLOW = 8

-- reboot
S.LINUX_REBOOT_CMD_RESTART      =  0x01234567
S.LINUX_REBOOT_CMD_HALT         =  0xCDEF0123
S.LINUX_REBOOT_CMD_CAD_ON       =  0x89ABCDEF
S.LINUX_REBOOT_CMD_CAD_OFF      =  0x00000000
S.LINUX_REBOOT_CMD_POWER_OFF    =  0x4321FEDC
S.LINUX_REBOOT_CMD_RESTART2     =  0xA1B2C3D4
S.LINUX_REBOOT_CMD_SW_SUSPEND   =  0xD000FCE2
S.LINUX_REBOOT_CMD_KEXEC        =  0x45584543

-- inotify
-- flags
S.IN_CLOEXEC = octal("02000000")
S.IN_NONBLOCK = octal("04000")

-- events
S.IN_ACCESS        = 0x00000001
S.IN_MODIFY        = 0x00000002
S.IN_ATTRIB        = 0x00000004
S.IN_CLOSE_WRITE   = 0x00000008
S.IN_CLOSE_NOWRITE = 0x00000010
S.IN_OPEN          = 0x00000020
S.IN_MOVED_FROM    = 0x00000040
S.IN_MOVED_TO      = 0x00000080
S.IN_CREATE        = 0x00000100
S.IN_DELETE        = 0x00000200
S.IN_DELETE_SELF   = 0x00000400
S.IN_MOVE_SELF     = 0x00000800

S.IN_UNMOUNT       = 0x00002000
S.IN_Q_OVERFLOW    = 0x00004000
S.IN_IGNORED       = 0x00008000

S.IN_CLOSE         = S.IN_CLOSE_WRITE + S.IN_CLOSE_NOWRITE
S.IN_MOVE          = S.IN_MOVED_FROM + S.IN_MOVED_TO

S.IN_ONLYDIR       = 0x01000000
S.IN_DONT_FOLLOW   = 0x02000000
S.IN_EXCL_UNLINK   = 0x04000000
S.IN_MASK_ADD      = 0x20000000
S.IN_ISDIR         = 0x40000000
S.IN_ONESHOT       = 0x80000000

S.IN_ALL_EVENTS    = S.IN_ACCESS + S.IN_MODIFY + S.IN_ATTRIB + S.IN_CLOSE_WRITE
                       + S.IN_CLOSE_NOWRITE + S.IN_OPEN + S.IN_MOVED_FROM
                       + S.IN_MOVED_TO + S.IN_CREATE + S.IN_DELETE
                       + S.IN_DELETE_SELF + S.IN_MOVE_SELF

--prctl
S.PR_SET_PDEATHSIG = 1
S.PR_GET_PDEATHSIG = 2
S.PR_GET_DUMPABLE  = 3
S.PR_SET_DUMPABLE  = 4
S.PR_GET_UNALIGN   = 5
S.PR_SET_UNALIGN   = 6
S.PR_UNALIGN_NOPRINT   = 1
S.PR_UNALIGN_SIGBUS    = 2
S.PR_GET_KEEPCAPS  = 7
S.PR_SET_KEEPCAPS  = 8
S.PR_GET_FPEMU     = 9
S.PR_SET_FPEMU     = 10
S.PR_FPEMU_NOPRINT     = 1
S.PR_FPEMU_SIGFPE      = 2
S.PR_GET_FPEXC     = 11
S.PR_SET_FPEXC     = 12
S.PR_FP_EXC_SW_ENABLE  = 0x80
S.PR_FP_EXC_DIV        = 0x010000
S.PR_FP_EXC_OVF        = 0x020000
S.PR_FP_EXC_UND        = 0x040000
S.PR_FP_EXC_RES        = 0x080000
S.PR_FP_EXC_INV        = 0x100000
S.PR_FP_EXC_DISABLED   = 0
S.PR_FP_EXC_NONRECOV   = 1
S.PR_FP_EXC_ASYNC      = 2
S.PR_FP_EXC_PRECISE    = 3
S.PR_GET_TIMING    = 13
S.PR_SET_TIMING    = 14
S.PR_TIMING_STATISTICAL= 0
S.PR_TIMING_TIMESTAMP  = 1
S.PR_SET_NAME      = 15
S.PR_GET_NAME      = 16
S.PR_GET_ENDIAN    = 19
S.PR_SET_ENDIAN    = 20
S.PR_ENDIAN_BIG         = 0
S.PR_ENDIAN_LITTLE      = 1
S.PR_ENDIAN_PPC_LITTLE  = 2
S.PR_GET_SECCOMP   = 21
S.PR_SET_SECCOMP   = 22
S.PR_CAPBSET_READ  = 23
S.PR_CAPBSET_DROP  = 24
S.PR_GET_TSC       = 25
S.PR_SET_TSC       = 26
S.PR_TSC_ENABLE         = 1
S.PR_TSC_SIGSEGV        = 2
S.PR_GET_SECUREBITS= 27
S.PR_SET_SECUREBITS= 28
S.PR_SET_TIMERSLACK= 29
S.PR_GET_TIMERSLACK= 30
S.PR_TASK_PERF_EVENTS_DISABLE=31
S.PR_TASK_PERF_EVENTS_ENABLE=32
S.PR_MCE_KILL      = 33
S.PR_MCE_KILL_CLEAR     = 0
S.PR_MCE_KILL_SET       = 1
S.PR_MCE_KILL_LATE         = 0
S.PR_MCE_KILL_EARLY        = 1
S.PR_MCE_KILL_DEFAULT      = 2
S.PR_MCE_KILL_GET  = 34
S.PR_SET_PTRACER   = 0x59616d61 -- Ubuntu extension

-- syscalls, filling in as used at the minute
-- note ARM EABI same syscall numbers as x86, not tested on non eabi arm, will need offset added
if ffi.abi("32bit") and (arch == "x86" or (arch == "arm" and ffi.abi("eabi"))) then
  S.SYS_getdents = 141
elseif ffi.abi("64bit") and arch == "x64" then
  S.SYS_getdents = 78
end

-- constants
local HOST_NAME_MAX = 64 -- Linux. should we export?

-- errors. In a subtable unlike other constants
S.E = {}

S.E.EPERM          =  1
S.E.ENOENT         =  2
S.E.ESRCH          =  3
S.E.EINTR          =  4
S.E.EIO            =  5
S.E.ENXIO          =  6
S.E.E2BIG          =  7
S.E.ENOEXEC        =  8
S.E.EBADF          =  9
S.E.ECHILD         = 10
S.E.EAGAIN         = 11
S.E.ENOMEM         = 12
S.E.EACCES         = 13
S.E.EFAULT         = 14
S.E.ENOTBLK        = 15
S.E.EBUSY          = 16
S.E.EEXIST         = 17
S.E.EXDEV          = 18
S.E.ENODEV         = 19
S.E.ENOTDIR        = 20
S.E.EISDIR         = 21
S.E.EINVAL         = 22
S.E.ENFILE         = 23
S.E.EMFILE         = 24
S.E.ENOTTY         = 25
S.E.ETXTBSY        = 26
S.E.EFBIG          = 27
S.E.ENOSPC         = 28
S.E.ESPIPE         = 29
S.E.EROFS          = 30
S.E.EMLINK         = 31
S.E.EPIPE          = 32
S.E.EDOM           = 33
S.E.ERANGE         = 34
S.E.EDEADLK        = 35
S.E.ENAMETOOLONG   = 36
S.E.ENOLCK         = 37
S.E.ENOSYS         = 38
S.E.ENOTEMPTY      = 39
S.E.ELOOP          = 40
S.E.EWOULDBLOCK    = S.E.EAGAIN
S.E.ENOMSG         = 42
S.E.EIDRM          = 43
S.E.ECHRNG         = 44
S.E.EL2NSYNC       = 45
S.E.EL3HLT         = 46
S.E.EL3RST         = 47
S.E.ELNRNG         = 48
S.E.EUNATCH        = 49
S.E.ENOCSI         = 50
S.E.EL2HLT         = 51
S.E.EBADE          = 52
S.E.EBADR          = 53
S.E.EXFULL         = 54
S.E.ENOANO         = 55
S.E.EBADRQC        = 56
S.E.EBADSLT        = 57
S.E.EDEADLOCK      = S.E.EDEADLK
S.E.EBFONT         = 59
S.E.ENOSTR         = 60
S.E.ENODATA        = 61
S.E.ETIME          = 62
S.E.ENOSR          = 63
S.E.ENONET         = 64
S.E.ENOPKG         = 65
S.E.EREMOTE        = 66
S.E.ENOLINK        = 67
S.E.EADV           = 68
S.E.ESRMNT         = 69
S.E.ECOMM          = 70
S.E.EPROTO         = 71
S.E.EMULTIHOP      = 72
S.E.EDOTDOT        = 73
S.E.EBADMSG        = 74
S.E.EOVERFLOW      = 75
S.E.ENOTUNIQ       = 76
S.E.EBADFD         = 77
S.E.EREMCHG        = 78
S.E.ELIBACC        = 79
S.E.ELIBBAD        = 80
S.E.ELIBSCN        = 81
S.E.ELIBMAX        = 82
S.E.ELIBEXEC       = 83
S.E.EILSEQ         = 84
S.E.ERESTART       = 85
S.E.ESTRPIPE       = 86
S.E.EUSERS         = 87
S.E.ENOTSOCK       = 88
S.E.EDESTADDRREQ   = 89
S.E.EMSGSIZE       = 90
S.E.EPROTOTYPE     = 91
S.E.ENOPROTOOPT    = 92
S.E.EPROTONOSUPPORT= 93
S.E.ESOCKTNOSUPPORT= 94
S.E.EOPNOTSUPP     = 95
S.E.EPFNOSUPPORT   = 96
S.E.EAFNOSUPPORT   = 97
S.E.EADDRINUSE     = 98
S.E.EADDRNOTAVAIL  = 99
S.E.ENETDOWN       = 100
S.E.ENETUNREACH    = 101
S.E.ENETRESET      = 102
S.E.ECONNABORTED   = 103
S.E.ECONNRESET     = 104
S.E.ENOBUFS        = 105
S.E.EISCONN        = 106
S.E.ENOTCONN       = 107
S.E.ESHUTDOWN      = 108
S.E.ETOOMANYREFS   = 109
S.E.ETIMEDOUT      = 110
S.E.ECONNREFUSED   = 111
S.E.EHOSTDOWN      = 112
S.E.EHOSTUNREACH   = 113
S.E.EINPROGRESS    = 115
S.E.ESTALE         = 116
S.E.EUCLEAN        = 117
S.E.ENOTNAM        = 118
S.E.ENAVAIL        = 119
S.E.EISNAM         = 120
S.E.EREMOTEIO      = 121
S.E.EDQUOT         = 122
S.E.ENOMEDIUM      = 123
S.E.EMEDIUMTYPE    = 124
S.E.ECANCELED      = 125
S.E.ENOKEY         = 126
S.E.EKEYEXPIRED    = 127
S.E.EKEYREVOKED    = 128
S.E.EKEYREJECTED   = 129
S.E.EOWNERDEAD     = 130
S.E.ENOTRECOVERABLE= 131
S.E.ERFKILL        = 132

function S.strerror(errno) return string(C.strerror(errno)) end

local emt = {__tostring = function(e) return S.strerror(e.errno) end}

local errsyms = {}

for i, v in pairs(S.E) do
  errsyms[v] = i
end

local mkerror = function(errno)
  local sym = errsyms[errno]
  local e = {errno = errno, sym = sym}
  e[sym] = true
  e[sym:sub(2):lower()] = true
  setmetatable(e, emt)
  return e
end

-- misc
function S.nogc(d) ffi.gc(d, nil) end
local errorret, retint, retbool, retptr, retfd, getfd

-- standard error return
function errorret()
  return nil, mkerror(ffi.errno())
end

function retint(ret)
  if ret == -1 then return errorret() end
  return ret
end

-- used for no return value, return true for use of assert
function retbool(ret)
  if ret == -1 then return errorret() end
  return true
end

-- used for pointer returns, -1 is failure, optional gc function
function retptr(ret, f)
  if cast("long", ret) == -1 then return errorret() end
  if f then return ffi.gc(ret, f) end
  return ret
end

local fd_t -- type for a file descriptor

-- char buffer type
local buffer_t = typeof("char[?]")

S.string = string -- convenience for converting buffers
S.sizeof = sizeof -- convenience so user need not require ffi
S.cast = cast -- convenience so user need not require ffi

--get fd from standard string, integer, or cdata
function getfd(fd)
  if type(fd) == 'number' then return fd end
  if istype(fd_t, fd) then return fd.fd end
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
typedef uint32_t id_t;
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
typedef long blksize_t;
typedef long blkcnt_t;
typedef long clock_t;
typedef unsigned long ino_t;
typedef unsigned long nlink_t;
typedef unsigned long rlim_t;

// should be a word, but we use 32 bits as bitops are signed 32 bit in LuaJIT at the moment
typedef int32_t fd_mask;

typedef struct {
  int32_t val[1024 / (8 * sizeof (int32_t))];
} sigset_t;

typedef int idtype_t; /* defined as enum */

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
struct rlimit {
  rlim_t rlim_cur;
  rlim_t rlim_max;
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
struct timex {
  unsigned int modes;
  long int offset;
  long int freq;
  long int maxerror;
  long int esterror;
  int status;
  long int constant;
  long int precision;
  long int tolerance;
  struct timeval time;
  long int tick;

  long int ppsfreq;
  long int jitter;
  int shift;
  long int stabil;
  long int jitcnt;
  long int calcnt;
  long int errcnt;
  long int stbcnt;

  int tai;

  int  :32; int  :32; int  :32; int  :32;
  int  :32; int  :32; int  :32; int  :32;
  int  :32; int  :32; int  :32;
};
typedef union sigval {
  int sival_int;
  void *sival_ptr;
} sigval_t;
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
struct ifinfomsg {
  unsigned char   ifi_family;
  unsigned char   __ifi_pad;
  unsigned short  ifi_type;
  int             ifi_index;
  unsigned        ifi_flags;
  unsigned        ifi_change;
};
struct rtattr {
  unsigned short  rta_len;
  unsigned short  rta_type;
};
struct inotify_event {
  int wd;
  uint32_t mask;
  uint32_t cookie;
  uint32_t len;
  char name[?];
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
]]

-- Linux struct siginfo padding depends on architecture
if ffi.abi("64bit") then
ffi.cdef[[
static const int SI_MAX_SIZE = 128;
static const int SI_PAD_SIZE = (SI_MAX_SIZE / sizeof (int)) - 4;
]]
else
ffi.cdef[[
static const int SI_MAX_SIZE = 128;
static const int SI_PAD_SIZE = (SI_MAX_SIZE / sizeof (int)) - 3;
]]
end

-- note we might make a metatype with the short names (eg si_pid) defined in bits/siginfo.h TODO
ffi.cdef[[
typedef struct siginfo {
  int si_signo;
  int si_errno;
  int si_code;

  union {
    int _pad[SI_PAD_SIZE];

    struct {
      pid_t si_pid;
      uid_t si_uid;
    } kill;

    struct {
      int si_tid;
      int si_overrun;
      sigval_t si_sigval;
    } timer;

    struct {
      pid_t si_pid;
      uid_t si_uid;
      sigval_t si_sigval;
    } rt;

    struct {
      pid_t si_pid;
      uid_t si_uid;
      int si_status;
      clock_t si_utime;
      clock_t si_stime;
    } sigchld;

    struct {
      void *si_addr;
    } sigfault;

    struct {
      long int si_band;   /* Band event for SIGPOLL.  */
       int si_fd;
    } sigpoll;
  } sifields;
} siginfo_t;
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

-- not currently used, but may switch
if arch == 'x86' then
ffi.cdef[[
struct linux_stat {
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
else -- all architectures except x86 the same
ffi.cdef [[
struct linux_stat {
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
int symlink(const char *oldpath, const char *newpath);
int chroot(const char *path);
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
pid_t getsid(pid_t pid);
pid_t setsid(void);
pid_t fork(void);
int execve(const char *filename, const char *argv[], const char *envp[]);
pid_t wait(int *status);
pid_t waitpid(pid_t pid, int *status, int options);
int waitid(idtype_t idtype, id_t id, siginfo_t *infop, int options);
void _exit(int status);
int signal(int signum, int handler); /* although deprecated, just using to set SIG_ values */
int kill(pid_t pid, int sig);
int gettimeofday(struct timeval *tv, void *tz);   /* not even defining struct timezone */
int settimeofday(const struct timeval *tv, const void *tz);
time_t time(time_t *t);
int clock_getres(clockid_t clk_id, struct timespec *res);
int clock_gettime(clockid_t clk_id, struct timespec *tp);
int clock_settime(clockid_t clk_id, const struct timespec *tp);
unsigned int alarm(unsigned int seconds);
int sysinfo(struct sysinfo *info);
void sync(void);
int nice(int inc);
int getpriority(int which, int who);
int setpriority(int which, int who, int prio);
int prctl(int option, unsigned long arg2, unsigned long arg3, unsigned long arg4, unsigned long arg5);
int sigprocmask(int how, const sigset_t *set, sigset_t *oldset);
int sigpending(sigset_t *set);
int sigsuspend(const sigset_t *mask);

ssize_t read(int fd, void *buf, size_t count);
ssize_t write(int fd, const void *buf, size_t count);
ssize_t pread(int fd, void *buf, size_t count, off_t offset);
ssize_t pwrite(int fd, const void *buf, size_t count, off_t offset);
off_t lseek(int fd, off_t offset, int whence); 
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
int epoll_ctl(int epfd, int op, int fd, struct epoll_event *event);
int epoll_wait(int epfd, struct epoll_event *events, int maxevents, int timeout);
ssize_t sendfile(int out_fd, int in_fd, off_t *offset, size_t count);
int eventfd(unsigned int initval, int flags);
int reboot(int cmd);
int klogctl(int type, char *bufp, int len);
int inotify_init1(int flags);
int inotify_add_watch(int fd, const char *pathname, uint32_t mask);
int inotify_rm_watch(int fd, uint32_t wd);
int adjtimex(struct timex *buf);

int dup(int oldfd);
int dup2(int oldfd, int newfd);
int dup3(int oldfd, int newfd, int flags);
int fchdir(int fd);
int fsync(int fd);
int fdatasync(int fd);
int fcntl(int fd, int cmd, long arg); /* arg can be a pointer though */
int fchmod(int fd, mode_t mode);
int truncate(const char *path, off_t length);
int ftruncate(int fd, off_t length);
int pause(void);
int getrlimit(int resource, struct rlimit *rlim);
int setrlimit(int resource, const struct rlimit *rlim);

int socket(int domain, int type, int protocol);
int socketpair(int domain, int type, int protocol, int sv[2]);
int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
int listen(int sockfd, int backlog);
int connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
int accept(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
int accept4(int sockfd, struct sockaddr *addr, socklen_t *addrlen, int flags);
int getsockname(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
int getpeername(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
int shutdown(int sockfd, int how);

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);
int munmap(void *addr, size_t length);
int msync(void *addr, size_t length, int flags);
int mlock(const void *addr, size_t len);
int munlock(const void *addr, size_t len);
int mlockall(int flags);
int munlockall(void);
void *mremap(void *old_address, size_t old_size, size_t new_size, int flags, void *new_address);
int madvise(void *addr, size_t length, int advice);

int pipe(int pipefd[2]);
int pipe2(int pipefd[2], int flags);
int mount(const char *source, const char *target, const char *filesystemtype, unsigned long mountflags, const void *data);
int umount(const char *target);
int umount2(const char *target, int flags);

int access(const char *pathname, int mode);
char *getcwd(char *buf, size_t size);

int nanosleep(const struct timespec *req, struct timespec *rem);

int syscall(int number, ...);

int ioctl(int d, int request, void *argp); /* void* easiest here */

// stat glibc internal functions
int __fxstat(int ver, int fd, struct stat *buf);
int __xstat(int ver, const char *path, struct stat *buf);
int __lxstat(int ver, const char *path, struct stat *buf);
// real stat functions, might not exist
int stat(const char *path, struct stat *buf);
int fstat(int fd, struct stat *buf);
int lstat(const char *path, struct stat *buf);

// functions from libc ie man 3 not man 2
void exit(int status);
int inet_aton(const char *cp, struct in_addr *inp);
char *inet_ntoa(struct in_addr in);
int inet_pton(int af, const char *src, void *dst);
const char *inet_ntop(int af, const void *src, char *dst, socklen_t size);

// functions from libc that could be exported as a convenience, used internally
void *calloc(size_t nmemb, size_t size);
void *malloc(size_t size);
void free(void *ptr);
void *realloc(void *ptr, size_t size);
char *strerror(int);
// env. dont support putenv, as does not copy which is an issue
extern char **environ;
int setenv(const char *name, const char *value, int overwrite);
int unsetenv(const char *name);
int clearenv(void);
char *getenv(const char *name);
]]

-- glibc does not have a stat symbol, has its own struct stat and way of calling
local use_gnu_stat
if pcall(function () local t = C.stat end) then use_gnu_stat = false else use_gnu_stat = true end

-- Lua type constructors corresponding to defined types
local timespec_t = typeof("struct timespec")
local timeval_t = typeof("struct timeval")
local sockaddr_t = typeof("struct sockaddr")
local sockaddr_storage_t = typeof("struct sockaddr_storage")
local sa_family_t = typeof("sa_family_t")
local sockaddr_in_t = typeof("struct sockaddr_in")
local sockaddr_in6_t = typeof("struct sockaddr_in6")
local in_addr_t = typeof("struct in_addr")
local in6_addr_t = typeof("struct in6_addr")
local sockaddr_un_t = typeof("struct sockaddr_un")
local sockaddr_nl_t = typeof("struct sockaddr_nl")
local iovec_t = typeof("struct iovec[?]")
local msghdr_t = typeof("struct msghdr")
local cmsghdr_t = typeof("struct cmsghdr")
local ucred_t = typeof("struct ucred")
local sysinfo_t = typeof("struct sysinfo")
local fdset_t = typeof("fd_set")
local fdmask_t = typeof("fd_mask")
local stat_t = typeof("struct stat")
local epoll_event_t = typeof("struct epoll_event")
local epoll_events_t = typeof("struct epoll_event[?]")
local off_t = typeof("off_t")
local nlmsghdr_t = typeof("struct nlmsghdr")
local nlmsghdr_pt = typeof("struct nlmsghdr *")
local rtgenmsg_t = typeof("struct rtgenmsg")
local ifinfomsg_t = typeof("struct ifinfomsg")
local ifinfomsg_pt = typeof("struct ifinfomsg *")
local rtattr_t = typeof("struct rtattr")
local rtattr_pt = typeof("struct rtattr *")
local timex_t = typeof("struct timex")
local utsname_t = typeof("struct utsname")
local sigset_t = typeof("sigset_t")
local rlimit_t = typeof("struct rlimit")

S.RLIM_INFINITY = cast("rlim_t", -1)

-- siginfo needs some metamethods
local siginfo_get = {
  si_pid     = function(s) return s.sifields.kill.si_pid end,
  si_uid     = function(s) return s.sifields.kill.si_uid end,
  si_timerid = function(s) return s.sifields.timer.si_tid end,
  si_overrun = function(s) return s.sifields.timer.si_overrun end,
  si_status  = function(s) return s.sifields.sigchld.si_status end,
  si_utime   = function(s) return s.sifields.sigchld.si_utime end,
  si_stime   = function(s) return s.sifields.sigchld.si_stime end,
  si_value   = function(s) return s.sifields.rt.si_sigval end,
  si_int     = function(s) return s.sifields.rt.si_sigval.sival_int end,
  si_ptr     = function(s) return s.sifields.rt.si_sigval.sival_ptr end,
  si_addr    = function(s) return s.sifields.sigfault.si_addr end,
  si_band    = function(s) return s.sifields.sigpoll.si_band end,
  si_fd      = function(s) return s.sifields.sigpoll.si_fd end,
}

local siginfo_set = {
  si_pid     = function(s, v) s.sifields.kill.si_pid = v end,
  si_uid     = function(s, v) s.sifields.kill.si_uid = v end,
  si_timerid = function(s, v) s.sifields.timer.si_tid = v end,
  si_overrun = function(s, v) s.sifields.timer.si_overrun = v end,
  si_status  = function(s, v) s.sifields.sigchld.si_status = v end,
  si_utime   = function(s, v) s.sifields.sigchld.si_utime = v end,
  si_stime   = function(s, v) s.sifields.sigchld.si_stime = v end,
  si_value   = function(s, v) s.sifields.rt.si_sigval = v end,
  si_int     = function(s, v) s.sifields.rt.si_sigval.sival_int = v end,
  si_ptr     = function(s, v) s.sifields.rt.si_sigval.sival_ptr = v end,
  si_addr    = function(s, v) s.sifields.sigfault.si_addr = v end,
  si_band    = function(s, v) s.sifields.sigpoll.si_band = v end,
  si_fd      = function(s, v) s.sifields.sigpoll.si_fd = v end,
}
local siginfo_t = ffi.metatype("struct siginfo",{
  __index = function(t, k) if siginfo_get[k] then return siginfo_get[k](t) end end,
  __newindex = function(t, k, v) if siginfo_set[k] then siginfo_set[k](t, v) end end,
})

--[[ -- used to generate tests, will refactor into test code later
print("eq (sizeof(struct timespec), " .. sizeof(timespec_t) .. ");")
print("eq (sizeof(struct timeval), " .. sizeof(timeval_t) .. ");")
print("eq (sizeof(struct sockaddr_storage), " .. sizeof(sockaddr_storage_t) .. ");")
print("eq (sizeof(struct sockaddr_in), " .. sizeof(sockaddr_in_t) .. ");")
print("eq (sizeof(struct sockaddr_in6), " .. sizeof(sockaddr_in6_t) .. ");")
print("eq (sizeof(struct sockaddr_un), " .. sizeof(sockaddr_un_t) .. ");")
print("eq (sizeof(struct iovec), " .. sizeof(iovec_t(1)) .. ");")
print("eq (sizeof(struct msghdr), " .. sizeof(msghdr_t) .. ");")
print("eq (sizeof(struct cmsghdr), " .. sizeof(cmsghdr_t(0)) .. ");")
print("eq (sizeof(struct sysinfo), " .. sizeof(sysinfo_t) .. ");")
]]
--print(sizeof("struct stat"))
--print(sizeof("struct gstat"))

local int_t = typeof("int")
local uint_t = typeof("unsigned int")
local off1_t = typeof("off_t[1]") -- used to pass off_t to sendfile etc
local int1_t = typeof("int[1]") -- used to pass pointer to int
local int2_t = typeof("int[2]") -- pair of ints, eg for pipe
local ints_t = typeof("int[?]") -- array of ints
local int64_t = typeof("int64_t")
local uint64_t = typeof("uint64_t")
local int32_pt = typeof("int32_t *")
local int64_1t = typeof("int64_t[1]")
local uint64_1t = typeof("uint64_t[1]")
local socklen1_t = typeof("socklen_t[1]")
local ulong_t = typeof("unsigned long")

local string_array_t = typeof("const char *[?]")

-- need these for casts
local sockaddr_pt = typeof("struct sockaddr *")
local cmsghdr_pt = typeof("struct cmsghdr *")
local uchar_pt = typeof("unsigned char *")
local int_pt = typeof("int *")
local linux_dirent_pt = typeof("struct linux_dirent *")
local inotify_event_pt = typeof("struct inotify_event *")
local inotify_event_t = typeof("struct inotify_event")

local pointersize = sizeof("char *")

assert(sizeof(sockaddr_t) == sizeof(sockaddr_in_t)) -- inet socket addresses should be padded to same as sockaddr
assert(sizeof(sockaddr_storage_t) == 128) -- this is the required size in Linux
assert(sizeof(sockaddr_storage_t) >= sizeof(sockaddr_t))
assert(sizeof(sockaddr_storage_t) >= sizeof(sockaddr_in_t))
assert(sizeof(sockaddr_storage_t) >= sizeof(sockaddr_in6_t))
assert(sizeof(sockaddr_storage_t) >= sizeof(sockaddr_un_t))
assert(sizeof(sockaddr_storage_t) >= sizeof(sockaddr_nl_t))

-- misc
local div = function(a, b) return math.floor(tonumber(a) / tonumber(b)) end -- would be nicer if replaced with shifts, as only powers of 2

local split, trim
function split(delimiter, text)
  if delimiter == "" then return text end
  local list = {}
  local pos = 1
  while true do
    local first, last = text:find(delimiter, pos)
    if first then
      list[#list + 1] = text:sub(pos, first - 1)
      pos = last + 1
    else
      list[#list + 1] = text:sub(pos)
      break
    end
  end
  return list
end
function trim (s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end
-- take a bunch of flags in a string and return a number
-- note if using with 64 bit flags will have to change to use a 64 bit number, currently assumes 32 bit, as uses bitops
local stringflag, stringflags
function stringflags(str, prefix, prefix2) -- allows multiple comma sep flags that are ORed
  if not str then return 0 end
  if type(str) ~= "string" then return str end
  local f = 0
  local a = split(",", str)
  local ts, s, val
  for i, v in ipairs(a) do
    ts = trim(v)
    s = ts
    if s:sub(1, #prefix) ~= prefix then s = prefix .. s end -- prefix optional
    val = S[s:upper()]
    if prefix2 and not val then
      s = ts
      if s:sub(1, #prefix2) ~= prefix2 then s = prefix2 .. s end -- prefix optional
      val = S[s:upper()]
    end
    if not val then error("invalid flag: " .. v) end -- don't use this format if you don't want exceptions, better than silent ignore
    f = bit.bor(f, val) -- note this forces to signed 32 bit, ok for most flags, but might get sign extension on long
  end
  return f
end
function stringflag(str, prefix) -- single value only
  if not str then return 0 end
  if type(str) ~= "string" then return str end
  if #str == 0 then return 0 end
  local s = trim(str)
  if s:sub(1, #prefix) ~= prefix then s = prefix .. s end -- prefix optional
  local val = S[s:upper()]
  if not val then error("invalid flag: " .. s) end -- don't use this format if you don't want exceptions, better than silent ignore
  return val
end

-- reverse flag operations
local getflag, getflags -- should be used elsewhere
function getflags(e, prefix, values, r)
  if not r then r = {} end
  for _, f in ipairs(values) do
    if bit.band(e, S[f]) ~= 0 then
      r[f] = true
      r[f:lower()] = true
      r[f:sub(#prefix + 1):lower()] = true -- ie set r.in, r.out etc as well
    end
  end
  return r
end

function getflag(e, prefix, values)
  local r= {}
  for _, f in ipairs(values) do
    if e == S[f] then
      r[f] = true
      r[f:lower()] = true
      r[f:sub(#prefix + 1):lower()] = true -- ie set r.in, r.out etc as well
    end
  end
  return r
end

-- endian conversion
if ffi.abi("be") then -- nothing to do
  function S.htonl(b) return b end
else
  function S.htonl(b)
  if istype(in_addr_t, b) then return in_addr_t(bit.bswap(b.s_addr)) end -- not sure we need this, actually not using this function
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
  return sockaddr_in_t(S.AF_INET, S.htons(port), addr)
end
function S.sockaddr_in6(port, addr)
  if type(addr) == 'string' then addr = S.inet_pton(S.AF_INET6, addr) end
  if not addr then return nil end
  local sa = sockaddr_in6_t()
  sa.sin6_family = S.AF_INET6
  sa.sin6_port = S.htons(port)
  ffi.copy(sa.sin6_addr, addr, sizeof(in6_addr_t))
  return sa
end
function S.sockaddr_un() -- actually, not using this, not sure it is useful for unix sockets
  local addr = sockaddr_in_t()
  addr.sun_family = S.AF_UNIX
  return addr
end
function S.sockaddr_nl(pid, groups)
  local addr = sockaddr_nl_t()
  addr.nl_family = S.AF_NETLINK
  if pid then addr.nl_pid = pid end -- optional, kernel will set
  if groups then addr.nl_groups = groups end
  return addr
end

-- map from socket family to data type
local socket_type, address_type = {}, {}
-- AF_UNSPEC
socket_type[S.AF_LOCAL] = sockaddr_un_t
socket_type[S.AF_INET] = sockaddr_in_t
address_type[S.AF_INET] = in_addr_t
--  AF_AX25
--  AF_IPX
--  AF_APPLETALK
--  AF_NETROM
--  AF_BRIDGE
--  AF_ATMPVC
--  AF_X25
socket_type[S.AF_INET6] = sockaddr_in6_t
address_type[S.AF_INET6] = in6_addr_t
--  AF_ROSE
--  AF_DECnet
--  AF_NETBEUI
--  AF_SECURITY
--  AF_KEY
socket_type[S.AF_NETLINK] = sockaddr_nl_t
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

-- helper function to make setting addrlen optional
local getaddrlen
function getaddrlen(addr, addrlen)
  if not addr then return 0 end
  if addrlen == nil then
    if istype(sockaddr_t, addr) then return sizeof(sockaddr_t) end
    if istype(sockaddr_in_t, addr) then return sizeof(sockaddr_in_t) end
    if istype(sockaddr_in6_t, addr) then return sizeof(sockaddr_in6_t) end
    if istype(sockaddr_nl_t, addr) then return sizeof(sockaddr_nl_t) end
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
    if istype(sockaddr_un_t, addr) then
      local namelen = addrlen - sizeof(sa_family_t)
      if namelen > 0 then
        rets.name = string(addr.sun_path, namelen)
        if addr.sun_path[0] == 0 then rets.abstract = true end -- Linux only
      end
    elseif istype(sockaddr_in_t, addr) then
      rets.port = S.ntohs(addr.sin_port)
      rets.ipv4 = addr.sin_addr
    elseif istype(sockaddr_nl_t, addr) then
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

function S.inet_ntoa(addr) return string(C.inet_ntoa(addr)) end

local INET6_ADDRSTRLEN = 46
local INET_ADDRSTRLEN = 16

function S.inet_ntop(af, src)
  af = stringflag(af, "AF_")
  local len = INET6_ADDRSTRLEN -- could shorten for ipv4
  local dst = buffer_t(len)
  local ret = C.inet_ntop(af, src, dst, len)
  if ret == nil then return errorret() end
  return string(dst)
end

function S.inet_pton(af, src)
  af = stringflag(af, "AF_")
  local addr = address_type[af]()
  local ret = C.inet_pton(af, src, addr)
  if ret == -1 then return errorret() end
  if ret == 0 then return nil end -- maybe return string
  return addr
end

-- constants
S.INADDR_ANY = in_addr_t()
S.INADDR_LOOPBACK = S.inet_aton("127.0.0.1")
S.INADDR_BROADCAST = S.inet_aton("255.255.255.255")
-- ipv6 versions
S.in6addr_any = in6_addr_t()
S.in6addr_loopback = S.inet_pton(S.AF_INET6, "::1")

-- main definitions start here
function S.open(pathname, flags, mode) return retfd(C.open(pathname, stringflags(flags, "O_"), stringflags(mode, "S_"))) end

function S.dup(oldfd, newfd, flags)
  if newfd == nil then return retfd(C.dup(getfd(oldfd))) end
  if flags == nil then return retfd(C.dup2(getfd(oldfd), getfd(newfd))) end
  return retfd(C.dup3(getfd(oldfd), getfd(newfd), flags))
end

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
  if ret == -1 then
    local errno = ffi.errno()
    if istype(fd_t, fd) and errno ~= S.E.INTR then -- file will still be open if interrupted
      ffi.gc(fd, nil)
      fd.fd = -1 -- make sure cannot accidentally close this fd object again
    end
    return errorret()
  end
  if istype(fd_t, fd) then
    ffi.gc(fd, nil)
    fd.fd = -1 -- make sure cannot accidentally close this fd object again
  end
  return true
end

function S.creat(pathname, mode) return retfd(C.creat(pathname, stringflags(mode, "S_"))) end
function S.unlink(pathname) return retbool(C.unlink(pathname)) end
function S.access(pathname, mode) return retbool(C.access(pathname, mode)) end
function S.chdir(path) return retbool(C.chdir(path)) end
function S.mkdir(path, mode) return retbool(C.mkdir(path, stringflags(mode, "S_"))) end
function S.rmdir(path) return retbool(C.rmdir(path)) end
function S.unlink(pathname) return retbool(C.unlink(pathname)) end
function S.acct(filename) return retbool(C.acct(filename)) end
function S.chmod(path, mode) return retbool(C.chmod(path, stringflags(mode, "S_"))) end
function S.link(oldpath, newpath) return retbool(C.link(oldpath, newpath)) end
function S.symlink(oldpath, newpath) return retbool(C.symlink(oldpath, newpath)) end
function S.truncate(path, length) return retbool(C.truncate(path, length)) end
function S.ftruncate(fd, length) return retbool(C.ftruncate(getfd(fd), length)) end
function S.pause() return retbool(C.pause()) end

local retinte
function retinte(f, ...) -- for cases where need to explicitly set and check errno, ie signed int return
  ffi.errno(0)
  local ret = f(...)
  if ffi.errno() ~= 0 then return errorret() end
  return ret
end

function S.nice(inc) return retinte(C.nice, inc) end
-- NB glibc is shifting these values from what strace shows, as per man page, kernel adds 20 to make these values positive...
-- might cause issues with other C libraries in which case may shift to using system call
function S.getpriority(which, who) return retinte(C.getpriority, stringflags(which, "PRIO_"), who or 0) end
function S.setpriority(which, who, prio) return retinte(C.setpriority, stringflags(which, "PRIO_"), who or 0, prio) end

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
  local ret = C.syscall(stringflag(num, "SYS_"), a, b, c, d, e, f)
  if ret == -1 then return errorret() end
  return ret
end

-- do not export?
function S.ioctl(d, request, argp)
  local ret = C.ioctl(d, request, argp)
  if ret == -1 then return errorret() end
  -- some different return types may need to be handled
  return true
end

function S.reboot(cmd) return retbool(C.reboot(stringflag(cmd, "LINUX_REBOOT_CMD_"))) end

function S.getdents(fd, buf, size, noiter) -- default behaviour is to iterate over whole directory, use noiter if you have very large directories
  if not buf then
    size = size or 4096
    buf = buffer_t(size)
  end
  local d = {}
  local ret
  repeat
    ret = C.syscall(S.SYS_getdents, uint_t(getfd(fd)), buf, uint_t(size))
    if ret == -1 then return errorret() end
    local i = 0
    while i < ret do
      local dp = cast(linux_dirent_pt, buf + i)
      local t = buf[i + dp.d_reclen - 1]
      local dd = getflag(t, "DT_", {"DT_UNKNOWN", "DT_FIFO", "DT_CHR", "DT_DIR", "DT_BLK", "DT_REG", "DT_LNK", "DT_SOCK", "DT_WHT"})
      dd.inode = tonumber(dp.d_ino)
      dd.offset = tonumber(dp.d_off)
      d[string(dp.d_name)] = dd
      i = i + dp.d_reclen
    end
  until noiter or ret == 0
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
function S.waitid(idtype, id, options, infop) -- note order of args, as usually dont supply infop
  if not infop then infop = siginfo_t() end
  infop.si_pid = 0 -- see notes on man page
  local ret = C.waitid(stringflag(idtype, "P_"), id or 0, infop, stringflags(options, "W"))
  if ret == -1 then return errorret() end
  return infop -- return table here?
end

function S._exit(status) C._exit(stringflag(status, "EXIT_")) end
function S.exit(status) C.exit(stringflag(status, "EXIT_")) end

function S.read(fd, buf, count)
  if buf then return retint(C.read(getfd(fd), buf, count)) end -- user supplied a buffer, standard usage
  local buf = buffer_t(count)
  local ret = C.read(getfd(fd), buf, count)
  if ret == -1 then return errorret() end
  return string(buf, ret) -- user gets a string back, can get length from #string
end

function S.write(fd, buf, count) return retint(C.write(getfd(fd), buf, count or #buf)) end
function S.pread(fd, buf, count, offset) return retint(C.pread(getfd(fd), buf, count, offset)) end
function S.pwrite(fd, buf, count, offset) return retint(C.pwrite(getfd(fd), buf, count, offset)) end
function S.lseek(fd, offset, whence) return retint(C.lseek(getfd(fd), offset, stringflag(whence, "SEEK_"))) end
function S.send(fd, buf, count, flags) return retint(C.send(getfd(fd), buf, count or #buf, stringflags(flags, "MSG_"))) end
function S.sendto(fd, buf, count, flags, addr, addrlen)
  return retint(C.sendto(getfd(fd), buf, count or #buf, stringflags(flags, "MSG_"), cast(sockaddr_pt, addr), getaddrlen(addr)))
end
function S.readv(fd, iov, iovcnt) return retint(C.readv(getfd(fd), iov, iovcnt)) end
function S.writev(fd, iov, iovcnt) return retint(C.writev(getfd(fd), iov, iovcnt)) end

function S.recv(fd, buf, count, flags) return retint(C.recv(getfd(fd), buf, count or #buf, stringflags(flags, "MSG_"))) end
function S.recvfrom(fd, buf, count, flags)
  local ss = sockaddr_storage_t()
  local addrlen = int1_t(sizeof(sockaddr_storage_t))
  local ret = C.recvfrom(getfd(fd), buf, count, stringflags(flags, "MSG_"), cast(sockaddr_pt, ss), addrlen)
  if ret == -1 then return errorret() end
  return saret(ss, addrlen[0], {count = ret})
end

function S.setsockopt(fd, level, optname, optval, optlen)
   -- allocate buffer for user, from Lua type if know how, int and bool so far
  if not optlen and type(optval) == 'boolean' then if optval then optval = 1 else optval = 0 end end
  if not optlen and type(optval) == 'number' then
    optval = int1_t(optval)
    optlen = sizeof(int1_t)
  end
  return retbool(C.setsockopt(getfd(fd), level, optname, optval, optlen))
end

function S.getsockopt(fd, level, optname) -- will need fixing for non int/bool options
  local optval, optlen = int1_t(), socklen1_t()
  optlen[0] = sizeof(int1_t)
  local ret = C.getsockopt(getfd(fd), level, optname, optval, optlen)
  if ret == -1 then return errorret() end
  return tonumber(optval[0]) -- no special case for bool
end

function S.fchdir(fd) return retbool(C.fchdir(getfd(fd))) end
function S.fsync(fd) return retbool(C.fsync(getfd(fd))) end
function S.fdatasync(fd) return retbool(C.fdatasync(getfd(fd))) end
function S.fchmod(fd, mode) return retbool(C.fchmod(getfd(fd), stringflags(mode, "S_"))) end

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

function S.chroot(path) return retbool(C.chroot(path)) end

function S.getcwd(buf, size)
  local ret = C.getcwd(buf, size or 0)
  if not buf then -- Linux will allocate buffer here, return Lua string and free
    if ret == nil then return errorret() end
    local s = string(ret) -- guaranteed to be zero terminated if no error
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

function S.mmap(addr, length, prot, flags, fd, offset) -- adds munmap gc
  return retptr(C.mmap(addr, length, stringflags(prot, "PROT_"), stringflags(flags, "MAP_"), getfd(fd), offset), function(addr) C.munmap(addr, length) end)
end
function S.munmap(addr, length)
  return retbool(C.munmap(ffi.gc(addr, nil), length)) -- remove gc on unmap
end
function S.msync(addr, length, flags) return retbool(C.msync(addr, length, stringflags(flags, "MS_"))) end
function S.mlock(addr, len) return retbool(C.mlock(addr, len)) end
function S.munlock(addr, len) return retbool(C.munlock(addr, len)) end
function S.mlockall(flags) return retbool(C.mlockall(stringflags(flags, "MCL_"))) end
function S.munlockall() return retbool(C.munlockall()) end
function S.mremap(old_address, old_size, new_size, flags, new_address)
  return retptr(C.mremap(old_address, old_size, new_size, stringflags(flags, "MREMAP_"), new_address))
end
function S.madvise(addr, length, advice) return retbool(C.madvise(addr, length, stringflag(advice, "MADV_"))) end

local sproto
function sproto(domain, protocol) -- helper function to lookup protocol type depending on domain
  if domain == S.AF_NETLINK then return stringflag(protocol, "NETLINK_") end
  return protocol or 0
end

function S.socket(domain, stype, protocol)
  domain = stringflag(domain, "AF_")
  return retfd(C.socket(domain, stringflags(stype, "SOCK_"), sproto(domain, protocol)))
end
function S.socketpair(domain, stype, protocol)
  domain = stringflag(domain, "AF_")
  local sv2 = int2_t()
  local ret = C.socketpair(domain, stringflags(stype, "SOCK_"), sproto(domain, protocol), sv2)
  if ret == -1 then return errorret() end
  return {fd_t(sv2[0]), fd_t(sv2[1])}
end

function S.bind(sockfd, addr, addrlen)
  return retbool(C.bind(getfd(sockfd), cast(sockaddr_pt, addr), getaddrlen(addr, addrlen)))
end

function S.listen(sockfd, backlog) return retbool(C.listen(getfd(sockfd), backlog or 0)) end
function S.connect(sockfd, addr, addrlen)
  return retbool(C.connect(getfd(sockfd), cast(sockaddr_pt, addr), getaddrlen(addr, addrlen)))
end

function S.shutdown(sockfd, how) return retbool(C.shutdown(getfd(sockfd), stringflag(how, "SHUT_"))) end

function S.accept(sockfd)
  local ss = sockaddr_storage_t()
  local addrlen = int1_t(sizeof(sockaddr_storage_t))
  local ret = C.accept(getfd(sockfd), cast(sockaddr_pt, ss), addrlen)
  if ret == -1 then return errorret() end
  return saret(ss, addrlen[0], {fd = fd_t(ret)})
end
--S.accept4 = S.accept -- need to add support for flags argument TODO

function S.getsockname(sockfd)
  local ss = sockaddr_storage_t()
  local addrlen = int1_t(sizeof(sockaddr_storage_t))
  local ret = C.getsockname(getfd(sockfd), cast(sockaddr_pt, ss), addrlen)
  if ret == -1 then return errorret() end
  return saret(ss, addrlen[0])
end

function S.getpeername(sockfd)
  local ss = sockaddr_storage_t()
  local addrlen = int1_t(sizeof(sockaddr_storage_t))
  local ret = C.getpeername(getfd(sockfd), cast(sockaddr_pt, ss), addrlen)
  if ret == -1 then return errorret() end
  return saret(ss, addrlen[0])
end

function S.fcntl(fd, cmd, arg)
  -- some uses have arg as a pointer, need handling TODO
  cmd = stringflag(cmd, "F_")
  if cmd == S.F_SETFL then arg = stringflags(arg, "O_")
  elseif cmd == S.F_SETFD then arg = stringflag(arg, "FD_")
  end
  local ret = C.fcntl(getfd(fd), cmd, arg or 0)
  -- return values differ, some special handling needed
  if cmd == S.F_DUPFD or cmd == S.F_DUPFD_CLOEXEC then return retfd(ret) end
  if cmd == S.F_GETFD or cmd == S.F_GETFL or cmd == S.F_GETLEASE or cmd == S.F_GETOWN or
     cmd == S.F_GETSIG or cmd == S.F_GETPIPE_SZ then return retint(ret) end
  return retbool(ret)
end

function S.uname()
  local u = utsname_t()
  local ret = C.uname(u)
  if ret == -1 then return errorret() end
  return {sysname = string(u.sysname), nodename = string(u.nodename), release = string(u.release),
          version = string(u.version), machine = string(u.machine), domainname = string(u.domainname)}
end

function S.gethostname()
  local buf = buffer_t(HOST_NAME_MAX + 1)
  local ret = C.gethostname(buf, HOST_NAME_MAX + 1)
  if ret == -1 then return errorret() end
  buf[HOST_NAME_MAX] = 0 -- paranoia here to make sure null terminated, which could happen if HOST_NAME_MAX was incorrect
  return string(buf)
end

function S.sethostname(s) -- only accept Lua string, do not see use case for buffer as well
  return retbool(C.sethostname(s, #s))
end

function S.signal(signum, handler) return retbool(C.signal(stringflag(signum, "SIG"), stringflag(handler, "SIG_"))) end
function S.kill(pid, sig) return retbool(C.kill(pid, stringflag(sig, "SIG"))) end
function S.killpg(pgrp, sig) return S.kill(-pgrp, sig) end

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

-- fdset handlers
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

-- signal set handlers
local mksigset, getsigset, sigismember, sigaddset, sigdelset, sigaddsets, sigdelsets, sigsetmt

function mksigset(str)
  if not str then return sigset_t() end
  if istype(sigset_t, str) then return str end
  if type(str) == "table" then return str.sigset end
  local f = sigset_t()
  local a = split(",", str)
  for i, v in ipairs(a) do
    local s = trim(v:upper())
    if s:sub(1, 3) ~= "SIG" then s = "SIG" .. s end
    local sig = S[s]
    if not sig then error("invalid signal: " .. v) end -- don't use this format if you don't want exceptions, better than silent ignore

    local d = bit.rshift(sig - 1, 5) -- always 32 bits
    f.val[d] = bit.bor(f.val[d], bit.lshift(1, (sig - 1) % 32))
  end
  return f
end

function sigismember(set, sig)
  local d = bit.rshift(sig - 1, 5) -- always 32 bits
  return bit.band(set.val[d], bit.lshift(1, (sig - 1) % 32)) ~= 0
end
function sigaddset(set, sig)
  set = mksigset(set)
  local d = bit.rshift(sig - 1, 5)
  set.val[d] = bit.bor(set.val[d], bit.lshift(1, (sig - 1) % 32))
  return set
end
function sigdelset(set, sig)
  set = mksigset(set)
  local d = bit.rshift(sig - 1, 5)
  set.val[d] = bit.band(set.val[d], bit.bnot(bit.lshift(1, (sig - 1) % 32)))
  return set
end

function sigaddsets(set, sigs) -- allow multiple
  if type(sigs) ~= "string" then return getsigset(sigaddset(set, sigs)) end
  set = mksigset(set)
  local a = split(",", sigs)
  for i, v in ipairs(a) do
    local s = trim(v:upper())
    if s:sub(1, 3) ~= "SIG" then s = "SIG" .. s end
    local sig = S[s]
    if not sig then error("invalid signal: " .. v) end -- don't use this format if you don't want exceptions, better than silent ignore
    sigaddset(set, sig)
  end
  return getsigset(set)
end

function sigdelsets(set, sigs) -- allow multiple
  if type(sigs) ~= "string" then return getsigset(sigdelset(set, sigs)) end
  set = mksigset(set)
  local a = split(",", sigs)
  for i, v in ipairs(a) do
    local s = trim(v:upper())
    if s:sub(1, 3) ~= "SIG" then s = "SIG" .. s end
    local sig = S[s]
    if not sig then error("invalid signal: " .. v) end -- don't use this format if you don't want exceptions, better than silent ignore
    sigdelset(set, sig)
  end
  return getsigset(set)
end

sigsetmt = {__index = {add = sigaddsets, del = sigdelsets}}

function getsigset(set)
  local f = {sigset = set}
  local isemptyset = true
  for i = 1, S.NSIG do
    if sigismember(set, i) then
      f[signals[i]] = true
      f[signals[i]:lower():sub(4)] = true
      isemptyset = false
    end
  end
  f.isemptyset = isemptyset
  setmetatable(f, sigsetmt)
  return f
end

function S.sigprocmask(how, set)
  how = stringflag(how, "SIG_")
  set = mksigset(set)
  oldset = sigset_t()
  local ret = C.sigprocmask(how, set, oldset)
  if ret == -1 then return errorret() end
  return getsigset(oldset)
end

function S.sigpending()
  local set = sigset_t()
  local ret = C.sigpending(set)
  if ret == -1 then return errorret() end
 return getsigset(set)
end

function S.sigsuspend(mask) return retbool(C.sigsuspend(mksigset(mask))) end

function S.select(s) -- note same structure as returned
  local r, w, e
  local nfds = 0
  local timeout2
  if s.timeout then
    if istype(timeval_t, s.timeout) then timeout2 = s.timeout else timeout2 = timeval_t(s.timeout) end
  end
  r, nfds = mkfdset(s.readfds or {}, nfds or 0)
  w, nfds = mkfdset(s.writefds or {}, nfds)
  e, nfds = mkfdset(s.exceptfds or {}, nfds)
  local ret = C.select(nfds, r, w, e, timeout2)
  if ret == -1 then return errorret() end
  return {readfds = fdisset(s.readfds or {}, r), writefds = fdisset(s.writefds or {}, w),
          exceptfds = fdisset(s.exceptfds or {}, e), count = tonumber(ret)}
end

function S.mount(source, target, filesystemtype, mountflags, data)
  return retbool(C.mount(source, target, filesystemtype, stringflags(mountflags, "MS_"), data or nil))
end

function S.umount(target, flags)
  if flags then return retbool(C.umount2(target, stringflags(flags, "MNT_", "UMOUNT_"))) end
  return retbool(C.umount(target))
end

function S.getrlimit(resource)
  rlim = rlimit_t()
  local ret = C.getrlimit(stringflag(resource, "RLIMIT_"), rlim)
  if ret == -1 then return errorret() end
  return rlim
end

function S.setrlimit(resource, rlim, rlim2) -- can pass table, struct, or just both the parameters
  if rlim and rlim2 then rlim = rlimit_t(rlim, rlim2)
  elseif type(rlim) == 'table' then rlim = rlimit_t(rlim) end
  return retbool(C.setrlimit(stringflag(resource, "RLIMIT_"), rlim))
end

-- Linux only. use epoll1
function S.epoll_create(flags)
  return retfd(C.epoll_create1(stringflags(flags, "EPOLL_")))
end

function S.epoll_ctl(epfd, op, fd, events, data)
  local event = epoll_event_t{events = stringflags(events, "EPOLL")}
  if data then event.data.u64 = data else event.data.fd = getfd(fd) end
  return retbool(C.epoll_ctl(getfd(epfd), stringflag(op, "EPOLL_CTL_"), getfd(fd), event))
end

function S.epoll_wait(epfd, events, maxevents, timeout)
  if not maxevents then maxevents = 1 end
  if not events then events = epoll_events_t(maxevents) end
  local ret = C.epoll_wait(getfd(epfd), events, maxevents, timeout or 0)
  if ret == -1 then return errorret() end
  local r = {}
  for i = 1, ret do -- put in Lua array
    local e = events[i - 1]
    r[i] = getflags(e.events, "EPOLL", {"EPOLLIN", "EPOLLOUT", "EPOLLRDHUP", "EPOLLPRI", "EPOLLERR", "EPOLLHUP"}, {fd = e.data.fd, data = e.data.u64})
  end
  return r
end

function S.inotify_init(flags) return retfd(C.inotify_init1(stringflags(flags, "IN_"))) end
function S.inotify_add_watch(fd, pathname, mask) return retint(C.inotify_add_watch(getfd(fd), pathname, stringflags(mask, "IN_"))) end
function S.inotify_rm_watch(fd, wd) return retbool(C.inotify_rm_watch(getfd(fd), wd)) end

local in_recv_ev = {"IN_ACCESS", "IN_ATTRIB", "IN_CLOSE_WRITE", "IN_CLOSE_NOWRITE", "IN_CREATE", "IN_DELETE", "IN_DELETE_SELF", "IN_MODIFY",
                    "IN_MOVE_SELF", "IN_MOVED_FROM", "IN_MOVED_TO", "IN_OPEN",
                    "IN_CLOSE", "IN_MOVE" -- combined ops
                   }

-- helper function to read inotify structs as table from inotfy fd
function S.inotify_read(fd, buffer, len)
  if not len then len = 1024 end
  if not buffer then buffer = buffer_t(len) end
  local ret, err = S.read(fd, buffer, len)
  if not ret then return nil, err end
  local off, ee = 0, {}
  while off < ret do
    local ev = cast(inotify_event_pt, buffer + off)
    local le = getflags(ev.mask, "IN_", in_recv_ev, {wd = tonumber(ev.wd), mask = tonumber(ev.mask), cookie = tonumber(ev.cookie)})
    if ev.len > 0 then le.name = string(ev.name) end
    ee[#ee + 1] = le
    off = off + sizeof(inotify_event_t(ev.len))
  end
  return ee
end

function S.sendfile(out_fd, in_fd, offset, count) -- bit odd having two different return types...
  if not offset then return retint(C.sendfile(getfd(out_fd), getfd(in_fd), nil, count)) end
  local off = off1_t()
  off[0] = offset
  local ret = C.sendfile(getfd(out_fd), getfd(in_fd), off, count)
  if ret == -1 then return errorret() end
  return {count = tonumber(ret), offset = off[0]}
end

function S.eventfd(initval, flags) return retfd(C.eventfd(initval or 0, stringflags(flags, "EFD_"))) end
-- eventfd read and write helpers, as in glibc but Lua friendly. Note returns 0 for EAGAIN, as 0 never returned directly
-- returns Lua number - if you need all 64 bits, pass your own value in and use that for the exact result
function S.eventfd_read(fd, value)
  if not value then value = uint64_1t() end
  local ret = C.read(getfd(fd), value, 8)
  if ret == -1 and ffi.errno() == S.E.EAGAIN then
    value[0] = 0
    return 0
  end
  if ret == -1 then return errorret() end
  return tonumber(value[0])
end
function S.eventfd_write(fd, value)
  if not value then value = 1 end
  if type(value) == "number" then value = uint64_1t(value) end
  return retbool(C.write(getfd(fd), value, 8))
end

-- map for valid options for arg2
local prctlmap = {}
prctlmap[S.PR_CAPBSET_READ] = "CAP_"
prctlmap[S.PR_CAPBSET_DROP] = "CAP_"
prctlmap[S.PR_SET_ENDIAN] = "PR_ENDIAN"
prctlmap[S.PR_SET_FPEMU] = "PR_FPEMU_"
prctlmap[S.PR_SET_FPEXC] = "PR_FP_EXC_"
prctlmap[S.PR_SET_PDEATHSIG] = "SIG"
prctlmap[S.PR_SET_SECUREBITS] = "SECBIT_"
prctlmap[S.PR_SET_TIMING] = "PR_TIMING_"
prctlmap[S.PR_SET_TSC] = "PR_TSC_"
prctlmap[S.PR_SET_UNALIGN] = "PR_UNALIGN_"
prctlmap[S.PR_MCE_KILL] = "PR_MCE_KILL_"

local prctlrint = {} -- returns an integer directly
prctlrint[S.PR_GET_DUMPABLE] = true
prctlrint[S.PR_GET_KEEPCAPS] = true
prctlrint[S.PR_CAPBSET_READ] = true
prctlrint[S.PR_GET_TIMING] = true 
prctlrint[S.PR_GET_SECUREBITS] = true
prctlrint[S.PR_MCE_KILL_GET] = true
prctlrint[S.PR_GET_SECCOMP] = true

local prctlpint = {} -- returns result in a location pointed to by arg2
prctlpint[S.PR_GET_ENDIAN] = true
prctlpint[S.PR_GET_FPEMU] = true
prctlpint[S.PR_GET_FPEXC] = true
prctlpint[S.PR_GET_PDEATHSIG] = true
prctlpint[S.PR_GET_UNALIGN] = true

function S.prctl(option, arg2, arg3, arg4, arg5)
  local i, name
  option = stringflag(option, "PR_") -- actually not all PR_ prefixed options ok some are for other args, could be more specific
  local m = prctlmap[option]
  if m then arg2 = stringflag(arg2, m) end
  if option == S.PR_MCE_KILL and arg2 == S.PR_MCE_KILL_SET then arg3 = stringflag(arg3, "PR_MCE_KILL_")
  elseif prctlpint[option] then
    i = int1_t()
    arg2 = cast(ulong_t, i)
  elseif option == S.PR_GET_NAME then
    name = buffer_t(16)
    arg2 = cast(ulong_t, name)
  elseif option == S.PR_SET_NAME then
    if type(arg2) == "string" then arg2 = cast(ulong_t, arg2) end
  end
  local ret = C.prctl(option, arg2 or 0, arg3 or 0, arg4 or 0, arg5 or 0)
  if ret == -1 then return errorret() end
  if prctlrint[option] then return ret end
  if prctlpint[option] then return i[0] end
  if option == S.PR_GET_NAME then
    if name[15] ~= 0 then return string(name, 16) end -- actually, 15 bytes seems to be longest, aways 0 terminated
    return string(name)
  end
  return true
end

-- this is the glibc name for the syslog syscall
function S.klogctl(t, buf, len)
  if not buf and (t == 2 or t == 3 or t == 4) then
    if not len then
      len = C.klogctl(10, nil, 0) -- get size so we can allocate buffer
      if len == -1 then return errorret() end
    end
    buf = buffer_t(len)
  end
  local ret = C.klogctl(t, buf or nil, len or 0)
  if ret == -1 then return errorret() end
  if t == 9 or t == 10 then return tonumber(ret) end
  if t == 2 or t == 3 or t == 4 then return string(buf, ret) end
  return true
end

function S.adjtimex(t)
  if not t then t = timex_t() end
  if type(t) == 'table' then
    if t.modes then t.modes = stringflags(t.modes, "ADJ_") end
    if t.status then t.status = stringflags(t.status, "STA_") end
    t = timex_t(t)
  end
  local ret = C.adjtimex(t)
  if ret == -1 then return errorret() end
  -- we need to return a table, as we need to return both ret and the struct timex. should probably put timex fields in table
  local r = getflags(ret, "TIME_", {"TIME_OK", "TIME_INS", "TIME_DEL", "TIME_OOP", "TIME_WAIT", "TIME_BAD"}, {timex = t})
  return r
end

if rt then -- real time functions not in glibc in Linux, check if available. N/A on OSX.
  function S.clock_getres(clk_id, ts)
    if not ts then ts = timespec_t() end
    local ret = rt.clock_getres(stringflag(clk_id, "CLOCK_"), ts)
    if ret == -1 then return errorret() end
    return ts
  end

  function S.clock_gettime(clk_id, ts)
    if not ts then ts = timespec_t() end
    local ret = rt.clock_gettime(stringflag(clk_id, "CLOCK_"), ts)
    if ret == -1 then return errorret() end
    return ts
  end

  function S.clock_settime(clk_id, ts) return retbool(rt.clock_settime(stringflag(clk_id, "CLOCK_"), ts)) end
end

-- straight passthroughs, as no failure possible
S.getuid = C.getuid
S.geteuid = C.geteuid
S.getpid = C.getpid
S.getppid = C.getppid
S.getgid = C.getgid
S.getegid = C.getegid
S.sync = C.sync
S.alarm = C.alarm

function S.umask(mask) return C.umask(stringflags(mask, "S_")) end

function S.getsid(pid) return retint(C.getsid(pid or 0)) end
function S.setsid() return retint(C.setsid()) end

-- handle environment (Lua only provides os.getenv). Could add metatable to make more Lualike.
function S.environ() -- return whole environment as table
  local environ = ffi.C.environ
  if not environ then return nil end
  local r = {}
  local i = 0
  while environ[i] ~= nil do
    local e = string(environ[i])
    local eq = e:find('=')
    if eq then
      r[e:sub(1, eq - 1)] = e:sub(eq + 1)
    end
    i = i + 1
  end
  return r
end
function S.getenv(name)
  return S.environ()[name]
end
function S.unsetenv(name) return retbool(C.unsetenv(name)) end
function S.setenv(name, value, overwrite)
  if type(overwrite) == 'boolean' and overwrite then overwrite = 1 end
  return retbool(C.setenv(name, value, overwrite or 0))
end
function S.clearenv() return retbool(C.clearenv()) end

local oldcmdline, cmdstart

function S.setcmdline(...) -- this sets /proc/self/cmdline, use prctl to set /proc/self/comm as well
  -- note code makes memory layout assumptions that are not necessarily portable
  -- call this before modifying environment, as we cannot actually get real argv pointer right now, so deduce
  -- will probably segfault otherwise!

  if not oldcmdline then
    oldcmdline = S.readfile("/proc/self/cmdline")
    if not C.environ then return nil end -- nothing we can do
    cmdstart = C.environ[0] - #oldcmdline -- this is where Linux stores the command line
  end

  local me = cast("char *", C.environ)

  if not me then return nil end -- in normal use you should get a pointer to one null pointer as minimum

  local new = table.concat({...}, '\0')

  if #new <= #oldcmdline then -- do not need to move environment
    ffi.copy(cmdstart, new)
    ffi.fill(cmdstart + #new, #oldcmdline - #new)
    return true
  end

  local e = S.environ() -- keep copy to reconstruct

  -- we should have a guaranteed space, larger than env, but segfaulting... 

  local elen = 0
  for k, v in pairs(e) do elen = elen + #v + 1 end

  if #new > #oldcmdline + elen - 1 then new = new:sub(1, #oldcmdline + elen - 1) .. '\0' end
  C.environ = nil -- kill the old environ

  ffi.copy(cmdstart, new)
  ffi.fill(cmdstart + #new, #oldcmdline + elen - #new)

  for k, v in pairs(e) do S.setenv(k, v) end -- restore environment

  return true
end

-- 'macros' and helper functions etc

-- LuaJIT does not provide 64 bit bitops at the moment
local b64
function b64(n)
  local t64 = int64_1t(n)
  local t32 = cast(int32_pt, t64)
  if ffi.abi("le") then
    return tonumber(t32[1]), tonumber(t32[0]) -- return high, low
  else
    return tonumber(t32[0]), tonumber(t32[1])
  end
end

function S.major(dev)
  local h, l = b64(dev)
  return bit.bor(bit.band(bit.rshift(l, 8), 0xfff), bit.band(h, bit.bnot(0xfff)));
end

-- minor and makedev assume minor numbers 20 bit so all in low byte, currently true
-- would be easier to fix if LuaJIT had native 64 bit bitops
function S.minor(dev)
  local h, l = b64(dev)
  return bit.bor(bit.band(l, 0xff), bit.band(bit.rshift(l, 12), bit.bnot(0xff)));
end

local two32 = int64_t(0xffffffff) + 1 -- 0x100000000LL -- hack to get luac to parse this for checking
function S.makedev(major, minor)
  local dev = int64_t()
  dev = bit.bor(bit.band(minor, 0xff), bit.lshift(bit.band(major, 0xfff), 8), bit.lshift(bit.band(minor, bit.bnot(0xff)), 12)) + two32 * bit.band(major, bit.bnot(0xfff))
  return dev
end

function S.S_ISREG(m)  return bit.band(m, S.S_IFREG)  ~= 0 end
function S.S_ISDIR(m)  return bit.band(m, S.S_IFDIR)  ~= 0 end
function S.S_ISCHR(m)  return bit.band(m, S.S_IFCHR)  ~= 0 end
function S.S_ISBLK(m)  return bit.band(m, S.S_IFBLK)  ~= 0 end
function S.S_ISFIFO(m) return bit.band(m, S.S_IFFIFO) ~= 0 end
function S.S_ISLNK(m)  return bit.band(m, S.S_IFLNK)  ~= 0 end
function S.S_ISSOCK(m) return bit.band(m, S.S_IFSOCK) ~= 0 end

local align
function align(len, a) return bit.band(tonumber(len) + a - 1, bit.bnot(a - 1)) end

-- cmsg functions, try to hide some of this nasty stuff from the user
local cmsg_align, cmsg_space, cmsg_len, cmsg_firsthdr, cmsg_nxthdr
local cmsg_hdrsize = sizeof(cmsghdr_t(0))
if ffi.abi('32bit') then
  function cmsg_align(len) return align(len, 4) end
else
  function cmsg_align(len) return align(len, 8) end
end

local cmsg_ahdr = cmsg_align(cmsg_hdrsize)
function cmsg_space(len) return cmsg_ahdr + cmsg_align(len) end
function cmsg_len(len) return cmsg_ahdr + len end

-- msg_control is a bunch of cmsg structs, but these are all different lengths, as they have variable size arrays

-- these functions also take and return a raw char pointer to msg_control, to make life easier, as well as the cast cmsg
function cmsg_firsthdr(msg)
  if msg.msg_controllen < cmsg_hdrsize then return nil end
  local mc = msg.msg_control
  local cmsg = cast(cmsghdr_pt, mc)
  return mc, cmsg
end

function cmsg_nxthdr(msg, buf, cmsg)
  if cmsg.cmsg_len < cmsg_hdrsize then return nil end -- invalid cmsg
  buf = buf + cmsg_align(cmsg.cmsg_len) -- find next cmsg
  if buf + cmsg_hdrsize > msg.msg_control + msg.msg_controllen then return nil end -- header would not fit
  cmsg = cast(cmsghdr_pt, buf)
  if buf + cmsg_align(cmsg.cmsg_len) > msg.msg_control + msg.msg_controllen then return nil end -- whole cmsg would not fit
  return buf, cmsg
end

-- similar functions for netlink messages
local nlmsg_align = function(len) return align(len, 4) end
local nlmsg_hdrlen = nlmsg_align(sizeof(nlmsghdr_t))
local nlmsg_length = function(len) return len + nlmsg_hdrlen end
local nlmsg_ok = function(msg, len)
  return len >= nlmsg_hdrlen and msg.nlmsg_len >= nlmsg_hdrlen and msg.nlmsg_len <= len
end
local nlmsg_next = function(msg, buf, len)
  local inc = nlmsg_align(msg.nlmsg_len)
  return cast(nlmsghdr_pt, buf + inc), buf + inc, len - inc
end

local rta_align = nlmsg_align -- also 4 byte align
local rta_length = function(len) return len + rta_align(sizeof(rtattr_t)) end
local rta_ok = function(msg, len)
  return len >= sizeof(rtattr_t) and msg.rta_len >= sizeof(rtattr_t) and msg.rta_len <= len
end
local rta_next = function(msg, buf, len)
  local inc = rta_align(msg.rta_len)
  return cast(rtattr_pt, buf + inc), buf + inc, len - inc
end

local ifla_decode = {}
ifla_decode[S.IFLA_IFNAME] = function(r, buf, len)
  r.name = string(buf + rta_length(0))

  return r
end

local nlmsg_data_decode = {}
nlmsg_data_decode[S.RTM_NEWLINK] = function(r, buf, len)

  local iface = cast(ifinfomsg_pt, buf)

  buf = buf + nlmsg_align(sizeof(ifinfomsg_t))
  len = len - nlmsg_align(sizeof(ifinfomsg_t))

  local rtattr = cast(rtattr_pt, buf)
  local ir = {index = iface.ifi_index} -- info about interface
  while rta_ok(rtattr, len) do
    if ifla_decode[rtattr.rta_type] then ir = ifla_decode[rtattr.rta_type](ir, buf, len) end

    rtattr, buf, len = rta_next(rtattr, buf, len)
  end

  if not r.ifaces then r.ifaces = {} end -- array
  if not r.iface then r.iface = {} end -- table

  r.ifaces[#r.ifaces + 1] = ir -- cant use interface index as holes.
  if ir.name then r.iface[ir.name] = ir end

  return r
end

function S.nlmsg_read(s, addr) -- maybe we create the sockaddr?

  local bufsize = 8192
  local reply = buffer_t(bufsize)
  local ior = iovec_t(1, {{reply, bufsize}})
  local m = msghdr_t{msg_iov = ior, msg_iovlen = 1, msg_name = addr, msg_namelen = sizeof(addr)}

  local done = false -- what should we do if we get a done message but there is some extra buffer? could be next message...
  local r = {}

  while not done do
    local n, err = s:recvmsg(m)
    if not n then return nil, err end
    local len = n.count
    local buffer = reply

    local msg = cast(nlmsghdr_pt, buffer)

    while not done and nlmsg_ok(msg, len) do
      local t = tonumber(msg.nlmsg_type)

      if nlmsg_data_decode[t] then r = nlmsg_data_decode[t](r, buffer + nlmsg_hdrlen, msg.nlmsg_len - nlmsg_hdrlen) end

      if t == S.NLMSG_DONE then done = true end
      msg, buffer, len = nlmsg_next(msg, buffer, len)
    end
  end

  return r
end

function S.sendmsg(fd, msg, flags)
  if not msg then -- send a single byte message, eg enough to send credentials
    local buf1 = buffer_t(1)
    local io = iovec_t(1, {{buf1, 1}})
    msg = msghdr_t{msg_iov = io, msg_iovlen = 1}
  end
  return retbool(C.sendmsg(getfd(fd), msg, stringflags(flags, "MSG_")))
end

-- if no msg provided, assume want to receive cmsg
function S.recvmsg(fd, msg, flags)
  if not msg then 
    local buf1 = buffer_t(1) -- assume user wants to receive single byte to get cmsg
    local io = iovec_t(1, {{buf1, 1}})
    local bufsize = 1024 -- sane default, build your own structure otherwise
    local buf = buffer_t(bufsize)
    msg = msghdr_t{msg_iov = io, msg_iovlen = 1, msg_control = buf, msg_controllen = bufsize}
  end
  local ret = C.recvmsg(getfd(fd), msg, stringflags(flags, "MSG_"))
  if ret == -1 then return errorret() end
  local ret = {count = ret, iovec = msg.msg_iov} -- thats the basic return value, and the iovec
  local mc, cmsg = cmsg_firsthdr(msg)
  while cmsg do
    if cmsg.cmsg_level == S.SOL_SOCKET then
      if cmsg.cmsg_type == S.SCM_CREDENTIALS then
        local cred = ucred_t() -- could just cast to ucred pointer
        ffi.copy(cred, cmsg.cmsg_data, sizeof(ucred_t))
        ret.pid = cred.pid
        ret.uid = cred.uid
        ret.gid = cred.gid
      elseif cmsg.cmsg_type == S.SCM_RIGHTS then
      local fda = cast(int_pt, cmsg.cmsg_data)
      local fdc = div(cmsg.cmsg_len - cmsg_ahdr, sizeof(int1_t))
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
  local usize = sizeof(ucred_t)
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
  local fasize = sizeof(fa)
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
  local fl, err = s:fcntl(S.F_GETFL)
  if not fl then return nil, err end
  fl, err = s:fcntl(S.F_SETFL, bit.bor(fl, S.O_NONBLOCK))
  if not fl then return nil, err end
  return true
end

function S.readfile(name, length) -- convenience for reading short files into strings, eg for /proc etc, silently ignores short reads
  local f, err = S.open(name, S.O_RDONLY)
  if not f then print("open"); return nil, err end
  local r, err = f:read(nil, length or 4096)
  if not r then print("read"); return nil, err end
  local t, err = f:close()
  if not t then print("close"); return nil, err end
  return r
end

function S.writefile(name, string, mode) -- write string to named file. specify mode if want to create file, silently ignore short writes
  local f, err
  if mode then f, err = S.creat(name, mode) else f, err = S.open(name, S.O_WRONLY) end
  if not f then return nil, err end
  local n, err = f:write(string)
  if not n then return nil, err end
  local t, err = f:close()
  if not t then return nil, err end
  return true
end

function S.dirfile(name) -- return the directory entries in a file
  local fd, d, _, err
  fd, err = S.open(name, S.O_DIRECTORY + S.O_RDONLY)
  if err then return nil, err end
  d, err = fd:getdents()
  if err then return nil, err end
  _, err = fd:close()
  if err then return nil, err end
  return d
end

-- use string types for now
local threc -- helper for returning varargs
function threc(buf, offset, t, ...) -- alignment issues, need to round up to minimum alignment
  if not t then return nil end
  if select("#", ...) == 0 then return cast(typeof(t .. "*"), buf + offset) end
  return cast(typeof(t .. "*"), buf + offset), threc(buf, offset + sizeof(t), ...)
end
function S.tbuffer(...) -- helper function for sequence of types in a buffer
  local len = 0
  for i, t in ipairs{...} do
    len = len + sizeof(typeof(t)) -- alignment issues, need to round up to minimum alignment
  end
  local buf = buffer_t(len)
  return buf, len, threc(buf, 0, ...)
end

-- methods on an fd
local fdmethods = {'nogc', 'nonblock', 'sendfds', 'sendcred',
                   'close', 'dup', 'read', 'write', 'pread', 'pwrite',
                   'lseek', 'fchdir', 'fsync', 'fdatasync', 'fstat', 'fcntl', 'fchmod',
                   'bind', 'listen', 'connect', 'accept', 'getsockname', 'getpeername',
                   'send', 'sendto', 'recv', 'recvfrom', 'readv', 'writev', 'sendmsg',
                   'recvmsg', 'setsockopt', "epoll_ctl", "epoll_wait", "sendfile", "getdents",
                   'eventfd_read', 'eventfd_write', 'ftruncate', 'shutdown', 'getsockopt',
                   'inotify_add_watch', 'inotify_rm_watch', 'inotify_read'
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
  sockaddr_nl = sockaddr_nl_t, nlmsghdr = nlmsghdr_t, rtgenmsg = rtgenmsg_t, uint64 = uint64_t
}

return S


