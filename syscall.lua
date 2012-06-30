
local function syscall()

local S = {} -- exported functions

local ffi = require "ffi"
local bit = require "bit"

local C = ffi.C

local octal = function (s) return tonumber(s, 8) end 

local t, pt = {}, {} -- types and pointer types tables
S.t = t
S.pt = pt

local mt = {} -- metatables

-- convenience so user need not require ffi
S.string = ffi.string
S.sizeof = ffi.sizeof
S.cast = ffi.cast
S.copy = ffi.copy
S.fill = ffi.fill

S.STDIN_FILENO = 0
S.STDOUT_FILENO = 1
S.STDERR_FILENO = 2

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

if ffi.abi('32bit') then S.O_LARGEFILE = octal('0100000') else S.O_LARGEFILE = 0 end -- never required

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
S.F_GETLK64     = 12
S.F_SETLK64     = 13
S.F_SETLKW64    = 14
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

-- posix fadvise
S.POSIX_FADV_NORMAL       = 0
S.POSIX_FADV_RANDOM       = 1
S.POSIX_FADV_SEQUENTIAL   = 2
S.POSIX_FADV_WILLNEED     = 3
if ffi.arch == "s390x" then -- untested!
  S.POSIX_FADV_DONTNEED    = 6
  S.POSIX_FADV_NOREUSE     = 7
else
  S.POSIX_FADV_DONTNEED    = 4
  S.POSIX_FADV_NOREUSE     = 5
end

-- fallocate
S.FALLOC_FL_KEEP_SIZE	= 0x01
S.FALLOC_FL_PUNCH_HOLE	= 0x02

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

local signals = {
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

S.SIGIOT = 6
S.SIGUNUSED     = 31
S.SIGCLD        = S.SIGCHLD
S.SIGPOLL       = S.SIGIO

S.NSIG          = 32

-- sigprocmask
S.SIG_BLOCK     = 0
S.SIG_UNBLOCK   = 1
S.SIG_SETMASK   = 2

-- signalfd
S.SFD_CLOEXEC  = octal('02000000')
S.SFD_NONBLOCK = octal('04000')

-- sockets
S.SOCK_STREAM    = 1
S.SOCK_DGRAM     = 2
S.SOCK_RAW       = 3
S.SOCK_RDM       = 4
S.SOCK_SEQPACKET = 5
S.SOCK_DCCP      = 6
S.SOCK_PACKET    = 10

S.SOCK_CLOEXEC  = octal('02000000')
S.SOCK_NONBLOCK = octal('04000')

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

S.__WNOTHREAD    = 0x20000000
S.__WALL         = 0x40000000
S.__WCLONE       = 0x80000000
S.NOTHREAD, S.WALL, S.WCLONE = S.__WNOTHREAD, S.__WALL, S.__WCLONE

-- struct siginfo, eg waitid
local signal_reasons_gen = {}
local signal_reasons = {}

S.SI_ASYNCNL = -60
S.SI_TKILL = -6
S.SI_SIGIO = -5
S.SI_ASYNCIO = -4
S.SI_MESGQ = -3
S.SI_TIMER = -2
S.SI_QUEUE = -1
S.SI_USER = 0
S.SI_KERNEL = 0x80

for _, v in ipairs{"SI_ASYNCNL", "SI_TKILL", "SI_SIGIO", "SI_ASYNCIO", "SI_MESGQ", "SI_TIMER", "SI_QUEUE", "SI_USER", "SI_KERNEL"} do
  signal_reasons_gen[S[v]] = v
end

S.ILL_ILLOPC = 1
S.ILL_ILLOPN = 2
S.ILL_ILLADR = 3
S.ILL_ILLTRP = 4
S.ILL_PRVOPC = 5
S.ILL_PRVREG = 6
S.ILL_COPROC = 7
S.ILL_BADSTK = 8

signal_reasons[S.SIGILL] = {}
for _, v in ipairs{"ILL_ILLOPC", "ILL_ILLOPN", "ILL_ILLADR", "ILL_ILLTRP", "ILL_PRVOPC", "ILL_PRVREG", "ILL_COPROC", "ILL_BADSTK"} do
  signal_reasons[S.SIGILL][S[v]] = v
end

S.FPE_INTDIV = 1
S.FPE_INTOVF = 2
S.FPE_FLTDIV = 3
S.FPE_FLTOVF = 4
S.FPE_FLTUND = 5
S.FPE_FLTRES = 6
S.FPE_FLTINV = 7
S.FPE_FLTSUB = 8

signal_reasons[S.SIGFPE] = {}
for _, v in ipairs{"FPE_INTDIV", "FPE_INTOVF", "FPE_FLTDIV", "FPE_FLTOVF", "FPE_FLTUND", "FPE_FLTRES", "FPE_FLTINV", "FPE_FLTSUB"} do
  signal_reasons[S.SIGFPE][S[v]] = v
end

S.SEGV_MAPERR = 1
S.SEGV_ACCERR = 2

signal_reasons[S.SIGSEGV] = {}
for _, v in ipairs{"SEGV_MAPERR", "SEGV_ACCERR"} do
  signal_reasons[S.SIGSEGV][S[v]] = v
end

S.BUS_ADRALN = 1
S.BUS_ADRERR = 2
S.BUS_OBJERR = 3

signal_reasons[S.SIGBUS] = {}
for _, v in ipairs{"BUS_ADRALN", "BUS_ADRERR", "BUS_OBJERR"} do
  signal_reasons[S.SIGBUS][S[v]] = v
end

S.TRAP_BRKPT = 1
S.TRAP_TRACE = 2

signal_reasons[S.SIGTRAP] = {}
for _, v in ipairs{"TRAP_BRKPT", "TRAP_TRACE"} do
  signal_reasons[S.SIGTRAP][S[v]] = v
end

S.CLD_EXITED    = 1
S.CLD_KILLED    = 2
S.CLD_DUMPED    = 3
S.CLD_TRAPPED   = 4
S.CLD_STOPPED   = 5
S.CLD_CONTINUED = 6

signal_reasons[S.SIGCHLD] = {}
for _, v in ipairs{"CLD_EXITED", "CLD_KILLED", "CLD_DUMPED", "CLD_TRAPPED", "CLD_STOPPED", "CLD_CONTINUED"} do
  signal_reasons[S.SIGCHLD][S[v]] = v
end

S.POLL_IN  = 1
S.POLL_OUT = 2
S.POLL_MSG = 3
S.POLL_ERR = 4
S.POLL_PRI = 5
S.POLL_HUP = 6

signal_reasons[S.SIGPOLL] = {}
for _, v in ipairs{"POLL_IN", "POLL_OUT", "POLL_MSG", "POLL_ERR", "POLL_PRI", "POLL_HUP"} do
  signal_reasons[S.SIGPOLL][S[v]] = v
end

-- sigaction
S.SA_NOCLDSTOP = 0x00000001
S.SA_NOCLDWAIT = 0x00000002
S.SA_SIGINFO   = 0x00000004
S.SA_ONSTACK   = 0x08000000
S.SA_RESTART   = 0x10000000
S.SA_NODEFER   = 0x40000000
S.SA_RESETHAND = 0x80000000
S.SA_NOMASK = SA_NODEFER
S.SA_ONESHOT = SA_RESETHAND
S.SA_RESTORER = 0x04000000

-- timers
S.ITIMER_REAL = 0
S.ITIMER_VIRTUAL = 1
S.ITIMER_PROF = 2

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

mt.timex = {
  __index = function(t, k)
    local prefix = "TIME_"
    if k:sub(1, #prefix) ~= prefix then k = prefix .. k:upper() end
    if S[k] then return bit.band(t.state, S[k]) ~= 0 end
  end
}

-- xattr
S.XATTR_CREATE = 1
S.XATTR_REPLACE = 2

-- utime
S.UTIME_NOW  = bit.lshift(1, 30) - 1
S.UTIME_OMIT = bit.lshift(1, 30) - 2

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

-- timerfd
S.TFD_CLOEXEC = octal("02000000")
S.TFD_NONBLOCK = octal("04000")

S.TFD_TIMER_ABSTIME = 1

-- poll
S.POLLIN          = 0x001
S.POLLPRI         = 0x002
S.POLLOUT         = 0x004
S.POLLRDNORM      = 0x040
S.POLLRDBAND      = 0x080
S.POLLWRNORM      = 0x100
S.POLLWRBAND      = 0x200
S.POLLMSG         = 0x400
S.POLLREMOVE      = 0x1000
S.POLLRDHUP       = 0x2000
S.POLLERR         = 0x008
S.POLLHUP         = 0x010
S.POLLNVAL        = 0x020

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

mt.epoll = {
  __index = function(t, k)
    local prefix = "EPOLL"
    if k:sub(1, #prefix) ~= prefix then k = prefix .. k:upper() end
    if S[k] then return bit.band(t.events, S[k]) ~= 0 end
  end
}

S.EPOLL_CTL_ADD = 1
S.EPOLL_CTL_DEL = 2
S.EPOLL_CTL_MOD = 3

-- splice etc
S.SPLICE_F_MOVE         = 1
S.SPLICE_F_NONBLOCK     = 2
S.SPLICE_F_MORE         = 4
S.SPLICE_F_GIFT         = 8

-- aio - see /usr/include/linux/aio_abi.h
S.IOCB_CMD_PREAD = 0
S.IOCB_CMD_PWRITE = 1
S.IOCB_CMD_FSYNC = 2
S.IOCB_CMD_FDSYNC = 3
--S.IOCB_CMD_PREADX = 4
--S.IOCB_CMD_POLL = 5
S.IOCB_CMD_NOOP = 6
S.IOCB_CMD_PREADV = 7
S.IOCB_CMD_PWRITEV = 8

S.IOCB_FLAG_RESFD = 1

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

mt.dents = {
  __index = function(t, k)
    local prefix = "DT_"
    if k:sub(1, #prefix) ~= prefix then k = prefix .. k:upper() end
    if S[k] then return t.type == S[k] end
  end
}

-- sync file range
S.SYNC_FILE_RANGE_WAIT_BEFORE = 1
S.SYNC_FILE_RANGE_WRITE       = 2
S.SYNC_FILE_RANGE_WAIT_AFTER  = 4

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
S.IFLA_MAX       = 26

-- from if_addr.h interface address types and flags
S.IFA_UNSPEC    = 0
S.IFA_ADDRESS   = 1
S.IFA_LOCAL     = 2
S.IFA_LABEL     = 3
S.IFA_BROADCAST = 4
S.IFA_ANYCAST   = 5
S.IFA_CACHEINFO = 6
S.IFA_MULTICAST = 7
S.IFA_MAX       = 7

S.IFA_F_SECONDARY   = 0x01
S.IFA_F_TEMPORARY   = S.IFA_F_SECONDARY

S.IFA_F_NODAD       = 0x02
S.IFA_F_OPTIMISTIC  = 0x04
S.IFA_F_DADFAILED   = 0x08
S.IFA_F_HOMEADDRESS = 0x10
S.IFA_F_DEPRECATED  = 0x20
S.IFA_F_TENTATIVE   = 0x40
S.IFA_F_PERMANENT   = 0x80

-- interface flags
S.IFF_UP         = 0x1
S.IFF_BROADCAST  = 0x2
S.IFF_DEBUG      = 0x4
S.IFF_LOOPBACK   = 0x8
S.IFF_POINTOPOINT= 0x10
S.IFF_NOTRAILERS = 0x20
S.IFF_RUNNING    = 0x40
S.IFF_NOARP      = 0x80
S.IFF_PROMISC    = 0x100
S.IFF_ALLMULTI   = 0x200
S.IFF_MASTER     = 0x400
S.IFF_SLAVE      = 0x800
S.IFF_MULTICAST  = 0x1000
S.IFF_PORTSEL    = 0x2000
S.IFF_AUTOMEDIA  = 0x4000
S.IFF_DYNAMIC    = 0x8000
S.IFF_LOWER_UP   = 0x10000
S.IFF_DORMANT    = 0x20000
S.IFF_ECHO       = 0x40000

S.IFF_SLAVE_NEEDARP = 0x40
S.IFF_ISATAP        = 0x80
S.IFF_MASTER_ARPMON = 0x100
S.IFF_WAN_HDLC      = 0x200
S.IFF_XMIT_DST_RELEASE = 0x400
S.IFF_DONT_BRIDGE   = 0x800
S.IFF_DISABLE_NETPOLL    = 0x1000
S.IFF_MACVLAN_PORT       = 0x2000
S.IFF_BRIDGE_PORT = 0x4000
S.IFF_OVS_DATAPATH       = 0x8000
S.IFF_TX_SKB_SHARING     = 0x10000
S.IFF_UNICAST_FLT = 0x20000

-- Private (from user) interface flags (netdevice->priv_flags)
S.IFF_802_1Q_VLAN = 0x1
S.IFF_EBRIDGE     = 0x2
S.IFF_SLAVE_INACTIVE     = 0x4
S.IFF_MASTER_8023AD      = 0x8
S.IFF_MASTER_ALB  = 0x10
S.IFF_BONDING     = 0x20

S.IFF_VOLATILE = S.IFF_LOOPBACK + S.IFF_POINTOPOINT + S.IFF_BROADCAST + S.IFF_ECHO +
                 S.IFF_MASTER + S.IFF_SLAVE + S.IFF_RUNNING + S.IFF_LOWER_UP + S.IFF_DORMANT

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
S.AF_DECNET     = 12
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

-- arp types, which are also interface types for ifi_type
S.ARPHRD_NETROM   = 0
S.ARPHRD_ETHER    = 1
S.ARPHRD_EETHER   = 2
S.ARPHRD_AX25     = 3
S.ARPHRD_PRONET   = 4
S.ARPHRD_CHAOS    = 5
S.ARPHRD_IEEE802  = 6
S.ARPHRD_ARCNET   = 7
S.ARPHRD_APPLETLK = 8
S.ARPHRD_DLCI     = 15
S.ARPHRD_ATM      = 19
S.ARPHRD_METRICOM = 23
S.ARPHRD_IEEE1394 = 24
S.ARPHRD_EUI64    = 27
S.ARPHRD_INFINIBAND = 32
S.ARPHRD_SLIP     = 256
S.ARPHRD_CSLIP    = 257
S.ARPHRD_SLIP6    = 258
S.ARPHRD_CSLIP6   = 259
S.ARPHRD_RSRVD    = 260
S.ARPHRD_ADAPT    = 264
S.ARPHRD_ROSE     = 270
S.ARPHRD_X25      = 271
S.ARPHRD_HWX25    = 272
S.ARPHRD_CAN      = 280
S.ARPHRD_PPP      = 512
S.ARPHRD_CISCO    = 513
S.ARPHRD_HDLC     = ARPHRD_CISCO
S.ARPHRD_LAPB     = 516
S.ARPHRD_DDCMP    = 517
S.ARPHRD_RAWHDLC  = 518
S.ARPHRD_TUNNEL   = 768
S.ARPHRD_TUNNEL6  = 769
S.ARPHRD_FRAD     = 770
S.ARPHRD_SKIP     = 771
S.ARPHRD_LOOPBACK = 772
S.ARPHRD_LOCALTLK = 773
S.ARPHRD_FDDI     = 774
S.ARPHRD_BIF      = 775
S.ARPHRD_SIT      = 776
S.ARPHRD_IPDDP    = 777
S.ARPHRD_IPGRE    = 778
S.ARPHRD_PIMREG   = 779
S.ARPHRD_HIPPI    = 780
S.ARPHRD_ASH      = 781
S.ARPHRD_ECONET   = 782
S.ARPHRD_IRDA     = 783
S.ARPHRD_FCPP     = 784
S.ARPHRD_FCAL     = 785
S.ARPHRD_FCPL     = 786
S.ARPHRD_FCFABRIC = 787
S.ARPHRD_IEEE802_TR = 800
S.ARPHRD_IEEE80211 = 801
S.ARPHRD_IEEE80211_PRISM = 802
S.ARPHRD_IEEE80211_RADIOTAP = 803
S.ARPHRD_IEEE802154         = 804
S.ARPHRD_PHONET   = 820
S.ARPHRD_PHONET_PIPE = 821
S.ARPHRD_CAIF     = 822
S.ARPHRD_VOID     = 0xFFFF
S.ARPHRD_NONE     = 0xFFFE

-- IP
S.IPPROTO_IP = 0
S.IPPROTO_HOPOPTS = 0
S.IPPROTO_ICMP = 1
S.IPPROTO_IGMP = 2
S.IPPROTO_IPIP = 4
S.IPPROTO_TCP = 6
S.IPPROTO_EGP = 8
S.IPPROTO_PUP = 12
S.IPPROTO_UDP = 17
S.IPPROTO_IDP = 22
S.IPPROTO_TP = 29
S.IPPROTO_DCCP = 33
S.IPPROTO_IPV6 = 41
S.IPPROTO_ROUTING = 43
S.IPPROTO_FRAGMENT = 44
S.IPPROTO_RSVP = 46
S.IPPROTO_GRE = 47
S.IPPROTO_ESP = 50
S.IPPROTO_AH = 51
S.IPPROTO_ICMPV6 = 58
S.IPPROTO_NONE = 59
S.IPPROTO_DSTOPTS = 60
S.IPPROTO_MTP = 92
S.IPPROTO_ENCAP = 98
S.IPPROTO_PIM = 103
S.IPPROTO_COMP = 108
S.IPPROTO_SCTP = 132
S.IPPROTO_UDPLITE = 136
S.IPPROTO_RAW = 255

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

-- clone
S.CLONE_VM      = 0x00000100
S.CLONE_FS      = 0x00000200
S.CLONE_FILES   = 0x00000400
S.CLONE_SIGHAND = 0x00000800
S.CLONE_PTRACE  = 0x00002000
S.CLONE_VFORK   = 0x00004000
S.CLONE_PARENT  = 0x00008000
S.CLONE_THREAD  = 0x00010000
S.CLONE_NEWNS   = 0x00020000
S.CLONE_SYSVSEM = 0x00040000
S.CLONE_SETTLS  = 0x00080000
S.CLONE_PARENT_SETTID  = 0x00100000
S.CLONE_CHILD_CLEARTID = 0x00200000
S.CLONE_DETACHED = 0x00400000
S.CLONE_UNTRACED = 0x00800000
S.CLONE_CHILD_SETTID = 0x01000000
S.CLONE_NEWUTS   = 0x04000000
S.CLONE_NEWIPC   = 0x08000000
S.CLONE_NEWUSER  = 0x10000000
S.CLONE_NEWPID   = 0x20000000
S.CLONE_NEWNET   = 0x40000000
S.CLONE_IO       = 0x80000000

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

mt.inotify = {
  __index = function(t, k)
    local prefix = "IN_"
    if k:sub(1, #prefix) ~= prefix then k = prefix .. k:upper() end
    if S[k] then return bit.band(t.mask, S[k]) ~= 0 end
  end
}

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

-- capabilities
S.CAP_CHOWN = 0
S.CAP_DAC_OVERRIDE = 1
S.CAP_DAC_READ_SEARCH = 2
S.CAP_FOWNER = 3
S.CAP_FSETID = 4
S.CAP_KILL = 5
S.CAP_SETGID = 6
S.CAP_SETUID = 7
S.CAP_SETPCAP = 8
S.CAP_LINUX_IMMUTABLE = 9
S.CAP_NET_BIND_SERVICE = 10
S.CAP_NET_BROADCAST = 11
S.CAP_NET_ADMIN = 12
S.CAP_NET_RAW = 13
S.CAP_IPC_LOCK = 14
S.CAP_IPC_OWNER = 15
S.CAP_SYS_MODULE = 16
S.CAP_SYS_RAWIO = 17
S.CAP_SYS_CHROOT = 18
S.CAP_SYS_PTRACE = 19
S.CAP_SYS_PACCT = 20
S.CAP_SYS_ADMIN = 21
S.CAP_SYS_BOOT = 22
S.CAP_SYS_NICE = 23
S.CAP_SYS_RESOURCE = 24
S.CAP_SYS_TIME = 25
S.CAP_SYS_TTY_CONFIG = 26
S.CAP_MKNOD = 27
S.CAP_LEASE = 28
S.CAP_AUDIT_WRITE = 29
S.CAP_AUDIT_CONTROL = 30
S.CAP_SETFCAP = 31
S.CAP_MAC_OVERRIDE = 32
S.CAP_MAC_ADMIN = 33
S.CAP_SYSLOG = 34
S.CAP_WAKE_ALARM = 35

-- new SECCOMP modes, now there is filter as well as strict
S.SECCOMP_MODE_DISABLED = 0
S.SECCOMP_MODE_STRICT   = 1
S.SECCOMP_MODE_FILTER   = 2

S.SECCOMP_RET_KILL      = 0x00000000
S.SECCOMP_RET_TRAP      = 0x00030000
S.SECCOMP_RET_ERRNO     = 0x00050000
S.SECCOMP_RET_TRACE     = 0x7ff00000
S.SECCOMP_RET_ALLOW     = 0x7fff0000

S.SECCOMP_RET_ACTION    = 0xffff0000 -- note unsigned 
S.SECCOMP_RET_DATA      = 0x0000ffff

-- termios
S.NCCS = 32

-- termios - c_cc characters
S.VINTR    = 0
S.VQUIT    = 1
S.VERASE   = 2
S.VKILL    = 3
S.VEOF     = 4
S.VTIME    = 5
S.VMIN     = 6
S.VSWTC    = 7
S.VSTART   = 8
S.VSTOP    = 9
S.VSUSP    = 10
S.VEOL     = 11
S.VREPRINT = 12
S.VDISCARD = 13
S.VWERASE  = 14
S.VLNEXT   = 15
S.VEOL2    = 16

-- termios - c_iflag bits
S.IGNBRK  = octal('0000001')
S.BRKINT  = octal('0000002')
S.IGNPAR  = octal('0000004')
S.PARMRK  = octal('0000010')
S.INPCK   = octal('0000020')
S.ISTRIP  = octal('0000040')
S.INLCR   = octal('0000100')
S.IGNCR   = octal('0000200')
S.ICRNL   = octal('0000400')
S.IUCLC   = octal('0001000')
S.IXON    = octal('0002000')
S.IXANY   = octal('0004000')
S.IXOFF   = octal('0010000')
S.IMAXBEL = octal('0020000')
S.IUTF8   = octal('0040000')

-- termios - c_oflag bits
S.OPOST  = octal('0000001')
S.OLCUC  = octal('0000002')
S.ONLCR  = octal('0000004')
S.OCRNL  = octal('0000010')
S.ONOCR  = octal('0000020')
S.ONLRET = octal('0000040')
S.OFILL  = octal('0000100')
S.OFDEL  = octal('0000200')
S.NLDLY  = octal('0000400')
S.NL0    = octal('0000000')
S.NL1    = octal('0000400')
S.CRDLY  = octal('0003000')
S.CR0    = octal('0000000')
S.CR1    = octal('0001000')
S.CR2    = octal('0002000')
S.CR3    = octal('0003000')
S.TABDLY = octal('0014000')
S.TAB0   = octal('0000000')
S.TAB1   = octal('0004000')
S.TAB2   = octal('0010000')
S.TAB3   = octal('0014000')
S.BSDLY  = octal('0020000')
S.BS0    = octal('0000000')
S.BS1    = octal('0020000')
S.FFDLY  = octal('0100000')
S.FF0    = octal('0000000')
S.FF1    = octal('0100000')
S.VTDLY  = octal('0040000')
S.VT0    = octal('0000000')
S.VT1    = octal('0040000')
S.XTABS  = octal('0014000')

local bits_speed_map = { }
local speed_bits_map = { }
local function defspeed(speed, bits)
  bits = octal(bits)
  bits_speed_map[bits] = speed
  speed_bits_map[speed] = bits
  S['B'..speed] = bits
end
local function bits_to_speed(bits)
  local speed = bits_speed_map[bits]
  if not speed then error("unknown speedbits: " .. bits) end
  return speed
end
local function speed_to_bits(speed)
  local bits = speed_bits_map[speed]
  if not bits then error("unknown speed: " .. speed) end
  return bits
end
-- termios - c_cflag bit meaning
S.CBAUD      = octal('0010017')
defspeed(0, '0000000') -- hang up
defspeed(50, '0000001')
defspeed(75, '0000002')
defspeed(110, '0000003')
defspeed(134, '0000004')
defspeed(150, '0000005')
defspeed(200, '0000006')
defspeed(300, '0000007')
defspeed(600, '0000010')
defspeed(1200, '0000011')
defspeed(1800, '0000012')
defspeed(2400, '0000013')
defspeed(4800, '0000014')
defspeed(9600, '0000015')
defspeed(19200, '0000016')
defspeed(38400, '0000017')
S.EXTA       = S.B19200
S.EXTB       = S.B38400
S.CSIZE      = octal('0000060')
S.CS5        = octal('0000000')
S.CS6        = octal('0000020')
S.CS7        = octal('0000040')
S.CS8        = octal('0000060')
S.CSTOPB     = octal('0000100')
S.CREAD      = octal('0000200')
S.PARENB     = octal('0000400')
S.PARODD     = octal('0001000')
S.HUPCL      = octal('0002000')
S.CLOCAL     = octal('0004000')
S.CBAUDEX    = octal('0010000')
defspeed(57600, '0010001')
defspeed(115200, '0010002')
defspeed(230400, '0010003')
defspeed(460800, '0010004')
defspeed(500000, '0010005')
defspeed(576000, '0010006')
defspeed(921600, '0010007')
defspeed(1000000, '0010010')
defspeed(1152000, '0010011')
defspeed(1500000, '0010012')
defspeed(2000000, '0010013')
defspeed(2500000, '0010014')
defspeed(3000000, '0010015')
defspeed(3500000, '0010016')
defspeed(4000000, '0010017')
S.__MAX_BAUD = S.B4000000
S.CIBAUD     = octal('002003600000') -- input baud rate (not used)
S.CMSPAR     = octal('010000000000') -- mark or space (stick) parity
S.CRTSCTS    = octal('020000000000') -- flow control

-- termios - c_lflag bits
S.ISIG    = octal('0000001')
S.ICANON  = octal('0000002')
S.XCASE   = octal('0000004')
S.ECHO    = octal('0000010')
S.ECHOE   = octal('0000020')
S.ECHOK   = octal('0000040')
S.ECHONL  = octal('0000100')
S.NOFLSH  = octal('0000200')
S.TOSTOP  = octal('0000400')
S.ECHOCTL = octal('0001000')
S.ECHOPRT = octal('0002000')
S.ECHOKE  = octal('0004000')
S.FLUSHO  = octal('0010000')
S.PENDIN  = octal('0040000')
S.IEXTEN  = octal('0100000')

-- termios - tcflow() and TCXONC use these
S.TCOOFF = 0
S.TCOON  = 1
S.TCIOFF = 2
S.TCION  = 3

-- termios - tcflush() and TCFLSH use these
S.TCIFLUSH  = 0
S.TCOFLUSH  = 1
S.TCIOFLUSH = 2

-- termios - tcsetattr uses these
S.TCSANOW   = 0
S.TCSADRAIN = 1
S.TCSAFLUSH = 2

-- TIOCM ioctls
S.TIOCM_LE  = 0x001
S.TIOCM_DTR = 0x002
S.TIOCM_RTS = 0x004
S.TIOCM_ST  = 0x008
S.TIOCM_SR  = 0x010
S.TIOCM_CTS = 0x020
S.TIOCM_CAR = 0x040
S.TIOCM_RNG = 0x080
S.TIOCM_DSR = 0x100
S.TIOCM_CD  = S.TIOCM_CAR
S.TIOCM_RI  = S.TIOCM_RNG

-- syscalls, filling in as used at the minute
-- note ARM EABI same syscall numbers as x86, not tested on non eabi arm, will need offset added
if ffi.arch == "x86" then
  S.SYS_getpid           = 20
  S.SYS_stat             = 106
  S.SYS_fstat            = 108
  S.SYS_lstat            = 107
  S.SYS_clone            = 120
  S.SYS_getdents         = 141
  S.SYS_stat64           = 195
  S.SYS_lstat64          = 196
  S.SYS_fstat64          = 197
  S.SYS_getdents64       = 220
  S.SYS_io_setup         = 245
  S.SYS_io_destroy       = 246
  S.SYS_io_getevents     = 247
  S.SYS_io_submit        = 248
  S.SYS_io_cancel        = 249
  S.SYS_clock_settime    = 264
  S.SYS_clock_gettime    = 265
  S.SYS_clock_getres     = 266
  S.SYS_clock_nanosleep  = 267
elseif ffi.arch == "x64" then
  S.SYS_stat             = 4
  S.SYS_fstat            = 5
  S.SYS_lstat            = 6
  S.SYS_getpid           = 39
  S.SYS_clone            = 56
  S.SYS_getdents         = 78
  S.SYS_io_setup         = 206
  S.SYS_io_destroy       = 207
  S.SYS_io_getevents     = 208
  S.SYS_io_submit        = 209
  S.SYS_io_cancel        = 210
  S.SYS_getdents64       = 217
  S.SYS_clock_settime    = 227
  S.SYS_clock_gettime    = 228
  S.SYS_clock_getres     = 229
  S.SYS_clock_nanosleep  = 230
elseif ffi.arch == "arm" and ffi.abi("eabi") then
  S.SYS_getpid           = 20
  S.SYS_stat             = 106
  S.SYS_fstat            = 108
  S.SYS_lstat            = 107
  S.SYS_clone            = 120
  S.SYS_getdents         = 141
  S.SYS_stat64           = 195
  S.SYS_lstat64          = 196
  S.SYS_fstat64          = 197
  S.SYS_getdents64       = 217
  S.SYS_io_setup         = 243
  S.SYS_io_destroy       = 244
  S.SYS_io_getevents     = 245
  S.SYS_io_submit        = 246
  S.SYS_io_cancel        = 247
  S.SYS_clock_settime    = 262
  S.SYS_clock_gettime    = 263
  S.SYS_clock_getres     = 264
  S.SYS_clock_nanosleep  = 265
end

-- ioctls, filling in as needed
S.SIOCGIFINDEX   = 0x8933

S.SIOCBRADDBR    = 0x89a0
S.SIOCBRDELBR    = 0x89a1
S.SIOCBRADDIF    = 0x89a2
S.SIOCBRDELIF    = 0x89a3

S.TIOCMGET       = 0x5415
S.TIOCMBIS       = 0x5416
S.TIOCMBIC       = 0x5417
S.TIOCMSET       = 0x5418

-- sysfs values
S.SYSFS_BRIDGE_ATTR        = "bridge"
S.SYSFS_BRIDGE_FDB         = "brforward"
S.SYSFS_BRIDGE_PORT_SUBDIR = "brif"
S.SYSFS_BRIDGE_PORT_ATTR   = "brport"
S.SYSFS_BRIDGE_PORT_LINK   = "bridge"

-- sizes -- should we export?
local HOST_NAME_MAX = 64
local IFNAMSIZ      = 16
local IFHWADDRLEN   = 6

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

-- alternate names
S.E.EWOULDBLOCK    = S.E.EAGAIN
S.E.EDEADLOCK      = S.E.EDEADLK
S.E.ENOATTR        = S.E.ENODATA

local errsyms = {} -- reverse lookup
for k, v in pairs(S.E) do
  errsyms[v] = k
end

-- define C types
ffi.cdef[[

static const int UTSNAME_LENGTH = 65;

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
typedef int32_t daddr_t;

// 64 bit
typedef uint64_t dev_t;
typedef uint64_t loff_t;
typedef uint64_t off64_t;

// posix standards
typedef unsigned short int sa_family_t;

// typedefs which are word length
typedef unsigned long size_t;
typedef long ssize_t;
typedef long off_t;
typedef long kernel_off_t;
typedef long time_t;
typedef long blksize_t;
typedef long blkcnt_t;
typedef long clock_t;
typedef unsigned long ino_t;
typedef unsigned long nlink_t;
typedef unsigned long rlim_t;
typedef unsigned long aio_context_t;
typedef unsigned long nfds_t;

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
struct itimerspec {
  struct timespec it_interval;
  struct timespec it_value;
};
struct itimerval {
  struct timeval it_interval;
  struct timeval it_value;
};
// for uname.
struct utsname {
  char sysname[UTSNAME_LENGTH];
  char nodename[UTSNAME_LENGTH];
  char release[UTSNAME_LENGTH];
  char version[UTSNAME_LENGTH];
  char machine[UTSNAME_LENGTH];
  char domainname[UTSNAME_LENGTH]; // may not exist
};
struct iovec {
  void *iov_base;
  size_t iov_len;
};
struct pollfd {
  int fd;
  short int events;
  short int revents;
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
  void *msg_control;
  size_t msg_controllen;
  int msg_flags;
};
struct cmsghdr {
  size_t cmsg_len;
  int cmsg_level;
  int cmsg_type;
  //unsigned char cmsg_data[?]; /* causes issues with luaffi, pre C99 */
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
struct nlmsgerr {
  int             error;
  struct nlmsghdr msg;
};

static const int IFNAMSIZ = 16;

struct ifmap {
  unsigned long mem_start;
  unsigned long mem_end;
  unsigned short base_addr; 
  unsigned char irq;
  unsigned char dma;
  unsigned char port;
};
struct rtnl_link_stats {
  uint32_t rx_packets;
  uint32_t tx_packets;
  uint32_t rx_bytes;
  uint32_t tx_bytes;
  uint32_t rx_errors;
  uint32_t tx_errors;
  uint32_t rx_dropped;
  uint32_t tx_dropped;
  uint32_t multicast;
  uint32_t collisions;
  uint32_t rx_length_errors;
  uint32_t rx_over_errors;
  uint32_t rx_crc_errors;
  uint32_t rx_frame_errors;
  uint32_t rx_fifo_errors;
  uint32_t rx_missed_errors;
  uint32_t tx_aborted_errors;
  uint32_t tx_carrier_errors;
  uint32_t tx_fifo_errors;
  uint32_t tx_heartbeat_errors;
  uint32_t tx_window_errors;
  uint32_t rx_compressed;
  uint32_t tx_compressed;
};
typedef struct { 
  unsigned int clock_rate;
  unsigned int clock_type;
  unsigned short loopback;
} sync_serial_settings;
typedef struct { 
  unsigned int clock_rate;
  unsigned int clock_type;
  unsigned short loopback;
  unsigned int slot_map;
} te1_settings;
typedef struct {
  unsigned short encoding;
  unsigned short parity;
} raw_hdlc_proto;
typedef struct {
  unsigned int t391;
  unsigned int t392;
  unsigned int n391;
  unsigned int n392;
  unsigned int n393;
  unsigned short lmi;
  unsigned short dce;
} fr_proto;
typedef struct {
  unsigned int dlci;
} fr_proto_pvc;
typedef struct {
  unsigned int dlci;
  char master[IFNAMSIZ];
} fr_proto_pvc_info;
typedef struct {
  unsigned int interval;
  unsigned int timeout;
} cisco_proto;
struct if_settings {
  unsigned int type;
  unsigned int size;
  union {
    raw_hdlc_proto          *raw_hdlc;
    cisco_proto             *cisco;
    fr_proto                *fr;
    fr_proto_pvc            *fr_pvc;
    fr_proto_pvc_info       *fr_pvc_info;

    sync_serial_settings    *sync;
    te1_settings            *te1;
  } ifs_ifsu;
};
struct ifreq {
  union {
    char ifrn_name[IFNAMSIZ];
  } ifr_ifrn;
  union {
    struct  sockaddr ifru_addr;
    struct  sockaddr ifru_dstaddr;
    struct  sockaddr ifru_broadaddr;
    struct  sockaddr ifru_netmask;
    struct  sockaddr ifru_hwaddr;
    short   ifru_flags;
    int     ifru_ivalue;
    int     ifru_mtu;
    struct  ifmap ifru_map;
    char    ifru_slave[IFNAMSIZ];
    char    ifru_newname[IFNAMSIZ];
    void *  ifru_data;
    struct  if_settings ifru_settings;
  } ifr_ifru;
};
struct ifaddrmsg {
  uint8_t  ifa_family;
  uint8_t  ifa_prefixlen;
  uint8_t  ifa_flags;
  uint8_t  ifa_scope;
  uint32_t ifa_index;
};
struct ifa_cacheinfo {
  uint32_t ifa_prefered;
  uint32_t ifa_valid;
  uint32_t cstamp;
  uint32_t tstamp;
};
struct fdb_entry {
  uint8_t mac_addr[6];
  uint8_t port_no;
  uint8_t is_local;
  uint32_t ageing_timer_value;
  uint8_t port_hi;
  uint8_t pad0;
  uint16_t unused;
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
  kernel_off_t   d_off;
  unsigned short d_reclen;
  char           d_name[256];
};
struct linux_dirent64 {
  uint64_t             d_ino;
  int64_t              d_off;
  unsigned short  d_reclen;
  unsigned char   d_type;
  char            d_name[0];
};
struct stat {  /* only used on 64 bit architectures */
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
struct stat64 { /* only for 32 bit architectures */
  unsigned long long      st_dev;
  unsigned char   __pad0[4];
  unsigned long   __st_ino;
  unsigned int    st_mode;
  unsigned int    st_nlink;
  unsigned long   st_uid;
  unsigned long   st_gid;
  unsigned long long      st_rdev;
  unsigned char   __pad3[4];
  long long       st_size;
  unsigned long   st_blksize;
  unsigned long long      st_blocks;
  unsigned long   st_atime;
  unsigned long   st_atime_nsec;
  unsigned long   st_mtime;
  unsigned int    st_mtime_nsec;
  unsigned long   st_ctime;
  unsigned long   st_ctime_nsec;
  unsigned long long      st_ino;
};
typedef union epoll_data {
  void *ptr;
  int fd;
  uint32_t u32;
  uint64_t u64;
} epoll_data_t;
struct signalfd_siginfo {
  uint32_t ssi_signo;
  int32_t ssi_errno;
  int32_t ssi_code;
  uint32_t ssi_pid;
  uint32_t ssi_uid;
  int32_t ssi_fd;
  uint32_t ssi_tid;
  uint32_t ssi_band;
  uint32_t ssi_overrun;
  uint32_t ssi_trapno;
  int32_t ssi_status;
  int32_t ssi_int;
  uint64_t ssi_ptr;
  uint64_t ssi_utime;
  uint64_t ssi_stime;
  uint64_t ssi_addr;
  uint8_t __pad[48];
};
struct io_event {
  uint64_t           data;
  uint64_t           obj;
  int64_t            res;
  int64_t            res2;
};
struct seccomp_data {
  int nr;
  uint32_t arch;
  uint64_t instruction_pointer;
  uint64_t args[6];
};
struct ustat {
  daddr_t f_tfree;
  ino_t f_tinode;
  char f_fname[6];
  char f_fpack[6];
};

/* termios */
typedef unsigned char	cc_t;
typedef unsigned int	speed_t;
typedef unsigned int	tcflag_t;
struct termios
  {
    tcflag_t c_iflag;		/* input mode flags */
    tcflag_t c_oflag;		/* output mode flags */
    tcflag_t c_cflag;		/* control mode flags */
    tcflag_t c_lflag;		/* local mode flags */
    cc_t c_line;			/* line discipline */
    cc_t c_cc[32];		/* control characters */
    speed_t c_ispeed;		/* input speed */
    speed_t c_ospeed;		/* output speed */
  };
]]

-- sigaction is a union on x86. note luajit supports anonymous unions, which simplifies usage
-- it appears that there is no kernel sigaction in non x86 architectures? Need to check source.
-- presumably does not care, but the types are a bit of a pain.
-- temporarily just going to implement sighandler support
if ffi.arch == 'x86' then
ffi.cdef[[
struct sigaction {
  union {
    sighandler_t sa_handler;
    void (*sa_sigaction)(int, struct siginfo *, void *);
  };
  sigset_t sa_mask;
  unsigned long sa_flags;
  void (*sa_restorer)(void);
};
]]
else
ffi.cdef[[
struct sigaction {
  sighandler_t sa_handler;
  unsigned long sa_flags;
  void (*sa_restorer)(void);
  sigset_t sa_mask;
};
]]
end

-- Linux struct siginfo padding depends on architecture, also statfs
if ffi.abi("64bit") then
ffi.cdef[[
static const int SI_MAX_SIZE = 128;
static const int SI_PAD_SIZE = (SI_MAX_SIZE / sizeof (int)) - 4;
typedef long statfs_word;
]]
else
ffi.cdef[[
static const int SI_MAX_SIZE = 128;
static const int SI_PAD_SIZE = (SI_MAX_SIZE / sizeof (int)) - 3;
typedef uint32_t statfs_word;
]]
end

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

typedef struct {
  int     val[2];
} kernel_fsid_t;

struct statfs64 {
  statfs_word f_type;
  statfs_word f_bsize;
  uint64_t f_blocks;
  uint64_t f_bfree;
  uint64_t f_bavail;
  uint64_t f_files;
  uint64_t f_ffree;
  kernel_fsid_t f_fsid;
  statfs_word f_namelen;
  statfs_word f_frsize;
  statfs_word f_flags;
  statfs_word f_spare[4];
};
]]

-- epoll packed on x86_64 only (so same as x86)
if ffi.arch == "x64" then
ffi.cdef[[
struct epoll_event {
  uint32_t events;      /* Epoll events */
  epoll_data_t data;    /* User data variable */
}  __attribute__ ((packed));
]]
else
ffi.cdef[[
struct epoll_event {
  uint32_t events;      /* Epoll events */
  epoll_data_t data;    /* User data variable */
};
]]
end

-- endian dependent
if ffi.abi("le") then
ffi.cdef[[
struct iocb {
  uint64_t   aio_data;
  uint32_t   aio_key, aio_reserved1;

  uint16_t   aio_lio_opcode;
  int16_t    aio_reqprio;
  uint32_t   aio_fildes;

  uint64_t   aio_buf;
  uint64_t   aio_nbytes;
  int64_t    aio_offset;

  uint64_t   aio_reserved2;

  uint32_t   aio_flags;

  uint32_t   aio_resfd;
};
]]
else
ffi.cdef[[
struct iocb {
  uint64_t   aio_data;
  uint32_t   aio_reserved1, aio_key;

  uint16_t   aio_lio_opcode;
  int16_t    aio_reqprio;
  uint32_t   aio_fildes;

  uint64_t   aio_buf;
  uint64_t   aio_nbytes;
  int64_t    aio_offset;

  uint64_t   aio_reserved2;

  uint32_t   aio_flags;

  uint32_t   aio_resfd;
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
int sigaction(int signum, const struct sigaction *act, struct sigaction *oldact);
int kill(pid_t pid, int sig);
int gettimeofday(struct timeval *tv, void *tz);   /* not even defining struct timezone */
int settimeofday(const struct timeval *tv, const void *tz);
int getitimer(int which, struct itimerval *curr_value);
int setitimer(int which, const struct itimerval *new_value, struct itimerval *old_value);
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
int signalfd(int fd, const sigset_t *mask, int flags);
int timerfd_create(int clockid, int flags);
int timerfd_settime(int fd, int flags, const struct itimerspec *new_value, struct itimerspec *old_value);
int timerfd_gettime(int fd, struct itimerspec *curr_value);

ssize_t read(int fd, void *buf, size_t count);
ssize_t write(int fd, const void *buf, size_t count);
ssize_t pread64(int fd, void *buf, size_t count, loff_t offset);
ssize_t pwrite64(int fd, const void *buf, size_t count, loff_t offset);
loff_t llseek(int fd, loff_t offset, int whence);  /* note could use _llseek the syscall instead */
ssize_t send(int sockfd, const void *buf, size_t len, int flags);
// for sendto and recvfrom use void poointer not const struct sockaddr * to avoid casting
ssize_t sendto(int sockfd, const void *buf, size_t len, int flags, const void *dest_addr, socklen_t addrlen);
ssize_t recvfrom(int sockfd, void *buf, size_t len, int flags, void *src_addr, socklen_t *addrlen);
ssize_t sendmsg(int sockfd, const struct msghdr *msg, int flags);
ssize_t recv(int sockfd, void *buf, size_t len, int flags);
ssize_t recvmsg(int sockfd, struct msghdr *msg, int flags);
ssize_t readv(int fd, const struct iovec *iov, int iovcnt);
ssize_t writev(int fd, const struct iovec *iov, int iovcnt);
int getsockopt(int sockfd, int level, int optname, void *optval, socklen_t *optlen);
int setsockopt(int sockfd, int level, int optname, const void *optval, socklen_t optlen);
int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, struct timeval *timeout);
int poll(struct pollfd *fds, nfds_t nfds, int timeout);
ssize_t readlink(const char *path, char *buf, size_t bufsiz);

int epoll_create1(int flags);
int epoll_create(int size);
int epoll_ctl(int epfd, int op, int fd, struct epoll_event *event);
int epoll_wait(int epfd, struct epoll_event *events, int maxevents, int timeout);
int epoll_pwait(int epfd, struct epoll_event *events, int maxevents, int timeout, const sigset_t *sigmask);
ssize_t sendfile(int out_fd, int in_fd, off_t *offset, size_t count);
int eventfd(unsigned int initval, int flags);
ssize_t splice(int fd_in, loff_t *off_in, int fd_out, loff_t *off_out, size_t len, unsigned int flags);
ssize_t vmsplice(int fd, const struct iovec *iov, unsigned long nr_segs, unsigned int flags);
ssize_t tee(int fd_in, int fd_out, size_t len, unsigned int flags);
int reboot(int cmd);
int klogctl(int type, char *bufp, int len);
int inotify_init1(int flags);
int inotify_add_watch(int fd, const char *pathname, uint32_t mask);
int inotify_rm_watch(int fd, uint32_t wd);
int adjtimex(struct timex *buf);
int sync_file_range(int fd, loff_t offset, loff_t count, unsigned int flags);
ssize_t listxattr (const char *path, char *list, size_t size);
ssize_t llistxattr (const char *path, char *list, size_t size);
ssize_t flistxattr (int filedes, char *list, size_t size);
ssize_t getxattr (const char *path, const char *name, void *value, size_t size);
ssize_t lgetxattr (const char *path, const char *name, void *value, size_t size);
ssize_t fgetxattr (int filedes, const char *name, void *value, size_t size);
int setxattr (const char *path, const char *name, const void *value, size_t size, int flags);
int lsetxattr (const char *path, const char *name, const void *value, size_t size, int flags);
int fsetxattr (int filedes, const char *name, const void *value, size_t size, int flags);
int removexattr (const char *path, const char *name);
int lremovexattr (const char *path, const char *name);
int fremovexattr (int filedes, const char *name);

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
int truncate64(const char *path, loff_t length);
int ftruncate64(int fd, loff_t length);
int pause(void);
int getrlimit(int resource, struct rlimit *rlim);
int setrlimit(int resource, const struct rlimit *rlim);

int socket(int domain, int type, int protocol);
int socketpair(int domain, int type, int protocol, int sv[2]);
int bind(int sockfd, const void *addr, socklen_t addrlen); // void not struct
int listen(int sockfd, int backlog);
int connect(int sockfd, const void *addr, socklen_t addrlen);
int accept(int sockfd, void *addr, socklen_t *addrlen);
int accept4(int sockfd, void *addr, socklen_t *addrlen, int flags);
int getsockname(int sockfd, void *addr, socklen_t *addrlen);
int getpeername(int sockfd, void *addr, socklen_t *addrlen);
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
int posix_fadvise(int fd, off_t offset, off_t len, int advice);
int fallocate(int fd, int mode, off_t offset, off_t len);
ssize_t readahead(int fd, off64_t offset, size_t count);

int pipe(int pipefd[2]);
int pipe2(int pipefd[2], int flags);
int mount(const char *source, const char *target, const char *filesystemtype, unsigned long mountflags, const void *data);
int umount(const char *target);
int umount2(const char *target, int flags);

int nanosleep(const struct timespec *req, struct timespec *rem);
int access(const char *pathname, int mode);
char *getcwd(char *buf, size_t size);
int ustat(dev_t dev, struct ustat *ubuf);
int statfs(const char *path, struct statfs64 *buf); /* this is statfs64 syscall, but glibc wraps */
int fstatfs(int fd, struct statfs64 *buf);          /* this too */
int futimens(int fd, const struct timespec times[2]);
int unshare(int flags);

int syscall(int number, ...);

int ioctl(int d, int request, void *argp); /* void* easiest here */

// functions from libc ie man 3 not man 2
void exit(int status);
int inet_aton(const char *cp, struct in_addr *inp);
char *inet_ntoa(struct in_addr in);
int inet_pton(int af, const char *src, void *dst);
const char *inet_ntop(int af, const void *src, char *dst, socklen_t size);

// functions from libc that could be exported as a convenience, used internally
char *strerror(int);
// env. dont support putenv, as does not copy which is an issue
extern char **environ;
int setenv(const char *name, const char *value, int overwrite);
int unsetenv(const char *name);
int clearenv(void);
char *getenv(const char *name);

int tcgetattr(int fd, struct termios *termios_p);
int tcsetattr(int fd, int optional_actions, const struct termios *termios_p);
int tcsendbreak(int fd, int duration);
int tcdrain(int fd);
int tcflush(int fd, int queue_selector);
int tcflow(int fd, int action);
void cfmakeraw(struct termios *termios_p);
speed_t cfgetispeed(const struct termios *termios_p);
speed_t cfgetospeed(const struct termios *termios_p);
int cfsetispeed(struct termios *termios_p, speed_t speed);
int cfsetospeed(struct termios *termios_p, speed_t speed);
int cfsetspeed(struct termios *termios_p, speed_t speed);
pid_t tcgetsid(int fd);

int posix_openpt(int flags);
int grantpt(int fd);
int unlockpt(int fd);
int ptsname_r(int fd, char *buf, size_t buflen);
]]

-- use 64 bit fileops on 32 bit always
local C64, stattypename
if ffi.abi("64bit") then
  stattypename = "struct stat"
  C64 = {
    truncate = C.truncate,
    ftruncate = C.ftruncate,
  }
else
  stattypename = "struct stat64"
  S.SYS_stat = S.SYS_stat64
  S.SYS_lstat = S.SYS_lstat64
  S.SYS_fstat = S.SYS_fstat64
  C64 = {
    truncate = C.truncate64,
    ftruncate = C.ftruncate64,
  }
end

-- functions we need for metatypes

local function getfd(fd)
  if ffi.istype(t.fd, fd) then return fd.fileno end
  return fd
end

local function split(delimiter, text)
  if delimiter == "" then return {text} end
  if #text == 0 then return {} end
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

local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- take a bunch of flags in a string and return a number
-- note if using with 64 bit flags will have to change to use a 64 bit number, currently assumes 32 bit, as uses bitops
-- also forcing to return an int now - TODO find any 64 bit flags we are using and fix to use new function
local function stringflags(str, prefix, prefix2) -- allows multiple comma sep flags that are ORed
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

local function stringflag(str, prefix) -- single value only
  if not str then return 0 end
  if type(str) ~= "string" then return str end
  if #str == 0 then return 0 end
  local s = trim(str)
  if s:sub(1, #prefix) ~= prefix then s = prefix .. s end -- prefix optional
  local val = S[s:upper()]
  if not val then error("invalid flag: " .. s) end -- don't use this format if you don't want exceptions, better than silent ignore
  return val
end

local function accessflags(s) -- allow "rwx"
  if not s then return 0 end
  if type(s) ~= "string" then return s end
  s = trim(s:upper())
  local flag = 0
  for i = 1, #s do
    local c = s:sub(i, i)
    if     c == 'R' then flag = bit.bor(flag, S.R_OK)
    elseif c == 'W' then flag = bit.bor(flag, S.W_OK)
    elseif c == 'X' then flag = bit.bor(flag, S.X_OK)
    else error("invalid access flag") end
  end
  return flag
end

-- useful for comparing modes etc
function S.mode(mode) return stringflags(mode, "S_") end

-- Lua type constructors corresponding to defined types
-- basic types
t.char = ffi.typeof("char")
t.uchar = ffi.typeof("unsigned char")
t.int = ffi.typeof("int")
t.uint = ffi.typeof("unsigned int")
t.int32 = ffi.typeof("int32_t")
t.uint32 = ffi.typeof("uint32_t")
t.int64 = ffi.typeof("int64_t")
t.uint64 = ffi.typeof("uint64_t")
t.long = ffi.typeof("long")
t.ulong = ffi.typeof("unsigned long")
t.uintptr = ffi.typeof("uintptr_t")

t.sa_family = ffi.typeof("sa_family_t")
t.msghdr = ffi.typeof("struct msghdr")
t.cmsghdr = ffi.typeof("struct cmsghdr")
t.ucred = ffi.typeof("struct ucred")
t.sysinfo = ffi.typeof("struct sysinfo")
t.fdset = ffi.typeof("fd_set")
t.fdmask = ffi.typeof("fd_mask")
t.epoll_event = ffi.typeof("struct epoll_event")
t.off = ffi.typeof("off_t")
t.nlmsghdr = ffi.typeof("struct nlmsghdr")
t.rtgenmsg = ffi.typeof("struct rtgenmsg")
t.ifinfomsg = ffi.typeof("struct ifinfomsg")
t.ifaddrmsg = ffi.typeof("struct ifaddrmsg")
t.rtattr = ffi.typeof("struct rtattr")
t.nlmsgerr = ffi.typeof("struct nlmsgerr")
t.timex = ffi.typeof("struct timex")
t.utsname = ffi.typeof("struct utsname")
t.rlimit = ffi.typeof("struct rlimit")
t.fdb_entry = ffi.typeof("struct fdb_entry")
t.signalfd_siginfo = ffi.typeof("struct signalfd_siginfo")
t.iocb = ffi.typeof("struct iocb")
t.sighandler = ffi.typeof("sighandler_t")
t.sigaction = ffi.typeof("struct sigaction")
t.clockid = ffi.typeof("clockid_t")
t.inotify_event = ffi.typeof("struct inotify_event")
t.loff = ffi.typeof("loff_t")
t.io_event = ffi.typeof("struct io_event")
t.seccomp_data = ffi.typeof("struct seccomp_data")
t.iovec = ffi.typeof("struct iovec")
t.rtnl_link_stats = ffi.typeof("struct rtnl_link_stats")
t.ustat = ffi.typeof("struct ustat")
t.statfs = ffi.typeof("struct statfs64")
t.ifreq = ffi.typeof("struct ifreq")
t.linux_dirent64 = ffi.typeof("struct linux_dirent64")
t.ifa_cacheinfo = ffi.typeof("struct ifa_cacheinfo")

t.epoll_events = ffi.typeof("struct epoll_event[?]") -- TODO add metatable, like pollfds
t.io_events = ffi.typeof("struct io_event[?]")
t.iocbs = ffi.typeof("struct iocb[?]")

t.iocb_ptrs = ffi.typeof("struct iocb *[?]")
t.string_array = ffi.typeof("const char *[?]")

t.ints = ffi.typeof("int[?]")
t.buffer = ffi.typeof("char[?]")

t.int1 = ffi.typeof("int[1]")
t.int64_1 = ffi.typeof("int64_t[1]")
t.uint64_1 = ffi.typeof("uint64_t[1]")
t.socklen1 = ffi.typeof("socklen_t[1]")
t.off1 = ffi.typeof("off_t[1]")
t.loff1 = ffi.typeof("loff_t[1]")

t.int2 = ffi.typeof("int[2]")
t.timespec2 = ffi.typeof("struct timespec[2]")

-- types with metatypes
t.error = ffi.metatype("struct {int errno;}", {
  __tostring = function(e) return S.strerror(e.errno) end,
  __index = function(t, k)
    if k == 'sym' then return errsyms[t.errno] end
    if k == 'lsym' then return errsyms[t.errno]:sub(2):lower() end
    if S.E[k] then return S.E[k] == t.errno end
    local uk = S.E['E' .. k:upper()]
    if uk then return uk == t.errno end
  end,
  __new = function(tp, errno)
    if not errno then errno = ffi.errno() end
    return ffi.new(tp, errno)
  end
})

t.sockaddr = ffi.metatype("struct sockaddr", {
  __index = function(sa, k)
    local meth = {
      family = function(sa) return tonumber(sa.sa_family) end,
    }
    if meth[k] then return meth[k](sa) end
  end
})

t.sockaddr_storage = ffi.metatype("struct sockaddr_storage", {
  __index = function(sa, k)
    local meth = {
      family = function(sa) return tonumber(sa.ss_family) end,
    }
    if meth[k] then return meth[k](sa) end  end
})

t.sockaddr_in = ffi.metatype("struct sockaddr_in", {
  __index = function(sa, k)
    local meth = {
      family = function(sa) return tonumber(sa.sin_family) end,
      port = function(sa) return S.ntohs(sa.sin_port) end,
      addr = function(sa) return sa.sin_addr end,
    }
    if meth[k] then return meth[k](sa) end
  end,
  __newindex = function(sa, k, v)
    meth = {
      port = function(sa, v) sa.sin_port = S.htons(v) end
    }
    if meth[k] then meth[k](sa, v) end
  end,
  __new = function(tp, port, addr)
    if not ffi.istype(t.in_addr, addr) then
      addr = t.in_addr(addr)
      if not addr then return end
    end
    return ffi.new(tp, S.AF_INET, S.htons(port or 0), addr)
  end
})

t.sockaddr_in6 = ffi.metatype("struct sockaddr_in6", {
  __index = function(sa, k)
    local meth = {
      family = function(sa) return tonumber(sa.sin6_family) end,
      port = function(sa) return S.ntohs(sa.sin6_port) end,
      addr = function(sa) return sa.sin6_addr end,
    }
    if meth[k] then return meth[k](sa) end
  end,
  __newindex = function(sa, k, v)
    meth = {
      port = function(sa, v) sa.sin6_port = S.htons(v) end
    }
    if meth[k] then meth[k](sa, v) end
  end,
  __new = function(tp, port, addr, flowinfo, scope_id) -- reordered initialisers. should we allow table init too?
    if not ffi.istype(t.in6_addr, addr) then
      addr = t.in6_addr(addr)
      if not addr then return end
    end
    return ffi.new(tp, S.AF_INET6, S.htons(port or 0), flowinfo or 0, addr, scope_id or 0)
  end
})

t.sockaddr_un = ffi.metatype("struct sockaddr_un", {
  __index = function(sa, k)
    local meth = {
      family = function(sa) return tonumber(sa.un_family) end,
    }
    if meth[k] then return meth[k](sa) end
  end,
  __new = function(tp)
    return ffi.new(tp, S.AF_UNIX)
  end
})

t.sockaddr_nl = ffi.metatype("struct sockaddr_nl", {
  __index = function(sa, k)
    local meth = {
      family = function(sa) return tonumber(sa.nl_family) end,
      pid = function(sa) return tonumber(sa.nl_pid) end,
      groups = function(sa) return tonumber(sa.nl_groups) end,
    }
    if meth[k] then return meth[k](sa) end
  end,
  __new = function(tp, pid, groups)
    return ffi.new(tp, S.AF_NETLINK, pid or 0, groups or 0)
  end
})

t.stat = ffi.metatype(stattypename, { -- either struct stat on 64 bit or struct stat64 on 32 bit
  __index = function(st, k)
  local meth = {
    dev = function(st) return tonumber(st.st_dev) end,
    ino = function(st) return tonumber(st.st_ino) end,
    mode = function(st) return tonumber(st.st_mode) end,
    nlink = function(st) return tonumber(st.st_nlink) end,
    uid = function(st) return tonumber(st.st_uid) end,
    gid = function(st) return tonumber(st.st_gid) end,
    rdev = function(st) return tonumber(st.st_rdev) end,
    size = function(st) return tonumber(st.st_size) end,
    blksize = function(st) return tonumber(st.st_blksize) end,
    blocks = function(st) return tonumber(st.st_blocks) end,
    atime = function(st) return tonumber(st.st_atime) end,
    ctime = function(st) return tonumber(st.st_ctime) end,
    mtime = function(st) return tonumber(st.st_mtime) end,
    major = function(st) return S.major(st.st_rdev) end,
    minor = function(st) return S.minor(st.st_rdev) end,
    isreg = function(st) return S.S_ISREG(st.st_mode) end,
    isdir = function(st) return S.S_ISDIR(st.st_mode) end,
    ischr = function(st) return S.S_ISCHR(st.st_mode) end,
    isblk = function(st) return S.S_ISBLK(st.st_mode) end,
    isfifo = function(st) return S.S_ISFIFO(st.st_mode) end,
    islnk = function(st) return S.S_ISLNK(st.st_mode) end,
    issock = function(st) return S.S_ISSOCK(st.st_mode) end
  }
  if meth[k] then return meth[k](st) end
  end
})

t.siginfo = ffi.metatype("struct siginfo", {
  __index = function(t, k)
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
  if siginfo_get[k] then return siginfo_get[k](t) end
  end,
  __newindex = function(t, k, v)
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
  if siginfo_set[k] then siginfo_set[k](t, v) end
  end
})

t.macaddr = ffi.metatype("struct {uint8_t mac_addr[6];}", {
  __tostring = function(m)
    local hex = {}
    for i = 1, 6 do
      hex[i] = string.format("%02x", m.mac_addr[i - 1])
    end
    return table.concat(hex, ":")
  end
})

t.timeval = ffi.metatype("struct timeval", {
  __index = function(tv, k)
  local meth = {
    time = function(tv) return tonumber(tv.tv_sec) + tonumber(tv.tv_usec) / 1000000 end,
    sec = function(tv) return tonumber(tv.tv_sec) end,
    usec = function(tv) return tonumber(tv.tv_usec) end
  }
  if meth[k] then return meth[k](tv) end
  end,
  __newindex = function(tv, k, v)
    local meth = {
      time = function(tv, v)
        local i, f = math.modf(v)
        tv.tv_sec, tv.tv_usec = i, math.floor(f * 1000000)
      end,
      sec = function(tv, v) tv.tv_sec = v end,
      usec = function(tv, v) tv.tv_usec = v end
    }
    if meth[k] then meth[k](tv, v) end
  end,
  __new = function(tp, v)
    if not v then v = {0, 0} end
    if type(v) ~= "number" then return ffi.new(tp, v) end
    local ts = ffi.new(tp)
    ts.time = v
    return ts
  end
})

t.timespec = ffi.metatype("struct timespec", {
  __index = function(tv, k)
    local meth = {
      time = function(tv) return tonumber(tv.tv_sec) + tonumber(tv.tv_nsec) / 1000000000 end,
      sec = function(tv) return tonumber(tv.tv_sec) end,
      nsec = function(tv) return tonumber(tv.tv_nsec) end
    }
  if meth[k] then return meth[k](tv) end
  end,
  __newindex = function(tv, k, v)
    local meth = {
      time = function(tv, v)
        local i, f = math.modf(v)
        tv.tv_sec, tv.tv_nsec = i, math.floor(f * 1000000000)
      end,
      sec = function(tv, v) tv.tv_sec = v end,
      nsec = function(tv, v) tv.tv_nsec = v end
    }
    if meth[k] then meth[k](tv, v) end
  end,
  __new = function(tp, v)
    if not v then v = {0, 0} end
    if type(v) ~= "number" then return ffi.new(tp, v) end
    local ts = ffi.new(tp)
    ts.time = v
    return ts
  end
})

local function itnormal(v)
  if not v then v = {{0, 0}, {0, 0}} end
  if v.interval then
    v.it_interval = v.interval
    v.interval = nil
  end
  if v.value then
    v.it_value = v.value
    v.value = nil
  end
  if not v.it_interval then
    v.it_interval = v[1]
    v[1] = nil
  end
  if not v.it_value then
    v.it_value = v[2]
    v[2] = nil
  end
  return v
end

t.itimerspec = ffi.metatype("struct itimerspec", {
  __index = function(it, k)
  local meth = {
    interval = function(it) return it.it_interval end,
    value = function(it) return it.it_value end
  }
  return meth[k](it)
  end,
  __new = function(tp, v)
    v = itnormal(v)
    if not ffi.istype(t.timespec, v.it_interval) then v.it_interval = t.timespec(v.it_interval) end
    if not ffi.istype(t.timespec, v.it_value) then v.it_value = t.timespec(v.it_value) end
    return ffi.new(tp, v)
  end
})

t.itimerval = ffi.metatype("struct itimerval", {
  __index = function(it, k)
  local meth = {
    interval = function(it) return it.it_interval end,
    value = function(it) return it.it_value end
  }
  return meth[k](it)
  end,
  __new = function(tp, v)
    v = itnormal(v)
   if not ffi.istype(t.timeval, v.it_interval) then v.it_interval = t.timeval(v.it_interval) end
    if not ffi.istype(t.timeval, v.it_value) then v.it_value = t.timeval(v.it_value) end
    return ffi.new(tp, v)
  end
})

mt.iovecs = {
  __index = function(io, k)
    return io.iov[k - 1]
  end,
  __newindex = function(io, k, v)
    if not ffi.istype(t.iovec, v) then v = t.iovec(v) end
    ffi.copy(io.iov[k - 1], v, ffi.sizeof(t.iovec))
  end,
  __len = function(io) return io.count end,
  __new = function(tp, is)
    if type(is) == 'number' then return ffi.new(tp, is, is) end
    local count = #is
    local iov = ffi.new(tp, count, count)
    for n = 1, count do
      local i = is[n]
      if type(i) == 'string' then
        local buf = t.buffer(#i)
        ffi.copy(buf, i, #i)
        iov[n].iov_base = buf
        iov[n].iov_len = #i
      elseif type(i) == 'number' then
        iov[n].iov_base = t.buffer(i)
        iov[n].iov_len = i
      else
        iov[n] = i
      end
    end
    return iov
  end
}

t.iovecs = ffi.metatype("struct { int count; struct iovec iov[?];}", mt.iovecs)

t.pollfd = ffi.metatype("struct pollfd", {
  __index = function(t, k)
    if k == 'fileno' then return t.fd end
    local prefix = "POLL"
    if k:sub(1, #prefix) ~= prefix then k = prefix .. k:upper() end
    return bit.band(t.revents, S[k]) ~= 0
  end
})

mt.pollfds = {
  __index = function(p, k)
    return p.pfd[k - 1]
  end,
  __newindex = function(p, k, v)
    if not ffi.istype(t.pollfd, v) then v = t.pollfd(v) end
    ffi.copy(p.pfd[k - 1], v, ffi.sizeof(t.pollfd))
  end,
  __len = function(p) return p.count end,
  __new = function(tp, ps)
    if type(ps) == 'number' then return ffi.new(tp, ps, ps) end
    local count = #ps
    local fds = ffi.new(tp, count, count)
    for n = 1, count do
      fds[n].fd = getfd(ps[n].fd)
      fds[n].events = stringflags(ps[n].events, "POLL")
      fds[n].revents = 0
    end
    return fds
  end
}

t.pollfds = ffi.metatype("struct { int count; struct pollfd pfd[?];}", mt.pollfds)

t.in_addr = ffi.metatype("struct in_addr", {
  __tostring = function(a) return S.inet_ntoa(a) end,
  __new = function(tp, s)
    local addr = ffi.new(tp)
    if s then addr = S.inet_aton(s, addr) end
    return addr
  end
})

t.in6_addr = ffi.metatype("struct in6_addr", {
  __tostring = function(a) return S.inet_ntop(S.AF_INET6, a) end,
  __new = function(tp, s)
    local addr = ffi.new(tp)
    if s then addr = S.inet_pton(S.AF_INET6, s, addr) end
    return addr
  end
})

S.addrtype = {
  [S.AF_INET] = t.in_addr,
  [S.AF_INET6] = t.in6_addr,
}

-- cast to pointer to a type. could generate for all types.
local function ptt(tp)
  local ptp = ffi.typeof("$ *", tp)
  return function(x) return ffi.cast(ptp, x) end
end

pt.uchar = ptt(t.uchar)
pt.char = ptt(t.char)
pt.int = ptt(t.int)
pt.uint = ptt(t.uint)

pt.nlmsghdr = ptt(t.nlmsghdr)
pt.rtattr = ptt(t.rtattr)
pt.ifinfomsg = ptt(t.ifinfomsg)
pt.ifaddrmsg = ptt(t.ifaddrmsg)
pt.nlmsgerr = ptt(t.nlmsgerr)
pt.cmsghdr = ptt(t.cmsghdr)
pt.fdb_entry = ptt(t.fdb_entry)
pt.signalfd_siginfo = ptt(t.signalfd_siginfo)
pt.linux_dirent64 = ptt(t.linux_dirent64)
pt.inotify_event = ptt(t.inotify_event)
pt.ucred = ptt(t.ucred)

pt.void = function(x)
  local vp = ffi.typeof("void *")
  return ffi.cast(vp, x)
end

-- misc

-- luaffi did need some help casting number to pointer. maybe fixed now, check.
--S.pointer = function(i) return pt.void(ffi.cast(t.uintptr, i)) end
S.pointer = pt.void

local function div(a, b) return math.floor(tonumber(a) / tonumber(b)) end -- would be nicer if replaced with shifts, as only powers of 2

function S.nogc(d) ffi.gc(d, nil) end

-- return helpers. not so much needed any more, often not using

-- straight passthrough, only needed for real 64 bit quantities. Used eg for seek (file might have giant holes!)
local function ret64(ret)
  if ret == t.uint64(-1) then return nil, t.error() end
  return ret
end

local function retnum(ret) -- return Lua number where double precision ok, eg file ops etc
  ret = tonumber(ret)
  if ret == -1 then return nil, t.error() end
  return ret
end

local function retfd(ret)
  if ret == -1 then return nil, t.error() end
  return t.fd(ret)
end

-- used for no return value, return true for use of assert
local function retbool(ret)
  if ret == -1 then return nil, t.error() end
  return true
end

-- used for pointer returns, -1 is failure; removed gc for mem
local function retptr(ret)
  if ret == S.pointer(-1) then return nil, t.error() end
  return ret
end

mt.wait = {
  __index = function(w, k)
    local WTERMSIG = bit.band(w.status, 0x7f)
    local EXITSTATUS = bit.rshift(bit.band(w.status, 0xff00), 8)
    local WIFEXITED = (WTERMSIG == 0)
    local tab = {
      WIFEXITED = WIFEXITED,
      WIFSTOPPED = bit.band(w.status, 0xff) == 0x7f,
      WIFSIGNALED = not WIFEXITED and bit.band(w.status, 0x7f) ~= 0x7f -- I think this is right????? TODO recheck, cleanup
    }
    if tab.WIFEXITED then tab.EXITSTATUS = EXITSTATUS end
    if tab.WIFSTOPPED then tab.WSTOPSIG = EXITSTATUS end
    if tab.WIFSIGNALED then tab.WTERMSIG = WTERMSIG end
    if tab[k] then return tab[k] end
    local uc = 'W' .. k:upper()
    if tab[uc] then return tab[uc] end
  end
}

local function retwait(ret, status)
  if ret == -1 then return nil, t.error() end
  return setmetatable({pid = ret, status = status}, mt.wait)
end

-- endian conversion
if ffi.abi("be") then -- nothing to do
  function S.htonl(b) return b end
else
  function S.htonl(b) return bit.bswap(b) end
  function S.htons(b) return bit.rshift(bit.bswap(b), 16) end
end
S.ntohl = S.htonl -- reverse is the same
S.ntohs = S.htons -- reverse is the same

-- we should be adding padding at the end of size nlmsg_alignto (4), (and in middle but 0) or will have issues if try to send more messages. So need to pass align function.
local function tbuffer(...) -- helper function for sequence of types in a buffer
  local function threc(buf, offset, tp, ...) -- alignment issues, need to round up to minimum alignment
    if not tp then return nil end
    local p = ptt(tp)
    if select("#", ...) == 0 then return p(buf + offset) end
    return p(buf + offset), threc(buf, offset + ffi.sizeof(tp), ...)
  end
  local len = 0
  for _, tp in ipairs{...} do
    len = len + ffi.sizeof(tp) -- TODO alignment issues, need to round up to minimum alignment, or as supplied
  end
  local buf = t.buffer(len)
  return buf, len, threc(buf, 0, ...)
end

-- cast socket address to actual type based on family
local samap = {
  [S.AF_UNIX] = t.sockaddr_un,
  [S.AF_INET] = t.sockaddr_in,
  [S.AF_INET6] = t.sockaddr_in6,
  [S.AF_NETLINK] = t.sockaddr_nl,
}

-- TODO add tests
mt.sockaddr_un = {
  __index = function(un, k)
    local sa = un.addr
    if k == 'sun_family' then return sa.sun_family end
    if k == 'family' then return tonumber(sa.sun_family) end
    local namelen = un.addrlen - ffi.sizeof(t.sun_family)
    if namelen > 0 then
      if sa.sun_path[0] == 0 then
        if k == 'abstract' then return true end
        if k == 'name' then return ffi.string(rets.addr.sun_path, namelen) end -- should we also remove leading \0?
      else
        if k == 'name' then return ffi.string(rets.addr.sun_path) end
      end
    else
      if k == 'unnamed' then return true end
    end
  end
}

local function sa(addr, addrlen)
  local family = addr.family
  if family == S.AF_UNIX then -- we return Lua metatable not metatype, as need length to decode
    local sa = t.sockaddr_un()
    ffi.copy(sa, addr, addrlen)
    return setmetatable({addr = sa, addrlen = addrlen}, mt.sockaddr_un)
  end
  local st = samap[family]
  local a = st()
  ffi.copy(a, addr, ffi.sizeof(st))
  return a
end

-- functions from section 3 that we use for ip addresses etc
function S.strerror(errno) return ffi.string(C.strerror(errno)) end

function S.inet_aton(s, addr)
  if not addr then addr = t.in_addr() end
  local ret = C.inet_aton(s, addr)
  if ret == 0 then return nil end
  return addr
end

function S.inet_ntoa(addr)
  local b = pt.uchar(addr)
  return tonumber(b[0]) .. "." .. tonumber(b[1]) .. "." .. tonumber(b[2]) .. "." .. tonumber(b[3])
end

local INET6_ADDRSTRLEN = 46
local INET_ADDRSTRLEN = 16

function S.inet_ntop(af, src)
  af = stringflag(af, "AF_")
  local len = INET6_ADDRSTRLEN -- could shorten for ipv4
  local dst = t.buffer(len)
  local ret = C.inet_ntop(af, src, dst, len)
  if ret == nil then return nil, t.error() end
  return ffi.string(dst)
end

function S.inet_pton(af, src, addr)
  af = stringflag(af, "AF_")
  if not addr then addr = S.addrtype[af]() end
  local ret = C.inet_pton(af, src, addr)
  if ret == -1 then return nil, t.error() end
  if ret == 0 then return nil end -- maybe return string
  return addr
end

-- main definitions start here
function S.open(pathname, flags, mode)
  local ret = C.open(pathname, stringflags(flags, "O_"), S.mode(mode))
  if ret == -1 then return nil, t.error() end
  return t.fd(ret)
end

function S.dup(oldfd, newfd, flags)
  local ret
  if newfd == nil then ret = C.dup(getfd(oldfd))
  elseif flags == nil then ret = C.dup2(getfd(oldfd), getfd(newfd))
  else ret = C.dup3(getfd(oldfd), getfd(newfd), flags) end
  if ret == -1 then return nil, t.error() end
  return t.fd(ret)
end

function S.pipe(flags)
  local fd2 = t.int2()
  local ret
  if flags then ret = C.pipe2(fd2, stringflags(flags, "O_")) else ret = C.pipe(fd2) end
  if ret == -1 then return nil, t.error() end
  return {t.fd(fd2[0]), t.fd(fd2[1])}
end

function S.close(fd)
  local fileno = getfd(fd)
  if fileno == -1 then return true end -- already closed
  local ret = C.close(fileno)
  if ret == -1 then
    local errno = ffi.errno()
    if ffi.istype(t.fd, fd) and errno ~= S.E.INTR then -- file will still be open if interrupted
      fd.fileno = -1 -- make sure cannot accidentally close this fd object again
    end
    return nil, t.error()
  end
  if ffi.istype(t.fd, fd) then
    fd.fileno = -1 -- make sure cannot accidentally close this fd object again
  end
  return true
end

function S.creat(pathname, mode) return retfd(C.creat(pathname, S.mode(mode))) end
function S.unlink(pathname) return retbool(C.unlink(pathname)) end
function S.chdir(path) return retbool(C.chdir(path)) end
function S.mkdir(path, mode) return retbool(C.mkdir(path, S.mode(mode))) end
function S.rmdir(path) return retbool(C.rmdir(path)) end
function S.unlink(pathname) return retbool(C.unlink(pathname)) end
function S.acct(filename) return retbool(C.acct(filename)) end
function S.chmod(path, mode) return retbool(C.chmod(path, S.mode(mode))) end
function S.link(oldpath, newpath) return retbool(C.link(oldpath, newpath)) end
function S.symlink(oldpath, newpath) return retbool(C.symlink(oldpath, newpath)) end
function S.pause() return retbool(C.pause()) end

function S.truncate(path, length) return retbool(C64.truncate(path, length)) end
function S.ftruncate(fd, length) return retbool(C64.ftruncate(getfd(fd), length)) end

function S.access(pathname, mode) return retbool(C.access(pathname, accessflags(mode))) end

function S.readlink(path) -- note no idea if name truncated except return value is buffer len, so have to reallocate
  local size = 256
  local buffer, ret
  repeat
    buffer = t.buffer(size)
    ret = tonumber(C.readlink(path, buffer, size))
    if ret == -1 then return nil, t.error() end
    if ret == size then -- possibly truncated
      buffer = nil
      size = size * 2
    end
  until buffer
  return ffi.string(buffer, ret)
end

local function retnume(f, ...) -- for cases where need to explicitly set and check errno, ie signed int return
  ffi.errno(0)
  local ret = f(...)
  local errno = ffi.errno()
  if errno ~= 0 then return nil, t.error() end
  return ret
end

function S.nice(inc) return retnume(C.nice, inc) end
-- NB glibc is shifting these values from what strace shows, as per man page, kernel adds 20 to make these values positive...
-- might cause issues with other C libraries in which case may shift to using system call
function S.getpriority(which, who) return retnume(C.getpriority, stringflags(which, "PRIO_"), who or 0) end
function S.setpriority(which, who, prio) return retnume(C.setpriority, stringflags(which, "PRIO_"), who or 0, prio) end

 -- we could allocate ptid, ctid, tls if required in flags instead. TODO add signal into flag parsing directly
function S.clone(flags, signal, stack, ptid, tls, ctid)
  flags = t.int64(stringflags(flags, "CLONE_") + stringflag(signal, "SIG"))
  return retnum(C.syscall(S.SYS_clone, flags, pt.void(stack), pt.void(ptid), pt.void(tls), pt.void(ctid)))
end

function S.unshare(flags)
  return retbool(C.unshare(stringflags(flags, "CLONE_")))
end

function S.fork() return retnum(C.fork()) end
function S.execve(filename, argv, envp)
  local cargv = t.string_array(#argv + 1, argv)
  cargv[#argv] = nil -- LuaJIT does not zero rest of a VLA
  local cenvp = t.string_array(#envp + 1, envp)
  cenvp[#envp] = nil
  return retbool(C.execve(filename, cargv, cenvp))
end

-- best to call C.syscall directly? do not export?
function S.syscall(num, ...)
  -- call with the right types, use at your own risk
  local a, b, c, d, e, f = ...
  local ret = C.syscall(stringflag(num, "SYS_"), a, b, c, d, e, f)
  if ret == -1 then return nil, t.error() end
  return ret
end

function S.ioctl(d, request, argp)
  local ret = C.ioctl(d, request, argp)
  if ret == -1 then return nil, t.error() end
  -- some different return types may need to be handled
  return true
end

function S.reboot(cmd) return retbool(C.reboot(stringflag(cmd, "LINUX_REBOOT_CMD_"))) end

-- ffi metatype on linux_dirent?
function S.getdents(fd, buf, size, noiter) -- default behaviour is to iterate over whole directory, use noiter if you have very large directories
  if not buf then
    size = size or 4096
    buf = t.buffer(size)
  end
  local d = {}
  local ret
  repeat
    ret = C.syscall(S.SYS_getdents64, t.int(getfd(fd)), buf, t.uint(size))
    if ret == -1 then return nil, t.error() end
    local i = 0
    while i < ret do
      local dp = pt.linux_dirent64(buf + i)
      local dd = setmetatable({inode = tonumber(dp.d_ino), offset = tonumber(dp.d_off), type = tonumber(dp.d_type)}, mt.dents)
      d[ffi.string(dp.d_name)] = dd -- could calculate length
      i = i + dp.d_reclen
    end
  until noiter or ret == 0
  return d
end

function S.wait()
  local status = t.int1()
  return retwait(C.wait(status), status[0])
end
function S.waitpid(pid, options)
  local status = t.int1()
  return retwait(C.waitpid(pid, status, stringflags(options, "W")), status[0])
end
function S.waitid(idtype, id, options, infop) -- note order of args, as usually dont supply infop
  if not infop then infop = t.siginfo() end
  infop.si_pid = 0 -- see notes on man page
  local ret = C.waitid(stringflag(idtype, "P_"), id or 0, infop, stringflags(options, "W"))
  if ret == -1 then return nil, t.error() end
  return infop -- return table here?
end

function S._exit(status) C._exit(stringflag(status, "EXIT_")) end
function S.exit(status) C.exit(stringflag(status, "EXIT_")) end

function S.read(fd, buf, count)
  if buf then return retnum(C.read(getfd(fd), buf, count)) end -- user supplied a buffer, standard usage
  if not count then count = 4096 end
  local buf = t.buffer(count)
  local ret = C.read(getfd(fd), buf, count)
  if ret == -1 then return nil, t.error() end
  return ffi.string(buf, tonumber(ret)) -- user gets a string back, can get length from #string
end

function S.write(fd, buf, count) return retnum(C.write(getfd(fd), buf, count or #buf)) end
function S.pread(fd, buf, count, offset) return retnum(C.pread64(getfd(fd), buf, count, offset)) end
function S.pwrite(fd, buf, count, offset) return retnum(C.pwrite64(getfd(fd), buf, count or #buf, offset)) end
function S.lseek(fd, offset, whence) return ret64(C.llseek(getfd(fd), offset, stringflag(whence, "SEEK_"))) end
function S.send(fd, buf, count, flags) return retnum(C.send(getfd(fd), buf, count or #buf, stringflags(flags, "MSG_"))) end
function S.sendto(fd, buf, count, flags, addr, addrlen)
  return retnum(C.sendto(getfd(fd), buf, count or #buf, stringflags(flags, "MSG_"), addr, addrlen or ffi.sizeof(addr)))
end

function S.readv(fd, iov)
  if not ffi.istype(t.iovecs, iov) then iov = t.iovecs(iov) end
  return retnum(C.readv(getfd(fd), iov.iov, #iov))
end

function S.writev(fd, iov)
  if not ffi.istype(t.iovecs, iov) then iov = t.iovecs(iov) end
  return retnum(C.writev(getfd(fd), iov.iov, #iov))
end

function S.recv(fd, buf, count, flags) return retnum(C.recv(getfd(fd), buf, count or #buf, stringflags(flags, "MSG_"))) end
function S.recvfrom(fd, buf, count, flags)
  local ss = t.sockaddr_storage()
  local addrlen = t.socklen1(ffi.sizeof(t.sockaddr_storage))
  local ret = C.recvfrom(getfd(fd), buf, count, stringflags(flags, "MSG_"), ss, addrlen)
  if ret == -1 then return nil, t.error() end
  return {count = tonumber(ret), addr = sa(ss, addrlen[0])}
end

function S.setsockopt(fd, level, optname, optval, optlen)
   -- allocate buffer for user, from Lua type if know how, int and bool so far
  if not optlen and type(optval) == 'boolean' then if optval then optval = 1 else optval = 0 end end
  if not optlen and type(optval) == 'number' then
    optval = t.int1(optval)
    optlen = ffi.sizeof(t.int1)
  end
  return retbool(C.setsockopt(getfd(fd), stringflag(level, "SOL_"), stringflag(optname, "SO_"), optval, optlen))
end

function S.getsockopt(fd, level, optname) -- will need fixing for non int/bool options
  local optval, optlen = t.int1(), t.socklen1()
  optlen[0] = ffi.sizeof(t.int1)
  local ret = C.getsockopt(getfd(fd), level, optname, optval, optlen)
  if ret == -1 then return nil, t.error() end
  return tonumber(optval[0]) -- no special case for bool
end

function S.fchdir(fd) return retbool(C.fchdir(getfd(fd))) end
function S.fsync(fd) return retbool(C.fsync(getfd(fd))) end
function S.fdatasync(fd) return retbool(C.fdatasync(getfd(fd))) end
function S.fchmod(fd, mode) return retbool(C.fchmod(getfd(fd), S.mode(mode))) end
function S.sync_file_range(fd, offset, count, flags)
  return retbool(C.sync_file_range(getfd(fd), offset, count, stringflags(flags, "SYNC_FILE_RANGE_")))
end

function S.stat(path, buf)
  if not buf then buf = t.stat() end
  local ret = C.syscall(S.SYS_stat, path, pt.void(buf))
  if ret == -1 then return nil, t.error() end
  return buf
end

function S.lstat(path, buf)
  if not buf then buf = t.stat() end
  local ret = C.syscall(S.SYS_lstat, path, pt.void(buf))
  if ret == -1 then return nil, t.error() end
  return buf
end

function S.fstat(fd, buf)
  if not buf then buf = t.stat() end
  local ret = C.syscall(S.SYS_fstat, t.int(getfd(fd)), pt.void(buf))
  if ret == -1 then return nil, t.error() end
  return buf
end

function S.futimens(fd, ts)
  if ts and (not ffi.istype(t.timespec2, ts)) then
    s1, s2 = ts[1], ts[2]
    ts = t.timespec2()
    if type(s1) == 'string' then ts[0].tv_nsec = stringflag(s1, "UTIME_") else ts[0] = t.timespec(s1) end
    if type(s2) == 'string' then ts[1].tv_nsec = stringflag(s2, "UTIME_") else ts[1] = t.timespec(s2) end
  end
  return retbool(C.futimens(getfd(fd), ts))
end

function S.chroot(path) return retbool(C.chroot(path)) end

function S.getcwd()
  local size = 64
  local buf
  repeat
    buf = t.buffer(size)
    local ret = C.getcwd(buf, size)
    if not ret then 
      local errno = ffi.errno()
      if errno == S.E.RANGE then size = size * 2 else return nil, t.error(errno) end
    end
  until ret
  return ffi.string(buf)
end

function S.ustat(dev) -- note deprecated, use statfs instead
  local u = t.ustat()
  local ret = C.ustat(dev, u)
  if ret == -1 then return nil, t.error() end
  return u
end

function S.statfs(path)
  local st = t.statfs()
  local ret = C.statfs(path, st)
  if ret == -1 then return nil, t.error() end
  return st
end

function S.fstatfs(fd)
  local st = t.statfs()
  local ret = C.fstatfs(getfd(fd), st)
  if ret == -1 then return nil, t.error() end
  return st
end

function S.nanosleep(req)
  if not ffi.istype(t.timespec, req) then req = t.timespec(req) end
  local rem = t.timespec()
  local ret = C.nanosleep(req, rem)
  if ret == -1 then return nil, t.error() end
  return rem
end

function S.sleep(sec) -- standard libc function
  local rem, err = S.nanosleep(sec)
  if not rem then return nil, err end
  return tonumber(rem.tv_sec)
end

function S.mmap(addr, length, prot, flags, fd, offset)
  return retptr(C.mmap(addr, length, stringflags(prot, "PROT_"), stringflags(flags, "MAP_"), getfd(fd), offset))
end
function S.munmap(addr, length)
  return retbool(C.munmap(addr, length))
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
function S.posix_fadvise(fd, advice, offset, len) -- note argument order
  return retbool(C.posix_fadvise(getfd(fd), offset or 0, len or 0, stringflag(advice, "POSIX_FADV_")))
end
function S.fallocate(fd, mode, offset, len)
  return retbool(C.fallocate(getfd(fd), stringflag(mode, "FALLOC_FL_"), offset or 0, len))
end
function S.posix_fallocate(fd, offset, len) return S.fallocate(fd, 0, offset, len) end
function S.readahead(fd, offset, count)
  return retbool(C.readahead(getfd(fd), offset, count))
end

local function sproto(domain, protocol) -- helper function to lookup protocol type depending on domain
  if domain == S.AF_NETLINK then return stringflag(protocol, "NETLINK_") end
  return protocol or 0
end

function S.socket(domain, stype, protocol)
  domain = stringflag(domain, "AF_")
  local ret = C.socket(domain, stringflags(stype, "SOCK_"), sproto(domain, protocol))
  if ret == -1 then return nil, t.error() end
  return t.fd(ret)
end

function S.socketpair(domain, stype, protocol)
  domain = stringflag(domain, "AF_")
  local sv2 = t.int2()
  local ret = C.socketpair(domain, stringflags(stype, "SOCK_"), sproto(domain, protocol), sv2)
  if ret == -1 then return nil, t.error() end
  return {t.fd(sv2[0]), t.fd(sv2[1])}
end

function S.bind(sockfd, addr, addrlen)
  return retbool(C.bind(getfd(sockfd), addr, addrlen or ffi.sizeof(addr)))
end

function S.listen(sockfd, backlog) return retbool(C.listen(getfd(sockfd), backlog or S.SOMAXCONN)) end
function S.connect(sockfd, addr, addrlen)
  return retbool(C.connect(getfd(sockfd), addr, addrlen or ffi.sizeof(addr)))
end

function S.shutdown(sockfd, how) return retbool(C.shutdown(getfd(sockfd), stringflag(how, "SHUT_"))) end

function S.accept(sockfd, flags, addr, addrlen)
  if not addr then addr = t.sockaddr_storage() end
  if not addrlen then addrlen = t.socklen1(addrlen or ffi.sizeof(addr)) end
  local ret
  if not flags
    then ret = C.accept(getfd(sockfd), addr, addrlen)
    else ret = C.accept4(getfd(sockfd), addr, addrlen, stringflags(flags, "SOCK_"))
  end
  if ret == -1 then return nil, t.error() end
  return {fd = t.fd(ret), addr = sa(addr, addrlen[0])}
end

function S.getsockname(sockfd)
  local ss = t.sockaddr_storage()
  local addrlen = t.socklen1(ffi.sizeof(t.sockaddr_storage))
  local ret = C.getsockname(getfd(sockfd), ss, addrlen)
  if ret == -1 then return nil, t.error() end
  return sa(ss, addrlen[0])
end

function S.getpeername(sockfd)
  local ss = t.sockaddr_storage()
  local addrlen = t.socklen1(ffi.sizeof(t.sockaddr_storage))
  local ret = C.getpeername(getfd(sockfd), ss, addrlen)
  if ret == -1 then return nil, t.error() end
  return sa(ss, addrlen[0])
end

function S.fcntl(fd, cmd, arg)
  -- some uses have arg as a pointer, need handling TODO
  cmd = stringflag(cmd, "F_")
  if cmd == S.F_SETFL then arg = stringflags(arg, "O_")
  elseif cmd == S.F_SETFD then arg = stringflag(arg, "FD_")
  end
  local ret = C.fcntl(getfd(fd), cmd, arg or 0)
  if ret == -1 then return nil, t.error() end
  -- return values differ, some special handling needed
  if cmd == S.F_DUPFD or cmd == S.F_DUPFD_CLOEXEC then return t.fd(ret) end
  if cmd == S.F_GETFD or cmd == S.F_GETFL or cmd == S.F_GETLEASE or cmd == S.F_GETOWN or
     cmd == S.F_GETSIG or cmd == S.F_GETPIPE_SZ then return tonumber(ret) end
  return true
end

function S.uname()
  local u = t.utsname()
  local ret = C.uname(u)
  if ret == -1 then return nil, t.error() end
  return {sysname = ffi.string(u.sysname), nodename = ffi.string(u.nodename), release = ffi.string(u.release),
          version = ffi.string(u.version), machine = ffi.string(u.machine), domainname = ffi.string(u.domainname)}
end

function S.gethostname()
  local buf = t.buffer(HOST_NAME_MAX + 1)
  local ret = C.gethostname(buf, HOST_NAME_MAX + 1)
  if ret == -1 then return nil, t.error() end
  buf[HOST_NAME_MAX] = 0 -- paranoia here to make sure null terminated, which could happen if HOST_NAME_MAX was incorrect
  return ffi.string(buf)
end

function S.sethostname(s) -- only accept Lua string, do not see use case for buffer as well
  return retbool(C.sethostname(s, #s))
end

-- signal set handlers TODO replace with metatypes
local function mksigset(str)
  if not str then return t.sigset() end
  if type(str) ~= 'string' then return str end
  local f = t.sigset()
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

local function sigismember(set, sig)
  local d = bit.rshift(sig - 1, 5) -- always 32 bits
  return bit.band(set.val[d], bit.lshift(1, (sig - 1) % 32)) ~= 0
end

local function sigemptyset(set)
  for i = 0, ffi.sizeof(t.sigset) / 4 - 1 do
    if set.val[i] ~= 0 then return false end
  end
  return true
end

local function sigaddset(set, sig)
  set = mksigset(set)
  local d = bit.rshift(sig - 1, 5)
  set.val[d] = bit.bor(set.val[d], bit.lshift(1, (sig - 1) % 32))
  return set
end

local function sigdelset(set, sig)
  set = mksigset(set)
  local d = bit.rshift(sig - 1, 5)
  set.val[d] = bit.band(set.val[d], bit.bnot(bit.lshift(1, (sig - 1) % 32)))
  return set
end

local function sigaddsets(set, sigs) -- allow multiple
  if type(sigs) ~= "string" then return sigaddset(set, sigs) end
  set = mksigset(set)
  local a = split(",", sigs)
  for i, v in ipairs(a) do
    local s = trim(v:upper())
    if s:sub(1, 3) ~= "SIG" then s = "SIG" .. s end
    local sig = S[s]
    if not sig then error("invalid signal: " .. v) end -- don't use this format if you don't want exceptions, better than silent ignore
    sigaddset(set, sig)
  end
  return set
end

local function sigdelsets(set, sigs) -- allow multiple
  if type(sigs) ~= "string" then return sigdelset(set, sigs) end
  set = mksigset(set)
  local a = split(",", sigs)
  for i, v in ipairs(a) do
    local s = trim(v:upper())
    if s:sub(1, 3) ~= "SIG" then s = "SIG" .. s end
    local sig = S[s]
    if not sig then error("invalid signal: " .. v) end -- don't use this format if you don't want exceptions, better than silent ignore
    sigdelset(set, sig)
  end
  return set
end

t.sigset = ffi.metatype("sigset_t", {
  __index = function(set, k)
    if k == 'add' then return sigaddsets end
    if k == 'del' then return sigdelsets end
    if k == 'isemptyset' then return sigemptyset(set) end
    local prefix = "SIG"
    if k:sub(1, #prefix) ~= prefix then k = prefix .. k:upper() end
    local sig = S[k]
    if sig then return sigismember(set, sig) end
  end
})

-- does not support passing a function as a handler, use sigaction instead
-- actualy glibc does not call the syscall anyway, defines in terms of sigaction; we could too
function S.signal(signum, handler) return retbool(C.signal(stringflag(signum, "SIG"), stringflag(handler, "SIG_"))) end

-- missing siginfo functionality for now, only supports getting signum TODO
function S.sigaction(signum, handler, mask, flags)
  local sa
  if ffi.istype(t.sigaction, handler) then sa = handler
  else
    if type(handler) == 'string' then
      handler = ffi.cast(t.sighandler, t.int1(stringflag(handler, "SIG_")))
    elseif
      type(handler) == 'function' then handler = ffi.cast(t.sighandler, handler) -- TODO check if gc problem here? need to copy?
    end
    sa = t.sigaction{sa_handler = handler, sa_mask = mksigset(mask), sa_flags = stringflags(flags, "SA_")}
  end
  local old = t.sigaction()
  local ret = C.sigaction(stringflag(signum, "SIG"), sa, old)
  if ret == -1 then return nil, t.error() end
  return old
end

function S.kill(pid, sig) return retbool(C.kill(pid, stringflag(sig, "SIG"))) end
function S.killpg(pgrp, sig) return S.kill(-pgrp, sig) end

function S.gettimeofday(tv)
  if not tv then tv = t.timeval() end -- note it is faster to pass your own tv if you call a lot
  local ret = C.gettimeofday(tv, nil)
  if ret == -1 then return nil, t.error() end
  return tv
end

function S.settimeofday(tv) return retbool(C.settimeofday(tv, nil)) end

function S.time()
  return tonumber(C.time(nil))
end

function S.sysinfo(info)
  if not info then info = t.sysinfo() end
  local ret = C.sysinfo(info)
  if ret == -1 then return nil, t.error() end
  return info
end

local function growattrbuf(f, a1, a2)
  local len = 512
  local buffer = t.buffer(len)
  local ret
  repeat
    if a2 then ret = tonumber(f(a1, a2, buffer, len)) else ret = tonumber(f(a1, buffer, len)) end
    if ret == -1 and ffi.errno ~= S.E.ERANGE then return nil, t.error() end
    if ret == -1 then
      len = len * 2
      buffer = t.buffer(len)
    end
  until ret >= 0

  if ret > 0 then ret = ret - 1 end -- has trailing \0

  return ffi.string(buffer, ret)
end

local function lattrbuf(...)
  local s, err = growattrbuf(...)
  if not s then return nil, err end
  return split('\0', s)
end

function S.listxattr(path) return lattrbuf(C.listxattr, path) end
function S.llistxattr(path) return lattrbuf(C.llistxattr, path) end
function S.flistxattr(fd) return lattrbuf(C.flistxattr, getfd(fd)) end

function S.setxattr(path, name, value, flags)
  return retbool(C.setxattr(path, name, value, #value + 1, stringflag(flags, "XATTR_")))
end
function S.lsetxattr(path, name, value, flags)
  return retbool(C.lsetxattr(path, name, value, #value + 1, stringflag(flags, "XATTR_")))
end
function S.fsetxattr(fd, name, value, flags)
  return retbool(C.fsetxattr(getfd(fd), name, value, #value + 1, stringflag(flags, "XATTR_")))
end

function S.getxattr(path, name) return growattrbuf(C.getxattr, path, name) end
function S.lgetxattr(path, name) return growattrbuf(C.lgetxattr, path, name) end
function S.fgetxattr(fd, name) return growattrbuf(C.fgetxattr, getfd(fd), name) end

function S.removexattr(path, name) return retbool(C.removexattr(path, name)) end
function S.lremovexattr(path, name) return retbool(C.lremovexattr(path, name)) end
function S.fremovexattr(fd, name) return retbool(C.fremovexattr(getfd(fd), name)) end

-- helper function to set and return attributes in tables
local function xattr(list, get, set, remove, path, t)
  local l, err = list(path)
  if not l then return nil, err end
  if not t then -- no table, so read
    local r = {}
    for _, name in ipairs(l) do
      r[name] = get(path, name) -- ignore errors
    end
    return r
  end
  -- write
  for _, name in ipairs(l) do
    if t[name] then
      set(path, name, t[name]) -- ignore errors, replace
      t[name] = nil
    else
      remove(path, name)
    end
  end
  for name, value in pairs(t) do
    set(path, name, value) -- ignore errors, create
  end
  return true
end

function S.xattr(path, t) return xattr(S.listxattr, S.getxattr, S.setxattr, S.removexattr, path, t) end
function S.lxattr(path, t) return xattr(S.llistxattr, S.lgetxattr, S.lsetxattr, S.lremovexattr, path, t) end
function S.fxattr(fd, t) return xattr(S.flistxattr, S.fgetxattr, S.fsetxattr, S.fremovexattr, fd, t) end

-- fdset handlers
local function mkfdset(fds, nfds) -- should probably check fd is within range (1024), or just expand structure size
  local set = t.fdset()
  for i, v in ipairs(fds) do
    local fd = tonumber(getfd(v))
    if fd + 1 > nfds then nfds = fd + 1 end
    local fdelt = bit.rshift(fd, 5) -- always 32 bits
    set.fds_bits[fdelt] = bit.bor(set.fds_bits[fdelt], bit.lshift(1, fd % 32)) -- always 32 bit words
  end
  return set, nfds
end

local function fdisset(fds, set)
  local f = {}
  for i, v in ipairs(fds) do
    local fd = tonumber(getfd(v))
    local fdelt = bit.rshift(fd, 5) -- always 32 bits
    if bit.band(set.fds_bits[fdelt], bit.lshift(1, fd % 32)) ~= 0 then table.insert(f, v) end -- careful not to duplicate fd objects
  end
  return f
end

function S.sigprocmask(how, set)
  how = stringflag(how, "SIG_")
  set = mksigset(set)
  local oldset = t.sigset()
  local ret = C.sigprocmask(how, set, oldset)
  if ret == -1 then return nil, t.error() end
  return oldset
end

function S.sigpending()
  local set = t.sigset()
  local ret = C.sigpending(set)
  if ret == -1 then return nil, t.error() end
 return set
end

function S.sigsuspend(mask) return retbool(C.sigsuspend(mksigset(mask))) end

function S.signalfd(set, flags, fd) -- note different order of args, as fd usually empty. See also signalfd_read()
  return retfd(C.signalfd(getfd(fd) or -1, mksigset(set), stringflags(flags, "SFD_")))
end

-- TODO convert to metatype?
function S.select(s) -- note same structure as returned
  local r, w, e
  local nfds = 0
  local timeout2
  if s.timeout then
    if ffi.istype(t.timeval, s.timeout) then timeout2 = s.timeout else timeout2 = t.timeval(s.timeout) end
  end
  r, nfds = mkfdset(s.readfds or {}, nfds or 0)
  w, nfds = mkfdset(s.writefds or {}, nfds)
  e, nfds = mkfdset(s.exceptfds or {}, nfds)
  local ret = C.select(nfds, r, w, e, timeout2)
  if ret == -1 then return nil, t.error() end
  return {readfds = fdisset(s.readfds or {}, r), writefds = fdisset(s.writefds or {}, w),
          exceptfds = fdisset(s.exceptfds or {}, e), count = tonumber(ret)}
end

function S.poll(fds, timeout)
  if not ffi.istype(t.pollfds, fds) then fds = t.pollfds(fds) end
  local ret = C.poll(fds.pfd, #fds, timeout or -1)
  if ret == -1 then return nil, t.error() end
  return fds
end

function S.mount(source, target, filesystemtype, mountflags, data)
  return retbool(C.mount(source, target, filesystemtype, stringflags(mountflags, "MS_"), data or nil))
end

function S.umount(target, flags)
  if flags then return retbool(C.umount2(target, stringflags(flags, "MNT_", "UMOUNT_"))) end
  return retbool(C.umount(target))
end

-- unlimited value. TODO metatype should return this to Lua.
S.RLIM_INFINITY = ffi.cast("rlim_t", -1)

function S.getrlimit(resource)
  local rlim = t.rlimit()
  local ret = C.getrlimit(stringflag(resource, "RLIMIT_"), rlim)
  if ret == -1 then return nil, t.error() end
  return rlim
end

function S.setrlimit(resource, rlim, rlim2) -- can pass table, struct, or just both the parameters
  if rlim and rlim2 then rlim = t.rlimit(rlim, rlim2)
  elseif type(rlim) == 'table' then rlim = t.rlimit(rlim) end
  return retbool(C.setrlimit(stringflag(resource, "RLIMIT_"), rlim))
end

function S.epoll_create(flags)
  return retfd(C.epoll_create1(stringflags(flags, "EPOLL_")))
end

function S.epoll_ctl(epfd, op, fd, event, data)
  if not ffi.istype(t.epoll_event, event) then
    local events = stringflags(event, "EPOLL")
    event = t.epoll_event()
    event.events = events
    if data then event.data.u64 = data else event.data.fd = getfd(fd) end
  end
  return retbool(C.epoll_ctl(getfd(epfd), stringflag(op, "EPOLL_CTL_"), getfd(fd), event))
end

local epoll_flags = {"EPOLLIN", "EPOLLOUT", "EPOLLRDHUP", "EPOLLPRI", "EPOLLERR", "EPOLLHUP"}

function S.epoll_wait(epfd, events, maxevents, timeout, sigmask) -- includes optional epoll_pwait functionality
  if not maxevents then maxevents = 16 end
  if not events then events = t.epoll_events(maxevents) end
  if sigmask then sigmask = mksigset(sigmask) end
  local ret
  if sigmask then
    ret = C.epoll_pwait(getfd(epfd), events, maxevents, timeout or -1, sigmask)
  else
    ret = C.epoll_wait(getfd(epfd), events, maxevents, timeout or -1)
  end
  if ret == -1 then return nil, t.error() end
  local r = {}
  for i = 1, ret do -- put in Lua array
    local e = events[i - 1]
    local ev = setmetatable({fileno = tonumber(e.data.fd), data = t.uint64(e.data.u64), events = e.events}, mt.epoll)
    r[i] = ev
  end
  return r
end

function S.splice(fd_in, off_in, fd_out, off_out, len, flags)
  local offin, offout = off_in, off_out
  if off_in and not ffi.istype(t.loff1, off_in) then
    offin = t.loff1()
    offin[0] = off_in
  end
  if off_out and not ffi.istype(t.loff1, off_out) then
    offout = t.loff1()
    offout[0] = off_out
  end
  return retnum(C.splice(getfd(fd_in), offin, getfd(fd_out), offout, len, stringflags(flags, "SPLICE_F_")))
end

function S.vmsplice(fd, iov, flags)
  if not ffi.istype(t.iovecs, iov) then iov = t.iovecs(iov) end
  return retnum(C.vmsplice(getfd(fd), iov.iov, #iov, stringflags(flags, "SPLICE_F_")))
end

function S.tee(fd_in, fd_out, len, flags)
  return retnum(C.tee(getfd(fd_in), getfd(fd_out), len, stringflags(flags, "SPLICE_F_")))
end

function S.inotify_init(flags) return retfd(C.inotify_init1(stringflags(flags, "IN_"))) end
function S.inotify_add_watch(fd, pathname, mask) return retnum(C.inotify_add_watch(getfd(fd), pathname, stringflags(mask, "IN_"))) end
function S.inotify_rm_watch(fd, wd) return retbool(C.inotify_rm_watch(getfd(fd), wd)) end

-- helper function to read inotify structs as table from inotify fd
function S.inotify_read(fd, buffer, len)
  if not len then len = 1024 end
  if not buffer then buffer = t.buffer(len) end
  local ret, err = S.read(fd, buffer, len)
  if not ret then return nil, err end
  local off, ee = 0, {}
  while off < ret do
    local ev = pt.inotify_event(buffer + off)
    local le = setmetatable({wd = tonumber(ev.wd), mask = tonumber(ev.mask), cookie = tonumber(ev.cookie)}, mt.inotify)
    if ev.len > 0 then le.name = ffi.string(ev.name) end
    ee[#ee + 1] = le
    off = off + ffi.sizeof(t.inotify_event(ev.len))
  end
  return ee
end

function S.sendfile(out_fd, in_fd, offset, count) -- bit odd having two different return types...
  if not offset then return retnum(C.sendfile(getfd(out_fd), getfd(in_fd), nil, count)) end
  local off = t.off1()
  off[0] = offset
  local ret = C.sendfile(getfd(out_fd), getfd(in_fd), off, count)
  if ret == -1 then return nil, t.error() end
  return {count = tonumber(ret), offset = tonumber(off[0])}
end

function S.eventfd(initval, flags) return retfd(C.eventfd(initval or 0, stringflags(flags, "EFD_"))) end
-- eventfd read and write helpers, as in glibc but Lua friendly. Note returns 0 for EAGAIN, as 0 never returned directly
-- returns Lua number - if you need all 64 bits, pass your own value in and use that for the exact result
function S.eventfd_read(fd, value)
  if not value then value = t.uint64_1() end
  local ret = C.read(getfd(fd), value, 8)
  if ret == -1 and ffi.errno() == S.E.EAGAIN then
    value[0] = 0
    return 0
  end
  if ret == -1 then return nil, t.error() end
  return tonumber(value[0])
end
function S.eventfd_write(fd, value)
  if not value then value = 1 end
  if type(value) == "number" then value = t.uint64_1(value) end
  return retbool(C.write(getfd(fd), value, 8))
end

local function sigcode(s, signo, code)
  s.code = code
  s.signo = signo
  local name = signals[s.signo]
  s[name] = true
  s[name:lower():sub(4)] = true
  local rname = signal_reasons_gen[code]
  if not rname and signal_reasons[signo] then rname = signal_reasons[signo][code] end
  if rname then
    s[rname] = true
    s[rname:sub(rname:find("_") + 1):lower()] = true
  end
end

-- TODO use metatypes
function S.signalfd_read(fd, buffer, len)
  if not len then len = ffi.sizeof(t.signalfd_siginfo) * 4 end
  if not buffer then buffer = t.buffer(len) end
  local ret, err = S.read(fd, buffer, len)
  if ret == 0 or (err and err.EAGAIN) then return {} end
  if not ret then return nil, err end
  local offset, ss = 0, {}
  while offset < ret do
    local ssi = pt.signalfd_siginfo(buffer + offset)
    local s = {}
    s.errno = tonumber(ssi.ssi_errno)
    sigcode(s, tonumber(ssi.ssi_signo), tonumber(ssi.ssi_code))

    if s.SI_USER or s.SI_QUEUE then
      s.pid = tonumber(ssi.ssi_pid)
      s.uid = tonumber(ssi.ssi_uid)
      s.int = tonumber(ssi.ssi_int)
      s.ptr = t.uint64(ssi.ssi_ptr)
    elseif s.SI_TIMER then
      s.overrun = tonumber(ssi.ssi_overrun)
      s.timerid = tonumber(ssi.ssi_tid)
    end

    if s.SIGCHLD then 
      s.pid = tonumber(ssi.ssi_pid)
      s.uid = tonumber(ssi.ssi_uid)
      s.status = tonumber(ssi.ssi_status)
      s.utime = tonumber(ssi.ssi_utime) / 1000000 -- convert to seconds
      s.stime = tonumber(ssi.ssi_stime) / 1000000
    elseif s.SIGILL or S.SIGFPE or s.SIGSEGV or s.SIGBUS or s.SIGTRAP then
      s.addr = t.uint64(ssi.ssi_addr)
    elseif s.SIGIO or s.SIGPOLL then
      s.band = tonumber(ssi.ssi_band) -- should split this up, is events from poll, TODO
      s.fd = tonumber(ssi.ssi_fd)
    end

    ss[#ss + 1] = s
    offset = offset + ffi.sizeof(t.signalfd_siginfo)
  end
  return ss
end

function S.getitimer(which, value)
  if not value then value = t.itimerval() end
  local ret = C.getitimer(stringflag(which, "ITIMER_"), value)
  if ret == -1 then return nil, t.error() end
  return value
end

function S.setitimer(which, it)
  if not ffi.istype(t.itimerval, it) then it = t.itimerval(it) end
  local oldtime = t.itimerval()
  local ret = C.setitimer(stringflag(which, "ITIMER_"), it, oldtime)
  if ret == -1 then return nil, t.error() end
  return oldtime
end

function S.timerfd_create(clockid, flags)
  return retfd(C.timerfd_create(stringflag(clockid, "CLOCK_"), stringflags(flags, "TFD_")))
end

function S.timerfd_settime(fd, flags, it)
  local oldtime = t.itimerspec()
  if not ffi.istype(t.itimerspec, it) then it = t.itimerspec(it) end
  local ret = C.timerfd_settime(getfd(fd), stringflag(flags, "TFD_TIMER_"), it, oldtime)
  if ret == -1 then return nil, t.error() end
  return oldtime
end

function S.timerfd_gettime(fd, curr_value)
  if not curr_value then curr_value = t.itimerspec() end
  local ret = C.timerfd_gettime(getfd(fd), curr_value)
  if ret == -1 then return nil, t.error() end
  return curr_value
end

function S.timerfd_read(fd, buffer)
  if not buffer then buffer = t.uint64_1() end
  local ret, err = S.read(fd, buffer, 8)
  if not ret and err.EAGAIN then return 0 end -- will never actually return 0
  if not ret then return nil, err end
  return tonumber(buffer[0])
end

-- aio functions
function S.io_setup(nr_events)
  local ctx = t.aio_context()
  local ret = C.syscall(S.SYS_io_setup, t.uint(nr_events), ctx)
  if ret == -1 then return nil, t.error() end
  return ctx
end

function S.io_destroy(ctx)
  if ctx.ctx == 0 then return end
  local ret = retbool(C.syscall(S.SYS_io_destroy, ctx:n()))
  ctx.ctx = 0
  return ret
end

-- TODO replace these functions with metatypes
local function getiocb(ioi, iocb)
  if not iocb then iocb = t.iocb() end
  iocb.aio_lio_opcode = stringflags(ioi.cmd, "IOCB_CMD_")
  iocb.aio_data = ioi.data or 0
  iocb.aio_reqprio = ioi.reqprio or 0
  iocb.aio_fildes = getfd(ioi.fd)
  iocb.aio_buf = ffi.cast(t.int64, ioi.buf) -- TODO check, looks wrong
  iocb.aio_nbytes = ioi.nbytes
  iocb.aio_offset = ioi.offset
  if ioi.resfd then
    iocb.aio_flags = iocb.aio_flags + S.IOCB_FLAG_RESFD
    iocb.aio_resfd = getfd(ioi.resfd)
  end
  return iocb
end

local function getiocbs(iocb, nr)
  if type(iocb) == "table" then
    local io = iocb
    nr = #io
    iocb = t.iocb_ptrs(nr)
    iocba = t.iocbs(nr)
    for i = 0, nr - 1 do
      local ioi = io[i + 1]
      iocb[i] = iocba + i
      getiocb(ioi, iocba[i])
    end
  end
  return iocb, nr
end

function S.io_cancel(ctx, iocb, result)
  iocb = getiocb(iocb)
  if not result then result = t.io_event() end
  local ret = C.syscall(S.SYS_io_cancel, ctx:n(), iocb, result)
  if ret == -1 then return nil, t.error() end
  return ret
end

function S.io_getevents(ctx, min, nr, timeout, events)
  if not events then events = t.io_events(nr) end
  if not ffi.istype(t.timespec, timeout) then timeout = t.timespec(timeout) end
  local ret = C.syscall(S.SYS_io_getevents, ctx:n(), t.long(min), t.long(nr), events, timeout)
  if ret == -1 then return nil, t.error() end
  -- need to think more about how to return these, eg metatype for io_event?
  local r = {}
  for i = 0, nr - 1 do
    r[i + 1] = events[i]
  end
  r.timeout = timeout
  r.events = events
  r.count = tonumber(ret)
  return r
end

function S.io_submit(ctx, iocb, nr) -- takes an array of pointers to iocb. note order of args
  iocb, nr = getiocbs(iocb)
  return retnum(C.syscall(S.SYS_io_submit, ctx:n(), t.long(nr), iocb))
end

-- map for valid options for arg2
local prctlmap = {
  [S.PR_CAPBSET_READ] = "CAP_",
  [S.PR_CAPBSET_DROP] = "CAP_",
  [S.PR_SET_ENDIAN] = "PR_ENDIAN",
  [S.PR_SET_FPEMU] = "PR_FPEMU_",
  [S.PR_SET_FPEXC] = "PR_FP_EXC_",
  [S.PR_SET_PDEATHSIG] = "SIG",
  [S.PR_SET_SECUREBITS] = "SECBIT_",
  [S.PR_SET_TIMING] = "PR_TIMING_",
  [S.PR_SET_TSC] = "PR_TSC_",
  [S.PR_SET_UNALIGN] = "PR_UNALIGN_",
  [S.PR_MCE_KILL] = "PR_MCE_KILL_",
  [S.PR_SET_SECCOMP] = "SECCOMP_MODE_",
}

local prctlrint = { -- returns an integer directly TODO add metatables to set names
  [S.PR_GET_DUMPABLE] = true,
  [S.PR_GET_KEEPCAPS] = true,
  [S.PR_CAPBSET_READ] = true,
  [S.PR_GET_TIMING] = true,
  [S.PR_GET_SECUREBITS] = true,
  [S.PR_MCE_KILL_GET] = true,
  [S.PR_GET_SECCOMP] = true,
}

local prctlpint = { -- returns result in a location pointed to by arg2
  [S.PR_GET_ENDIAN] = true,
  [S.PR_GET_FPEMU] = true,
  [S.PR_GET_FPEXC] = true,
  [S.PR_GET_PDEATHSIG] = true,
  [S.PR_GET_UNALIGN] = true,
}

function S.prctl(option, arg2, arg3, arg4, arg5)
  local i, name
  option = stringflag(option, "PR_") -- actually not all PR_ prefixed options ok some are for other args, could be more specific
  local noption = tonumber(option)
  local m = prctlmap[noption]
  if m then arg2 = stringflag(arg2, m) end
  if option == S.PR_MCE_KILL and arg2 == S.PR_MCE_KILL_SET then arg3 = stringflag(arg3, "PR_MCE_KILL_")
  elseif prctlpint[noption] then
    i = t.int1()
    arg2 = ffi.cast(t.ulong, i)
  elseif option == S.PR_GET_NAME then
    name = t.buffer(16)
    arg2 = ffi.cast(t.ulong, name)
  elseif option == S.PR_SET_NAME then
    if type(arg2) == "string" then arg2 = ffi.cast(t.ulong, arg2) end
  end
  local ret = C.prctl(option, arg2 or 0, arg3 or 0, arg4 or 0, arg5 or 0)
  if ret == -1 then return nil, t.error() end
  if prctlrint[noption] then return ret end
  if prctlpint[noption] then return i[0] end
  if option == S.PR_GET_NAME then
    if name[15] ~= 0 then return ffi.string(name, 16) end -- actually, 15 bytes seems to be longest, aways 0 terminated
    return ffi.string(name)
  end
  return true
end

-- this is the glibc name for the syslog syscall
function S.klogctl(tp, buf, len)
  if not buf and (tp == 2 or tp == 3 or tp == 4) then
    if not len then
      len = C.klogctl(10, nil, 0) -- get size so we can allocate buffer
      if len == -1 then return nil, t.error() end
    end
    buf = t.buffer(len)
  end
  local ret = C.klogctl(tp, buf or nil, len or 0)
  if ret == -1 then return nil, t.error() end
  if tp == 9 or tp == 10 then return tonumber(ret) end
  if tp == 2 or tp == 3 or tp == 4 then return ffi.string(buf, ret) end
  return true
end

function S.adjtimex(a)
  if not a then a = t.timex() end
  if type(a) == 'table' then  -- TODO pull this out to general initialiser for t.timex
    if a.modes then a.modes = tonumber(stringflags(a.modes, "ADJ_")) end
    if a.status then a.status = tonumber(stringflags(a.status, "STA_")) end
    a = t.timex(a)
  end
  local ret = C.adjtimex(a)
  if ret == -1 then return nil, t.error() end
  -- we need to return a table, as we need to return both ret and the struct timex. should probably put timex fields in table
  return setmetatable({state = ret, timex = a}, mt.timex)
end

function S.clock_getres(clk_id, ts)
  if not ffi.istype(t.timespec, ts) then ts = t.timespec(ts) end
  local ret = C.syscall(S.SYS_clock_getres, t.clockid(stringflag(clk_id, "CLOCK_")), pt.void(ts))
  if ret == -1 then return nil, t.error() end
  return ts
end

function S.clock_gettime(clk_id, ts)
  if not ffi.istype(t.timespec, ts) then ts = t.timespec(ts) end
  local ret = C.syscall(S.SYS_clock_gettime, t.clockid(stringflag(clk_id, "CLOCK_")), pt.void(ts))
  if ret == -1 then return nil, t.error() end
  return ts
end

function S.clock_settime(clk_id, ts) return retbool(C.syscall(S.SYS_clock_settime, stringflag(clk_id, "CLOCK_"), getts(ts))) end

-- straight passthroughs, as no failure possible
S.getuid = C.getuid
S.geteuid = C.geteuid
S.getppid = C.getppid
S.getgid = C.getgid
S.getegid = C.getegid
S.sync = C.sync
S.alarm = C.alarm

function S.getpid()
  return C.syscall(S.SYS_getpid) -- bypass glibc caching of pids
end

function S.umask(mask) return C.umask(S.mode(mask)) end

function S.getsid(pid) return retnum(C.getsid(pid or 0)) end
function S.setsid() return retnum(C.setsid()) end

-- handle environment (Lua only provides os.getenv). Could add metatable to make more Lualike.
function S.environ() -- return whole environment as table
  local environ = ffi.C.environ
  if not environ then return nil end
  local r = {}
  local i = 0
  while environ[i] ~= S.pointer(0) do
    local e = ffi.string(environ[i])
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

  local me = pt.char(C.environ)

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
local function b64(n)
  return math.floor(tonumber(n) / 0x100000000), tonumber(n) % 0x100000000
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

function S.makedev(major, minor)
  return bit.bor(bit.band(minor, 0xff), bit.lshift(bit.band(major, 0xfff), 8), bit.lshift(bit.band(minor, bit.bnot(0xff)), 12)) + 0x100000000 * bit.band(major, bit.bnot(0xfff))
end

function S.S_ISREG(m)  return bit.band(m, S.S_IFMT) == S.S_IFREG  end
function S.S_ISDIR(m)  return bit.band(m, S.S_IFMT) == S.S_IFDIR  end
function S.S_ISCHR(m)  return bit.band(m, S.S_IFMT) == S.S_IFCHR  end
function S.S_ISBLK(m)  return bit.band(m, S.S_IFMT) == S.S_IFBLK  end
function S.S_ISFIFO(m) return bit.band(m, S.S_IFMT) == S.S_IFFIFO end
function S.S_ISLNK(m)  return bit.band(m, S.S_IFMT) == S.S_IFLNK  end
function S.S_ISSOCK(m) return bit.band(m, S.S_IFMT) == S.S_IFSOCK end

local function align(len, a) return bit.band(tonumber(len) + a - 1, bit.bnot(a - 1)) end

-- cmsg functions, try to hide some of this nasty stuff from the user
local cmsg_align
local cmsg_hdrsize = ffi.sizeof(t.cmsghdr(0))
if ffi.abi('32bit') then
  function cmsg_align(len) return align(len, 4) end
else
  function cmsg_align(len) return align(len, 8) end
end

local cmsg_ahdr = cmsg_align(cmsg_hdrsize)
local function cmsg_space(len) return cmsg_ahdr + cmsg_align(len) end
local function cmsg_len(len) return cmsg_ahdr + len end

-- msg_control is a bunch of cmsg structs, but these are all different lengths, as they have variable size arrays

-- these functions also take and return a raw char pointer to msg_control, to make life easier, as well as the cast cmsg
local function cmsg_firsthdr(msg)
  if tonumber(msg.msg_controllen) < cmsg_hdrsize then return nil end
  local mc = msg.msg_control
  local cmsg = pt.cmsghdr(mc)
  return mc, cmsg
end

local function cmsg_nxthdr(msg, buf, cmsg)
  if tonumber(cmsg.cmsg_len) < cmsg_hdrsize then return nil end -- invalid cmsg
  buf = pt.char(buf)
  local msg_control = pt.char(msg.msg_control)
  buf = buf + cmsg_align(cmsg.cmsg_len) -- find next cmsg
  if buf + cmsg_hdrsize > msg_control + msg.msg_controllen then return nil end -- header would not fit
  cmsg = pt.cmsghdr(buf)
  if buf + cmsg_align(cmsg.cmsg_len) > msg_control + msg.msg_controllen then return nil end -- whole cmsg would not fit
  return buf, cmsg
end

-- similar functions for netlink messages
local function nlmsg_align(len) return align(len, 4) end
local nlmsg_hdrlen = nlmsg_align(ffi.sizeof(t.nlmsghdr))
local function nlmsg_length(len) return len + nlmsg_hdrlen end
local function nlmsg_ok(msg, len)
  return len >= nlmsg_hdrlen and msg.nlmsg_len >= nlmsg_hdrlen and msg.nlmsg_len <= len
end
local function nlmsg_next(msg, buf, len)
  local inc = nlmsg_align(msg.nlmsg_len)
  return pt.nlmsghdr(buf + inc), buf + inc, len - inc
end

local rta_align = nlmsg_align -- also 4 byte align
local function rta_length(len) return len + rta_align(ffi.sizeof(t.rtattr)) end
local function rta_ok(msg, len)
  return len >= ffi.sizeof(t.rtattr) and msg.rta_len >= ffi.sizeof(t.rtattr) and msg.rta_len <= len
end
local function rta_next(msg, buf, len)
  local inc = rta_align(msg.rta_len)
  return pt.rtattr(buf + inc), buf + inc, len - inc
end

local addrlenmap = { -- map interface type to length of hardware address
  [S.ARPHRD_ETHER] = 6,
  [S.ARPHRD_EETHER] = 6,
  [S.ARPHRD_LOOPBACK] = 6,
}

local ifla_decode = {
  [S.IFLA_IFNAME] = function(ir, buf, len)
    ir.name = ffi.string(buf)
  end,
  [S.IFLA_ADDRESS] = function(ir, buf, len)
    local addrlen = addrlenmap[ir.type]
    if (addrlen) then
      ir.addrlen = addrlen
      ir.macaddr = t.macaddr()
      ffi.copy(ir.macaddr, buf, addrlen)
    end
  end,
  [S.IFLA_BROADCAST] = function(ir, buf, len)
    local addrlen = addrlenmap[ir.type]
    if (addrlen) then
      ir.braddrlen = addrlen
      ir.broadcast = t.macaddr()
      ffi.copy(ir.broadcast, buf, addrlen)
    end
  end,
  [S.IFLA_MTU] = function(ir, buf, len)
    local u = pt.uint(buf)
    ir.mtu = tonumber(u[0])
  end,
  [S.IFLA_LINK] = function(ir, buf, len)
    local i = pt.int(buf)
    ir.link = tonumber(i[0])
  end,
  [S.IFLA_QDISC] = function(ir, buf, len)
    ir.qdisc = ffi.string(buf)
  end,
  [S.IFLA_STATS] = function(ir, buf, len)
    ir.stats = t.rtnl_link_stats() -- despite man page, this is what kernel uses. So only get 32 bit stats here.
    ffi.copy(ir.stats, buf, ffi.sizeof(t.rtnl_link_stats))
  end
}

local ifa_decode = {
  [S.IFA_ADDRESS] = function(ir, buf, len)
    ir.addr = S.addrtype[ir.family]()
    ffi.copy(ir.addr, buf, ffi.sizeof(ir.addr))
  end,
  [S.IFA_LOCAL] = function(ir, buf, len)
    ir.loc = S.addrtype[ir.family]()
    ffi.copy(ir.loc, buf, ffi.sizeof(ir.loc))
  end,
  [S.IFA_BROADCAST] = function(ir, buf, len)
    ir.broadcast = S.addrtype[ir.family]()
    ffi.copy(ir.broadcast, buf, ffi.sizeof(ir.broadcast))
  end,
  [S.IFA_LABEL] = function(ir, buf, len)
    ir.label = ffi.string(buf)
  end,
  [S.IFA_ANYCAST] = function(ir, buf, len)
    ir.anycast = S.addrtype[ir.family]()
    ffi.copy(ir.anycast, buf, ffi.sizeof(ir.anycast))
  end,
  [S.IFA_CACHEINFO] = function(ir, buf, len)
    ir.cacheinfo = t.ifa_cacheinfo()
    ffi.copy(ir.cacheinfo, buf, ffi.sizeof(t.ifa_cacheinfo))
  end
}

mt.iff = {
  __tostring = function(f)
    local s = {}
    local flags = {"UP", "BROADCAST", "DEBUG", "LOOPBACK", "POINTOPOINT", "NOTRAILERS", "RUNNING", "NOARP", "PROMISC",
                   "ALLMULTI", "MASTER", "SLAVE", "MULTICAST", "PORTSEL", "AUTOMEDIA", "DYNAMIC", "LOWER_UP", "DORMANT", "ECHO"}
    for _, i in pairs(flags) do if f[i] then s[#s + 1] = i end end
    return table.concat(s, ' ')
  end,
  __index = function(f, k)
    local prefix = "IFF_"
    if k:sub(1, #prefix) ~= prefix then k = prefix .. k:upper() end
    if S[k] then return bit.band(f.flags, S[k]) ~= 0 end
  end
}

S.encapnames = {
  [S.ARPHRD_ETHER] = "Ethernet",
  [S.ARPHRD_LOOPBACK] = "Local Loopback",
}

mt.iflinks = {
  __tostring = function(is)
    local s = {}
    for _, v in ipairs(is) do
      s[#s + 1] = tostring(v)
    end
    return table.concat(s, '\n')
  end
}

mt.iflink = {
  __index = function(i, k)
    local meth = {
      family = function(i) return tonumber(i.ifinfo.ifi_family) end,
      type = function(i) return tonumber(i.ifinfo.ifi_type) end,
      typename = function(i)
        local n = S.encapnames[i.type]
        return n or 'unknown ' ..i.type
      end,
      index = function(i) return tonumber(i.ifinfo.ifi_index) end,
      flags = function(i) return setmetatable({flags = tonumber(i.ifinfo.ifi_flags)}, mt.iff) end,
      change = function(i) return tonumber(i.ifinfo.ifi_change) end,
      setflags = function(i) return function(v) return S.setlink(i.index, v) end end,
    }
    if meth[k] then return meth[k](i) end
    local prefix = "ARPHRD_"
    if k:sub(1, #prefix) ~= prefix then k = prefix .. k:upper() end
    if S[k] then return i.ifinfo.ifi_type == S[k] end
  end,
  __tostring = function(i)
    local hw = ''
    if not i.loopback and i.macaddr then hw = '  HWaddr ' .. tostring(i.macaddr) end
    local s = i.name .. string.rep(' ', 10 - #i.name) .. 'Link encap:' .. i.typename .. hw .. '\n'
    for a = 1, #i.inet do
      s = s .. '          ' .. 'inet addr: ' .. tostring(i.inet[a].addr) .. '/' .. i.inet[a].prefixlen .. '\n'
    end
    for a = 1, #i.inet6 do
      s = s .. '          ' .. 'inet6 addr: ' .. tostring(i.inet6[a].addr) .. '/' .. i.inet6[a].prefixlen .. '\n'
    end
      s = s .. '          ' .. tostring(i.flags) .. '  MTU: ' .. i.mtu .. '\n'
      s = s .. '          ' .. 'RX packets:' .. i.stats.rx_packets .. ' errors:' .. i.stats.rx_errors .. ' dropped:' .. i.stats.rx_dropped .. '\n'
      s = s .. '          ' .. 'TX packets:' .. i.stats.tx_packets .. ' errors:' .. i.stats.tx_errors .. ' dropped:' .. i.stats.tx_dropped .. '\n'
    return s
  end
}

mt.ifaddr = {
  __index = function(i, k)
    local meth = {
      family = function(i) return tonumber(i.ifaddr.ifa_family) end,
      prefixlen = function(i) return tonumber(i.ifaddr.ifa_prefixlen) end,
      index = function(i) return tonumber(i.ifaddr.ifa_index) end,
      flags = function(i) return tonumber(i.ifaddr.ifa_flags) end,
      scope = function(i) return tonumber(i.ifaddr.ifa_scope) end,
    }
    if meth[k] then return meth[k](i) end
    local prefix = "IFA_F_"
    if k:sub(1, #prefix) ~= prefix then k = prefix .. k:upper() end
    if S[k] then return bit.band(i.ifaddr.ifa_flags, S[k]) ~= 0 end
  end
}

local nlmsg_data_decode = {
  [S.NLMSG_NOOP] = function(r, buf, len) return r end,
  [S.NLMSG_ERROR] = function(r, buf, len)
    local e = pt.nlmsgerr(buf)
    if e.error ~= 0 then r.error = e.error else r.ack = true end -- error zero is ACK
    return r
  end,
  [S.NLMSG_DONE] = function(r, buf, len) return r end,
  [S.NLMSG_OVERRUN] = function(r, buf, len)
    r.overrun = true
    return r
  end,
  [S.RTM_NEWADDR] = function(r, buf, len)
    local addr = pt.ifaddrmsg(buf)
    buf = buf + nlmsg_align(ffi.sizeof(t.ifaddrmsg))
    len = len - nlmsg_align(ffi.sizeof(t.ifaddrmsg))
    local rtattr = pt.rtattr(buf)

    local ir = setmetatable({ifaddr = t.ifaddrmsg(), addr = {}}, mt.ifaddr)
    ffi.copy(ir.ifaddr, addr, ffi.sizeof(t.ifaddrmsg))

    while rta_ok(rtattr, len) do
      if ifa_decode[rtattr.rta_type] then
        ifa_decode[rtattr.rta_type](ir, buf + rta_length(0), rta_align(rtattr.rta_len) - rta_length(0))
      end
      rtattr, buf, len = rta_next(rtattr, buf, len)
    end

   r[#r + 1] = ir

   return r
  end,
  [S.RTM_NEWLINK] = function(r, buf, len)
    local iface = pt.ifinfomsg(buf)
    buf = buf + nlmsg_align(ffi.sizeof(t.ifinfomsg))
    len = len - nlmsg_align(ffi.sizeof(t.ifinfomsg))
    local rtattr = pt.rtattr(buf)
    local ir = setmetatable({ifinfo = t.ifinfomsg()}, mt.iflink)
    ffi.copy(ir.ifinfo, iface, ffi.sizeof(t.ifinfomsg))

    while rta_ok(rtattr, len) do
      if ifla_decode[rtattr.rta_type] then
        ifla_decode[rtattr.rta_type](ir, buf + rta_length(0), rta_align(rtattr.rta_len) - rta_length(0))
      end
      rtattr, buf, len = rta_next(rtattr, buf, len)
    end

    r[ir.name] = ir
    r[#r + 1] = ir -- array and names

    return r
  end
}

function S.nlmsg_read(s, addr, bufsize) -- maybe we create the sockaddr?
  if not bufsize then bufsize = 8192 end
  local reply = t.buffer(bufsize)
  local ior = t.iovecs{{reply, bufsize}}
  local m = t.msghdr{msg_iov = ior.iov, msg_iovlen = #ior, msg_name = addr, msg_namelen = ffi.sizeof(addr)}

  local done = false -- what should we do if we get a done message but there is some extra buffer? could be next message...
  local r = {}

  while not done do
    local n, err = s:recvmsg(m)
    if not n then return nil, err end
    local len = tonumber(n.count)
    local buffer = reply

    local msg = pt.nlmsghdr(buffer)

    while not done and nlmsg_ok(msg, len) do
      local tp = tonumber(msg.nlmsg_type)

      if nlmsg_data_decode[tp] then
        r = nlmsg_data_decode[tp](r, buffer + nlmsg_hdrlen, msg.nlmsg_len - nlmsg_hdrlen)

        if r.overrun then return S.nlmsg_read(s, addr, bufsize * 2) end -- TODO add test
        if r.error then return nil, r.error end -- not sure what the errors mean though!
        if r.ack then done = true end

      else error("unknown data " .. tp)
      end

      if tp == S.NLMSG_DONE then done = true end
      msg, buffer, len = nlmsg_next(msg, buffer, len)
    end
  end

  return r
end

-- initial abstraction, expand later
local function nlmsg(ntype, flags, tp, init) -- will need more structures, possibly nested
  local s, err = S.socket("netlink", "raw", "route")
  if not s then return nil, err end
  local a = t.sockaddr_nl() -- kernel will fill in address
  local ok, err = s:bind(a)
  if not ok then return nil, err end -- gc will take care of closing socket...
  a = s:getsockname() -- to get bound address
  if not a then return nil, err end -- gc will take care of closing socket...

  local k = t.sockaddr_nl() -- kernel destination

  local buf, len, hdr, struct = tbuffer(t.nlmsghdr, tp)

  hdr.nlmsg_len = len
  hdr.nlmsg_type = ntype
  hdr.nlmsg_flags = flags
  hdr.nlmsg_seq = s:seq()
  hdr.nlmsg_pid = a.pid

  for k, v in pairs(init) do struct[k] = v end

  local ios = t.iovecs{{buf, len}}
  local m = t.msghdr{msg_iov = ios.iov, msg_iovlen = #ios, msg_name = k, msg_namelen = ffi.sizeof(t.sockaddr_nl)}

  local n, err = s:sendmsg(m)
  if not n then return nil, err end

  local r, err = S.nlmsg_read(s, k)
  if not r then
    s:close()
    return nil, err
  end

  local ok, err = s:close()
  if not ok then return nil, err end

  return r
end

-- read addresses on interfaces.
function S.getaddr(af)
  return nlmsg(S.RTM_GETADDR, S.NLM_F_REQUEST + S.NLM_F_ROOT, t.ifaddrmsg, {ifa_family = stringflag(af, "AF_")})
end

-- read interfaces and details.
function S.getlink()
  return nlmsg(S.RTM_GETLINK, S.NLM_F_REQUEST + S.NLM_F_DUMP, t.rtgenmsg, {rtgen_family = S.AF_PACKET})
end

function S.newlink()
  --return nlmsg(S.RTM_NEWLINK, 
end

function S.setlink(index, flags)
  return nlmsg(S.RTM_SETLINK, S.NLM_F_REQUEST + S.NLM_F_ACK, t.ifinfomsg,
    {ifi_index = index, ifi_flags = stringflags(flags, "IFF_"), ifi_change = 0xffffffff})
end

function S.get_interfaces() -- returns with address info too.
  local ifs, err = S.getlink()
  if not ifs then return nil, err end
  local addr4, err = S.getaddr(S.AF_INET)
  if not addr4 then return nil, err end
  local addr6, err = S.getaddr(S.AF_INET6)
  if not addr6 then return nil, err end
  local indexmap = {}
  for i, v in pairs(ifs) do
    v.inet, v.inet6 = {}, {}
    indexmap[v.index] = i
  end
  for i = 1, #addr4 do
    local v = ifs[indexmap[addr4[i].index]]
    v.inet[#v.inet + 1] = addr4[i]
  end
  for i = 1, #addr6 do
    local v = ifs[indexmap[addr6[i].index]]
    v.inet6[#v.inet6 + 1] = addr6[i]
  end
  return setmetatable(ifs, mt.iflinks)
end

function S.sendmsg(fd, msg, flags)
  if not msg then -- send a single byte message, eg enough to send credentials
    local buf1 = t.buffer(1)
    local io = t.iovecs{{buf1, 1}}
    msg = t.msghdr{msg_iov = io.iov, msg_iovlen = #io}
  end
  return retbool(C.sendmsg(getfd(fd), msg, stringflags(flags, "MSG_")))
end

-- if no msg provided, assume want to receive cmsg
function S.recvmsg(fd, msg, flags)
  if not msg then 
    local buf1 = t.buffer(1) -- assume user wants to receive single byte to get cmsg
    local io = t.iovecs{{buf1, 1}}
    local bufsize = 1024 -- sane default, build your own structure otherwise
    local buf = t.buffer(bufsize)
    msg = t.msghdr{msg_iov = io.iov, msg_iovlen = #io, msg_control = buf, msg_controllen = bufsize}
  end
  local ret = C.recvmsg(getfd(fd), msg, stringflags(flags, "MSG_"))
  if ret == -1 then return nil, t.error() end
  local ret = {count = ret, iovec = msg.msg_iov} -- thats the basic return value, and the iovec
  local mc, cmsg = cmsg_firsthdr(msg)
  while cmsg do
    if cmsg.cmsg_level == S.SOL_SOCKET then
      if cmsg.cmsg_type == S.SCM_CREDENTIALS then
        local cred = pt.ucred(cmsg + 1) -- cmsg_data
        ret.pid = cred.pid
        ret.uid = cred.uid
        ret.gid = cred.gid
      elseif cmsg.cmsg_type == S.SCM_RIGHTS then
        local fda = pt.int(cmsg + 1) -- cmsg_data
        local fdc = div(tonumber(cmsg.cmsg_len) - cmsg_ahdr, ffi.sizeof(t.int1))
        ret.fd = {}
        for i = 1, fdc do ret.fd[i] = t.fd(fda[i - 1]) end
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
  local ucred = t.ucred()
  ucred.pid = pid
  ucred.uid = uid
  ucred.gid = gid
  local buf1 = t.buffer(1) -- need to send one byte
  local io = t.iovecs{{buf1, 1}}
  local usize = ffi.sizeof(t.ucred)
  local bufsize = cmsg_space(usize)
  local buflen = cmsg_len(usize)
  local buf = t.buffer(bufsize) -- this is our cmsg buffer
  local msg = t.msghdr() -- assume socket connected and so does not need address
  msg.msg_iov = io.iov
  msg.msg_iovlen = #io
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
  local buf1 = t.buffer(1) -- need to send one byte
  local io = t.iovecs{{buf1, 1}}
  local fds = {}
  for i, v in ipairs{...} do fds[i] = getfd(v) end
  local fa = t.ints(#fds, fds)
  local fasize = ffi.sizeof(fa)
  local bufsize = cmsg_space(fasize)
  local buflen = cmsg_len(fasize)
  local buf = t.buffer(bufsize) -- this is our cmsg buffer
  local msg = t.msghdr() -- assume socket connected and so does not need address
  msg.msg_iov = io.iov
  msg.msg_iovlen = #io
  msg.msg_control = buf
  msg.msg_controllen = bufsize
  local mc, cmsg = cmsg_firsthdr(msg)
  cmsg.cmsg_level = S.SOL_SOCKET
  cmsg.cmsg_type = S.SCM_RIGHTS
  cmsg.cmsg_len = buflen -- could set from a constructor
  ffi.copy(cmsg + 1, fa, fasize) -- cmsg_data
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

function S.block(s)
  local fl, err = s:fcntl(S.F_GETFL)
  if not fl then return nil, err end
  fl, err = s:fcntl(S.F_SETFL, bit.band(fl, bit.bnot(S.O_NONBLOCK)))
  if not fl then return nil, err end
  return true
end


-- TODO fix short reads, add a loop
function S.readfile(name, buffer, length) -- convenience for reading short files into strings, eg for /proc etc, silently ignores short reads
  local f, err = S.open(name, S.O_RDONLY)
  if not f then return nil, err end
  local r, err = f:read(buffer, length or 4096)
  if not r then return nil, err end
  local ok, err = f:close()
  if not ok then return nil, err end
  return r
end

function S.writefile(name, str, mode) -- write string to named file. specify mode if want to create file, silently ignore short writes
  local f, err
  if mode then f, err = S.creat(name, mode) else f, err = S.open(name, S.O_WRONLY) end
  if not f then return nil, err end
  local n, err = f:write(str)
  if not n then return nil, err end
  local ok, err = f:close()
  if not ok then return nil, err end
  return true
end

function S.dirfile(name, nodots) -- return the directory entries in a file, remove . and .. if nodots true
  local fd, d, ok, err
  fd, err = S.open(name, S.O_DIRECTORY + S.O_RDONLY)
  if err then return nil, err end
  d, err = fd:getdents()
  if err then return nil, err end
  if nodots then
    d["."] = nil
    d[".."] = nil
  end
  ok, err = fd:close()
  if not ok then return nil, err end
  return d
end

mt.ls = {
  __tostring = function(t)
    table.sort(t)
    return table.concat(t, "\n")
    end
}

function S.ls(name, nodots) -- return just the list, no other data, cwd if no directory specified
  if not name then name = S.getcwd() end
  local ds = S.dirfile(name, nodots)
  local l = {}
  for k, _ in pairs(ds) do l[#l + 1] = k end
  return setmetatable(l, mt.ls)
end

local function if_nametoindex(name, s) -- internal version when already have socket for ioctl
  local ifr = t.ifreq()
  local len = #name + 1
  if len > IFNAMSIZ then len = IFNAMSIZ end
  ffi.copy(ifr.ifr_ifrn.ifrn_name, name, len)
  local ret = C.ioctl(getfd(s), S.SIOCGIFINDEX, ifr)
  if ret == -1 then return nil, t.error() end
  return ifr.ifr_ifru.ifru_ivalue
end

function S.if_nametoindex(name) -- standard function in some libc versions
  local s, err = S.socket(S.AF_LOCAL, S.SOCK_STREAM, 0)
  if not s then return nil, err end
  local i, err = if_nametoindex(name, s)
  if not i then return nil, err end
  local ok, err = s:close()
  if not ok then return nil, err end
  return i
end

-- bridge functions, could be in utility library. in error cases use gc to close file.
local function bridge_ioctl(io, name)
  local s, err = S.socket(S.AF_LOCAL, S.SOCK_STREAM, 0)
  if not s then return nil, err end
  local ret = C.ioctl(getfd(s), io, pt.char(name))
  if ret == -1 then return nil, t.error() end
  local ok, err = s:close()
  if not ok then return nil, err end
  return true
end

function S.bridge_add(name) return bridge_ioctl(S.SIOCBRADDBR, name) end
function S.bridge_del(name) return bridge_ioctl(S.SIOCBRDELBR, name) end

local function bridge_if_ioctl(io, bridge, dev)
  local err, s, ifr, len, ret, ok
  s, err = S.socket(S.AF_LOCAL, S.SOCK_STREAM, 0)
  if not s then return nil, err end
  if type(dev) == "string" then
    dev, err = if_nametoindex(dev, s)
    if not dev then return nil, err end
  end
  ifr = t.ifreq()
  len = #bridge + 1
  if len > IFNAMSIZ then len = IFNAMSIZ end
  ffi.copy(ifr.ifr_ifrn.ifrn_name, bridge, len) -- note not using the short forms as no metatable defined yet...
  ifr.ifr_ifru.ifru_ivalue = dev
  ret = C.ioctl(getfd(s), io, ifr);
  if ret == -1 then return nil, t.error() end
  ok, err = s:close()
  if not ok then return nil, err end
  return true
end

function S.bridge_add_interface(bridge, dev) return bridge_if_ioctl(S.SIOCBRADDIF, bridge, dev) end
function S.bridge_add_interface(bridge, dev) return bridge_if_ioctl(S.SIOCBRDELIF, bridge, dev) end

-- should probably have constant for "/sys/class/net"

local function brinfo(d) -- can be used as subpart of general interface info
  local bd = "/sys/class/net/" .. d .. "/" .. S.SYSFS_BRIDGE_ATTR
  if not S.stat(bd) then return nil end
  local bridge = {}
  local fs = S.dirfile(bd, true)
  if not fs then return nil end
  for f, _ in pairs(fs) do
    local s = S.readfile(bd .. "/" .. f)
    if s then
      s = s:sub(1, #s - 1) -- remove newline at end
      if f == "group_addr" or f == "root_id" or f == "bridge_id" then -- string values
        bridge[f] = s
      elseif f == "stp_state" then -- bool
        bridge[f] = s == 1
      else
        bridge[f] = tonumber(s) -- not quite correct, most are timevals TODO
      end
    end
  end

  local brif, err = S.ls("/sys/class/net/" .. d .. "/" .. S.SYSFS_BRIDGE_PORT_SUBDIR, true)
  if not brif then return nil end

  local fdb = "/sys/class/net/" .. d .. "/" .. S.SYSFS_BRIDGE_FDB
  if not S.stat(fdb) then return nil end
  local sl = 2048
  local buffer = t.buffer(sl)
  local fd = S.open(fdb, S.O_RDONLY)
  if not fd then return nil end
  local brforward = {}

  repeat
    local n = fd:read(buffer, sl)
    if not n then return nil end

    local fdbs = pt.fdb_entry(buffer)

    for i = 1, n / ffi.sizeof(t.fdb_entry) do
      local fdb = fdbs[i - 1]
      local mac = t.macaddr()
      ffi.copy(mac, fdb.mac_addr, IFHWADDRLEN)

      -- TODO ageing_timer_value is not an int, time, float
      brforward[#brforward + 1] = {
        mac_addr = mac, port_no = tonumber(fdb.port_no),
        is_local = fdb.is_local ~= 0,
        ageing_timer_value = tonumber(fdb.ageing_timer_value)
      }
    end

  until n == 0
  if not fd:close() then return nil end

  return {bridge = bridge, brif = brif, brforward = brforward}
end

function S.bridge_list()
  local dir, err = S.dirfile("/sys/class/net", true)
  if not dir then return nil, err end
  local b = {}
  for d, _ in pairs(dir) do
    b[d] = brinfo(d)
  end
  return b
end

mt.proc = {
  __index = function(p, k)
    local name = p.dir .. k
    local st, err = S.lstat(name)
    if not st then return nil, err end
    if st.isreg then
      local fd, err = S.open(p.dir .. k, "rdonly")
      if not fd then return nil, err end
      local ret, err = fd:read() -- read defaults to 4k, sufficient?
      if not ret then return nil, err end
      fd:close()
      return ret -- TODO many could usefully do with some parsing
    end
    if st.islnk then
      local ret, err = S.readlink(name)
      if not ret then return nil, err end
      return ret
    end
    -- TODO directories
  end,
  __tostring = function(p) -- TODO decide what to print
    local c = p.cmdline
    if #c == 0 and p.comm and #p.comm > 0 then c = '[' .. p.comm:sub(1, -2) .. ']' end 
    return p.pid .. '  ' .. c
  end
}

function S.proc(pid)
  if not pid then pid = S.getpid() end
  return setmetatable({pid = pid, dir = "/proc/" .. pid .. "/"}, mt.proc)
end

mt.ps = {
  __tostring = function(ps)
    local s = {}
    for i = 1, #ps do
      s[#s + 1] = tostring(ps[i])
    end
    return table.concat(s, '\n')
  end
}

function S.ps()
  local ls = S.ls("/proc")
  local ps = {}
  for i = 1, #ls do
    if not string.match(ls[i], '[^%d]') then
      local p = S.proc(tonumber(ls[i]))
      if p then ps[#ps + 1] = p end
    end
  end
  table.sort(ps, function(a, b) return a.pid < b.pid end)
  return setmetatable(ps, mt.ps)
end

function S.cfmakeraw(termios)
  C.cfmakeraw(termios)
  return true
end

function S.cfgetispeed(termios)
  local bits = C.cfgetispeed(termios)
  if bits == -1 then return nil, t.error() end
  return bits_to_speed(bits)
end

function S.cfgetospeed(termios)
  local bits = C.cfgetospeed(termios)
  if bits == -1 then return nil, t.error() end
  return bits_to_speed(bits)
end

function S.cfsetispeed(termios, speed)
  return retbool(C.cfsetispeed(termios, speed_to_bits(speed)))
end

function S.cfsetospeed(termios, speed)
  return retbool(C.cfsetospeed(termios, speed_to_bits(speed)))
end

function S.cfsetspeed(termios, speed)
  return retbool(C.cfsetspeed(termios, speed_to_bits(speed)))
end

t.termios = ffi.metatype("struct termios", {
  __index = {
    cfmakeraw = S.cfmakeraw,
    cfgetispeed = S.cfgetispeed,
    cfgetospeed = S.cfgetospeed,
    cfsetispeed = S.cfsetispeed,
    cfsetospeed = S.cfsetospeed,
    cfsetspeed = S.cfsetspeed
  }
})

function S.tcgetattr(fd)
  local termios = t.termios()
  local ret = C.tcgetattr(getfd(fd), termios)
  if ret == -1 then return nil, t.error() end
  return termios
end

function S.tcsetattr(fd, optional_actions, termios)
  return retbool(C.tcsetattr(getfd(fd), stringflag(optional_actions, "TCSA"), termios))
end

function S.tcsendbreak(fd, duration)
  return retbool(C.tcsendbreak(getfd(fd), duration))
end

function S.tcdrain(fd)
  return retbool(C.tcdrain(getfd(fd)))
end

function S.tcflush(fd, queue_selector)
  return retbool(C.tcflush(getfd(fd), stringflag(queue_selector, "TC")))
end

function S.tcflow(fd, action)
  return retbool(C.tcflow(getfd(fd), stringflag(action, "TC")))
end

function S.tcgetsid(fd)
  return retnum(C.tcgetsid(getfd(fd)))
end

function S.posix_openpt(flags)
  return retfd(C.posix_openpt(stringflags(flags, "O_")))
end

function S.grantpt(fd)
  return retbool(C.grantpt(getfd(fd)))
end

function S.unlockpt(fd)
  return retbool(C.unlockpt(getfd(fd)))
end

function S.ptsname(fd)
  local count = 32
  local buf = t.buffer(count)
  local ret = C.ptsname_r(getfd(fd), buf, count)
  if ret == 0 then
    return ffi.string(buf)
  else
    return retbool(ret)
  end
end

-- constants
S.INADDR_ANY = t.in_addr()
S.INADDR_LOOPBACK = t.in_addr("127.0.0.1")
S.INADDR_BROADCAST = t.in_addr("255.255.255.255")
-- ipv6 versions
S.in6addr_any = t.in6_addr()
S.in6addr_loopback = t.in6_addr("::1")

-- methods on an fd
local fdmethods = {'nogc', 'nonblock', 'block', 'sendfds', 'sendcred',
                   'close', 'dup', 'read', 'write', 'pread', 'pwrite',
                   'lseek', 'fchdir', 'fsync', 'fdatasync', 'fstat', 'fcntl', 'fchmod',
                   'bind', 'listen', 'connect', 'accept', 'getsockname', 'getpeername',
                   'send', 'sendto', 'recv', 'recvfrom', 'readv', 'writev', 'sendmsg',
                   'recvmsg', 'setsockopt', 'epoll_ctl', 'epoll_wait', 'sendfile', 'getdents',
                   'eventfd_read', 'eventfd_write', 'ftruncate', 'shutdown', 'getsockopt',
                   'inotify_add_watch', 'inotify_rm_watch', 'inotify_read', 'flistxattr',
                   'fsetxattr', 'fgetxattr', 'fremovexattr', 'fxattr', 'splice', 'vmsplice', 'tee',
                   'signalfd_read', 'timerfd_gettime', 'timerfd_settime', 'timerfd_read',
                   'posix_fadvise', 'fallocate', 'posix_fallocate', 'readahead',
                   'tcgetattr', 'tcsetattr', 'tcsendbreak', 'tcdrain', 'tcflush', 'tcflow', 'tcgetsid',
                   'grantpt', 'unlockpt', 'ptsname', 'sync_file_range', 'fstatfs', 'futimens'
                   }
local fmeth = {}
for _, v in ipairs(fdmethods) do fmeth[v] = S[v] end

-- allow calling without leading f
fmeth.stat = S.fstat
fmeth.chdir = S.fchdir
fmeth.sync = S.fsync
fmeth.datasync = S.fdatasync
fmeth.chmod = S.fchmod
fmeth.setxattr = S.fsetxattr
fmeth.getxattr = S.gsetxattr
fmeth.truncate = S.ftruncate
fmeth.statfs = S.fstatfs
fmeth.utimens = S.futimens

-- sequence number used by netlink messages
fmeth.seq = function(fd)
  fd.sequence = fd.sequence + 1
  return fd.sequence
end

t.fd = ffi.metatype("struct {int fileno; int sequence;}", {
  __index = fmeth,
  __gc = S.close,
})

S.stdin = ffi.gc(t.fd(S.STDIN_FILENO), nil)
S.stdout = ffi.gc(t.fd(S.STDOUT_FILENO), nil)
S.stderr = ffi.gc(t.fd(S.STDERR_FILENO), nil)

t.aio_context = ffi.metatype("struct {aio_context_t ctx;}", {
  __index = {destroy = S.io_destroy, submit = S.io_submit, getevents = S.io_getevents, cancel = S.io_cancel,
             n = function(ctx) return t.ulong(ctx.ctx) end},
  __gc = S.io_destroy
})

return S

end

return syscall()


