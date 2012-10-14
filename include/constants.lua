-- tables of constants

-- so far almost all the single flag options have been converted to seperate tables with metamethods but still TODO
-- are the multi flag ones

local ffi = require "ffi"
local bit = require "bit"

local arch = require("include/constants-" .. ffi.arch) -- architecture specific code

local function octal(s) return tonumber(s, 8) end 

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

local function trim(s) -- TODO should replace underscore with space
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- for single valued flags only
local function strflag(t, str)
  if not str then return 0 end
  if type(str) ~= "string" then return str end
  if #str == 0 then return 0 end
  local val = rawget(t, str)
  if val then return val end  
  local s = trim(str):upper()
  if #s == 0 then return 0 end
  local val = rawget(t, s)
  if not val then return nil end
  t[str] = val -- this memoizes for future use
  return val
end

local stringflag = {__index = strflag, __call = function(t, a) return t[a] end}

local S = {} -- TODO rename

S.SYS = arch.SYS

S.STD = setmetatable({
  IN_FILENO = 0,
  OUT_FILENO = 1,
  ERR_FILENO = 2,
  IN = 0,
  OUT = 1,
  ERR = 2,
}, stringflag)

-- sizes
S.PATH_MAX = 4096

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

-- incorporate into metatable for O so set as O>LARGEFILE or 0
if ffi.abi("32bit") then S.O_LARGEFILE = octal('0100000') else S.O_LARGEFILE = 0 end

-- these are arch dependent!
if arch.oflags then arch.oflags(S)
else -- generic values from asm-generic
  S.O_DIRECTORY = octal('0200000')
  S.O_NOFOLLOW  = octal('0400000')
  S.O_DIRECT    = octal('040000')
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

-- access
S.R_OK = 4
S.W_OK = 2
S.X_OK = 1
S.F_OK = 0

-- fcntl
S.F = setmetatable({
  DUPFD       = 0,
  GETFD       = 1,
  SETFD       = 2,
  GETFL       = 3,
  SETFL       = 4,
  GETLK       = 5,
  SETLK       = 6,
  SETLKW      = 7,
  SETOWN      = 8,
  GETOWN      = 9,
  SETSIG      = 10,
  GETSIG      = 11,
  GETLK64     = 12,
  SETLK64     = 13,
  SETLKW64    = 14,
  SETOWN_EX   = 15,
  GETOWN_EX   = 16,
  SETLEASE    = 1024,
  GETLEASE    = 1025,
  NOTIFY      = 1026,
  SETPIPE_SZ  = 1031,
  GETPIPE_SZ  = 1032,
  DUPFD_CLOEXEC = 1030,
}, stringflag)

-- messy
if ffi.abi("64bit") then
  S.F.GETLK64   = S.F.GETLK
  S.F.SETLK64   = S.F.SETLK
  S.F.SETLKW64  = S.F.SETLKW
else
  S.F.GETLK     = S.F.GETLK64
  S.F.SETLK     = S.F.SETLK64
  S.F.SETLKW    = S.F.SETLKW64
end

S.FD_CLOEXEC = 1

-- note changed from F_ to FCNTL_LOCK
S.FCNTL_LOCK = setmetatable({
  RDLCK = 0,
  WRLCK = 1,
  UNLCK = 2,
}, stringflag)

-- lockf, changed from F_ to LOCKF_
S.LOCKF = setmetatable({
  ULOCK = 0,
  LOCK  = 1,
  TLOCK = 2,
  TEST  = 3,
}, stringflag)

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
S.MAP_GROWSDOWN  = 0x00100
S.MAP_DENYWRITE  = 0x00800
S.MAP_EXECUTABLE = 0x01000
S.MAP_LOCKED     = 0x02000
S.MAP_NORESERVE  = 0x04000
S.MAP_POPULATE   = 0x08000
S.MAP_NONBLOCK   = 0x10000
S.MAP_STACK      = 0x20000
S.MAP_HUGETLB    = 0x40000

-- flags for `mlockall'.
S.MCL_CURRENT    = 1
S.MCL_FUTURE     = 2

-- flags for `mremap'.
S.MREMAP_MAYMOVE = 1
S.MREMAP_FIXED   = 2

-- madvise advice parameter
S.MADV = setmetatable({
  NORMAL      = 0,
  RANDOM      = 1,
  SEQUENTIAL  = 2,
  WILLNEED    = 3,
  DONTNEED    = 4,
  REMOVE      = 9,
  DONTFORK    = 10,
  DOFORK      = 11,
  MERGEABLE   = 12,
  UNMERGEABLE = 13,
  HUGEPAGE    = 14,
  NOHUGEPAGE  = 15,
  HWPOISON    = 100,
}, stringflag)

-- posix fadvise
S.POSIX_FADV = setmetatable({
  NORMAL       = 0,
  RANDOM       = 1,
  SEQUENTIAL   = 2,
  WILLNEED     = 3,
  DONTNEED     = 4,
  NOREUSE      = 5,
}, stringflag)

-- fallocate
S.FALLOC_FL = setmetatable({
  KEEP_SIZE  = 0x01,
  PUNCH_HOLE = 0x02,
}, stringflag)

-- getpriority, setpriority flags
S.PRIO = setmetatable({
  PROCESS = 0,
  PGRP = 1,
  USER = 2,
}, stringflag)

-- lseek
S.SEEK = setmetatable({
  SET = 0,
  CUR = 1,
  END = 2,
}, stringflag)

-- exit
S.EXIT = setmetatable({
  SUCCESS = 0,
  FAILURE = 1,
}, stringflag)

-- sigaction, note renamed SIGACT from SIG
S.SIGACT = setmetatable({
  ERR = -1,
  DFL =  0,
  IGN =  1,
  HOLD = 2,
}, stringflag)

S.SIG = setmetatable({
  HUP = 1,
  INT = 2,
  QUIT = 3,
  ILL = 4,
  TRAP = 5,
  ABRT = 6,
  BUS = 7,
  FPE = 8,
  KILL = 9,
  USR1 = 10,
  SEGV = 11,
  USR2 = 12,
  PIPE = 13,
  ALRM = 14,
  TERM = 15,
  STKFLT = 16,
  CHLD = 17,
  CONT = 18,
  STOP = 19,
  TSTP = 20,
  TTIN = 21,
  TTOU = 22,
  URG  = 23,
  XCPU = 24,
  XFSZ = 25,
  VTALRM = 26,
  PROF = 27,
  WINCH = 28,
  IO = 29,
  PWR = 30,
  SYS = 31,
}, stringflag)

local signals = {}
for k, v in pairs(S.SIG) do signals[v] = k end

S.SIG.IOT = 6
S.SIG.UNUSED     = 31
S.SIG.CLD        = S.SIG.CHLD
S.SIG.POLL       = S.SIG.IO

S.NSIG          = 65

-- sigprocmask note renaming of SIG to SIGPM
S.SIGPM = setmetatable({
  BLOCK     = 0,
  UNBLOCK   = 1,
  SETMASK   = 2,
}, stringflag)

-- signalfd
S.SFD_CLOEXEC  = octal('02000000')
S.SFD_NONBLOCK = octal('04000')

-- sockets note mix of single and multiple flags
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
S.SCM = setmetatable({
  RIGHTS = 0x01,
  CREDENTIALS = 0x02,
}, stringflag)

-- setsockopt
S.SOL = setmetatable({
  SOCKET     = 1,
  RAW        = 255,
  DECNET     = 261,
  X25        = 262,
  PACKET     = 263,
  ATM        = 264,
  AAL        = 265,
  IRDA       = 266,
}, stringflag)

S.SO = setmetatable({
  DEBUG       = 1,
  REUSEADDR   = 2,
  TYPE        = 3,
  ERROR       = 4,
  DONTROUTE   = 5,
  BROADCAST   = 6,
  SNDBUF      = 7,
  RCVBUF      = 8,
  KEEPALIVE   = 9,
  OOBINLINE   = 10,
  NO_CHECK    = 11,
  PRIORITY    = 12,
  LINGER      = 13,
  BSDCOMPAT   = 14,
  SNDBUFFORCE = 32,
  RCVBUFFORCE = 33,
}, stringflag)
if arch.socketoptions then arch.socketoptions(S)
else
  S.SO.PASSCRED    = 16
  S.SO.PEERCRED    = 17
  S.SO.RCVLOWAT    = 18
  S.SO.SNDLOWAT    = 19
  S.SO.RCVTIMEO    = 20
  S.SO.SNDTIMEO    = 21
end

-- Maximum queue length specifiable by listen.
S.SOMAXCONN = 128

-- shutdown
S.SHUT = setmetatable({
  RD   = 0,
  WR   = 1,
  RDWR = 2,
}, stringflag)

-- waitpid 3rd arg
S.WNOHANG       = 1
S.WUNTRACED     = 2

-- waitid
S.P = setmetatable({
  ALL  = 0,
  PID  = 1,
  PGID = 2,
}, stringflag)

S.WSTOPPED      = 2
S.WEXITED       = 4
S.WCONTINUED    = 8
S.WNOWAIT       = 0x01000000

S.__WNOTHREAD    = 0x20000000
S.__WALL         = 0x40000000
S.__WCLONE       = 0x80000000
S.NOTHREAD, S.WALL, S.WCLONE = S.__WNOTHREAD, S.__WALL, S.__WCLONE

-- struct siginfo, eg waitid
S.SI = setmetatable({
  ASYNCNL = -60,
  TKILL = -6,
  SIGIO = -5,
  ASYNCIO = -4,
  MESGQ = -3,
  TIMER = -2,
  QUEUE = -1,
  USER = 0,
  KERNEL = 0x80,
}, stringflag)

S.ILL = setmetatable({
  ILLOPC = 1,
  ILLOPN = 2,
  ILLADR = 3,
  ILLTRP = 4,
  PRVOPC = 5,
  PRVREG = 6,
  COPROC = 7,
  BADSTK = 8,
}, stringflag)

S.FPE = setmetatable({
  INTDIV = 1,
  INTOVF = 2,
  FLTDIV = 3,
  FLTOVF = 4,
  FLTUND = 5,
  FLTRES = 6,
  FLTINV = 7,
  FLTSUB = 8,
}, stringflag)

S.SEGV = setmetatable({
  MAPERR = 1,
  ACCERR = 2,
}, stringflag)

S.BUS = setmetatable({
  ADRALN = 1,
  ADRERR = 2,
  OBJERR = 3,
}, stringflag)

S.TRAP = setmetatable({
  BRKPT = 1,
  TRACE = 2,
}, stringflag)

S.CLD = setmetatable({
  EXITED    = 1,
  KILLED    = 2,
  DUMPED    = 3,
  TRAPPED   = 4,
  STOPPED   = 5,
  CONTINUED = 6,
}, stringflag)

S.POLL = setmetatable({
  IN  = 1,
  OUT = 2,
  MSG = 3,
  ERR = 4,
  PRI = 5,
  HUP = 6,
}, stringflag)

-- sigaction
S.SA_NOCLDSTOP = 0x00000001
S.SA_NOCLDWAIT = 0x00000002
S.SA_SIGINFO   = 0x00000004
S.SA_ONSTACK   = 0x08000000
S.SA_RESTART   = 0x10000000
S.SA_NODEFER   = 0x40000000
S.SA_RESETHAND = 0x80000000
S.SA_NOMASK    = S.SA_NODEFER
S.SA_ONESHOT   = S.SA_RESETHAND
S.SA_RESTORER  = 0x04000000

-- timers
S.ITIMER = setmetatable({
  REAL    = 0,
  VIRTUAL = 1,
  PROF    = 2,
}, stringflag)

-- clocks
S.CLOCK = setmetatable({
  REALTIME           = 0,
  MONOTONIC          = 1,
  PROCESS_CPUTIME_ID = 2,
  THREAD_CPUTIME_ID  = 3,
  MONOTONIC_RAW      = 4,
  REALTIME_COARSE    = 5,
  MONOTONIC_COARSE   = 6,
}, stringflag)

S.TIMER = setmetatable({
  ABSTIME = 1,
}, stringflag)

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

-- return values for adjtimex
S.TIME = setmetatable({
  OK         = 0,
  INS        = 1,
  DEL        = 2,
  OOP        = 3,
  WAIT       = 4,
  ERROR      = 5,
}, stringflag)

S.TIME.BAD        = S.TIME.ERROR

-- xattr
S.XATTR = setmetatable({
  CREATE  = 1,
  REPLACE = 2,
}, stringflag)

-- utime
S.UTIME = setmetatable({
  NOW  = bit.lshift(1, 30) - 1,
  OMIT = bit.lshift(1, 30) - 2,
}, stringflag)

-- ...at commands
S.AT_FDCWD = -100
S.AT_SYMLINK_NOFOLLOW    = 0x100
S.AT_REMOVEDIR           = 0x200
S.AT_SYMLINK_FOLLOW      = 0x400
S.AT_NO_AUTOMOUNT        = 0x800
S.AT_EACCESS             = 0x200

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
S.RLIMIT = setmetatable({
  CPU        = 0,
  FSIZE      = 1,
  DATA       = 2,
  STACK      = 3,
  CORE       = 4,
  RSS        = 5,
  NPROC      = 6,
  NOFILE     = 7,
  MEMLOCK    = 8,
  AS         = 9,
  LOCKS      = 10,
  SIGPENDING = 11,
  MSGQUEUE   = 12,
  NICE       = 13,
  RTPRIO     = 14,
  RTTIME     = 15,
}, stringflag)

S.RLIMIT.OFILE = S.RLIMIT.NOFILE

-- timerfd
S.TFD_CLOEXEC = octal("02000000")
S.TFD_NONBLOCK = octal("04000")

S.TFD_TIMER = setmetatable({
  ABSTIME = 1,
}, stringflag)

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
S.EPOLLET = bit.lshift(1, 30) * 2 -- 2^31 but making sure no sign issue 

S.EPOLL_CTL = setmetatable({
  ADD = 1,
  DEL = 2,
  MOD = 3,
}, stringflag)

-- splice etc
S.SPLICE_F_MOVE         = 1
S.SPLICE_F_NONBLOCK     = 2
S.SPLICE_F_MORE         = 4
S.SPLICE_F_GIFT         = 8

-- aio - see /usr/include/linux/aio_abi.h
S.IOCB_CMD = setmetatable({
  PREAD   = 0,
  PWRITE  = 1,
  FSYNC   = 2,
  FDSYNC  = 3,
-- PREADX = 4,
-- POLL   = 5,
  NOOP    = 6,
  PREADV  = 7,
  PWRITEV = 8,
}, stringflag)

S.IOCB_FLAG_RESFD = 1

-- file types in directory
S.DT = setmetatable({
  UNKNOWN = 0,
  FIFO = 1,
  CHR = 2,
  DIR = 4,
  BLK = 6,
  REG = 8,
  LNK = 10,
  SOCK = 12,
  WHT = 14,
}, stringflag)

-- sync file range
S.SYNC_FILE_RANGE_WAIT_BEFORE = 1
S.SYNC_FILE_RANGE_WRITE       = 2
S.SYNC_FILE_RANGE_WAIT_AFTER  = 4

-- netlink
S.NETLINK = setmetatable({
  ROUTE         = 0,
  UNUSED        = 1,
  USERSOCK      = 2,
  FIREWALL      = 3,
  INET_DIAG     = 4,
  NFLOG         = 5,
  XFRM          = 6,
  SELINUX       = 7,
  ISCSI         = 8,
  AUDIT         = 9,
  FIB_LOOKUP    = 10,     
  CONNECTOR     = 11,
  NETFILTER     = 12,
  IP6_FW        = 13,
  DNRTMSG       = 14,
  KOBJECT_UEVENT= 15,
  GENERIC       = 16,
  SCSITRANSPORT = 18,
  ECRYPTFS      = 19,
}, stringflag)

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

-- generic types. These are part of same sequence as RTM
S.NLMSG = setmetatable({
  NOOP     = 0x1,
  ERROR    = 0x2,
  DONE     = 0x3,
  OVERRUN  = 0x4,
}, stringflag)

-- routing
S.RTM = setmetatable({
  NEWLINK     = 16,
  DELLINK     = 17,
  GETLINK     = 18,
  SETLINK     = 19,
  NEWADDR     = 20,
  DELADDR     = 21,
  GETADDR     = 22,
  NEWROUTE    = 24,
  DELROUTE    = 25,
  GETROUTE    = 26,
  NEWNEIGH    = 28,
  DELNEIGH    = 29,
  GETNEIGH    = 30,
  NEWRULE     = 32,
  DELRULE     = 33,
  GETRULE     = 34,
  NEWQDISC    = 36,
  DELQDISC    = 37,
  GETQDISC    = 38,
  NEWTCLASS   = 40,
  DELTCLASS   = 41,
  GETTCLASS   = 42,
  NEWTFILTER  = 44,
  DELTFILTER  = 45,
  GETTFILTER  = 46,
  NEWACTION   = 48,
  DELACTION   = 49,
  GETACTION   = 50,
  NEWPREFIX   = 52,
  GETMULTICAST = 58,
  GETANYCAST  = 62,
  NEWNEIGHTBL = 64,
  GETNEIGHTBL = 66,
  SETNEIGHTBL = 67,
  NEWNDUSEROPT = 68,
  NEWADDRLABEL = 72,
  DELADDRLABEL = 73,
  GETADDRLABEL = 74,
  GETDCB = 78,
  SETDCB = 79,
}, stringflag)

-- linux/if_link.h
S.IFLA = setmetatable({
  UNSPEC    = 0,
  ADDRESS   = 1,
  BROADCAST = 2,
  IFNAME    = 3,
  MTU       = 4,
  LINK      = 5,
  QDISC     = 6,
  STATS     = 7,
  COST      = 8,
  PRIORITY  = 9,
  MASTER    = 10,
  WIRELESS  = 11,
  PROTINFO  = 12,
  TXQLEN    = 13,
  MAP       = 14,
  WEIGHT    = 15,
  OPERSTATE = 16,
  LINKMODE  = 17,
  LINKINFO  = 18,
  NET_NS_PID= 19,
  IFALIAS   = 20,
  NUM_VF    = 21,
  VFINFO_LIST = 22,
  STATS64   = 23,
  VF_PORTS  = 24,
  PORT_SELF = 25,
  AF_SPEC   = 26,
  GROUP     = 27,
  NET_NS_FD = 28,
}, stringflag)

S.IFLA_INET = setmetatable({
  UNSPEC = 0,
  CONF   = 1,
}, stringflag)

S.IFLA_INET6 = setmetatable({
  UNSPEC = 0,
  FLAGS  = 1,
  CONF   = 2,
  STATS  = 3,
  MCAST  = 4,
  CACHEINFO  = 5,
  ICMP6STATS = 6,
}, stringflag)

S.IFLA_INFO = setmetatable({
  UNSPEC = 0,
  KIND   = 1,
  DATA   = 2,
  XSTATS = 3,
}, stringflag)

S.IFLA_VLAN = setmetatable({
  UNSPEC = 0,
  ID     = 1,
  FLAGS  = 2,
  EGRESS_QOS  = 3,
  INGRESS_QOS = 4,
}, stringflag)

S.IFLA_VLAN_QOS = setmetatable({
  UNSPEC  = 0,
  MAPPING = 1,
}, stringflag)

S.IFLA_MACVLAN = setmetatable({
  UNSPEC = 0,
  MODE   = 1,
}, stringflag)

S.MACVLAN_MODE_PRIVATE = 1
S.MACVLAN_MODE_VEPA    = 2
S.MACVLAN_MODE_BRIDGE  = 4
S.MACVLAN_MODE_PASSTHRU = 8

S.IFLA_VF_INFO_UNSPEC = 0
S.IFLA_VF_INFO        = 1 -- TODO may have to rename IFLA_VF_INFO_INFO?

S.IFLA_VF = setmetatable({
  UNSPEC   = 0,
  MAC      = 1,
  VLAN     = 2,
  TX_RATE  = 3,
  SPOOFCHK = 4,
}, stringflag)

S.IFLA_VF_PORT_UNSPEC = 0
S.IFLA_VF_PORT        = 1 -- TODO may have to rename IFLA_VF_PORT_PORT?

S.IFLA_PORT = setmetatable({
  UNSPEC    = 0,
  VF        = 1,
  PROFILE   = 2,
  VSI_TYPE  = 3,
  INSTANCE_UUID = 4,
  HOST_UUID = 5,
  REQUEST   = 6,
  RESPONSE  = 7,
}, stringflag)

S.VETH_INFO = setmetatable({
  UNSPEC = 0,
  PEER   = 1,
}, stringflag)

S.PORT_PROFILE_MAX      =  40
S.PORT_UUID_MAX         =  16
S.PORT_SELF_VF          =  -1

S.PORT_REQUEST_PREASSOCIATE    = 0
S.PORT_REQUEST_PREASSOCIATE_RR = 1
S.PORT_REQUEST_ASSOCIATE       = 2
S.PORT_REQUEST_DISASSOCIATE    = 3

S.PORT_VDP_RESPONSE_SUCCESS = 0
S.PORT_VDP_RESPONSE_INVALID_FORMAT = 1
S.PORT_VDP_RESPONSE_INSUFFICIENT_RESOURCES = 2
S.PORT_VDP_RESPONSE_UNUSED_VTID = 3
S.PORT_VDP_RESPONSE_VTID_VIOLATION = 4
S.PORT_VDP_RESPONSE_VTID_VERSION_VIOALTION = 5
S.PORT_VDP_RESPONSE_OUT_OF_SYNC = 6
S.PORT_PROFILE_RESPONSE_SUCCESS = 0x100
S.PORT_PROFILE_RESPONSE_INPROGRESS = 0x101
S.PORT_PROFILE_RESPONSE_INVALID = 0x102
S.PORT_PROFILE_RESPONSE_BADSTATE = 0x103
S.PORT_PROFILE_RESPONSE_INSUFFICIENT_RESOURCES = 0x104
S.PORT_PROFILE_RESPONSE_ERROR = 0x105

-- from if_addr.h interface address types and flags
S.IFA = setmetatable({
  UNSPEC    = 0,
  ADDRESS   = 1,
  LOCAL     = 2,
  LABEL     = 3,
  BROADCAST = 4,
  ANYCAST   = 5,
  CACHEINFO = 6,
  MULTICAST = 7,
}, stringflag)

S.IFA_F_SECONDARY   = 0x01
S.IFA_F_TEMPORARY   = S.IFA_F_SECONDARY

S.IFA_F_NODAD       = 0x02
S.IFA_F_OPTIMISTIC  = 0x04
S.IFA_F_DADFAILED   = 0x08
S.IFA_F_HOMEADDRESS = 0x10
S.IFA_F_DEPRECATED  = 0x20
S.IFA_F_TENTATIVE   = 0x40
S.IFA_F_PERMANENT   = 0x80

-- routing
S.RTN = setmetatable({
  UNSPEC      = 0,
  UNICAST     = 1,
  LOCAL       = 2,
  BROADCAST   = 3,
  ANYCAST     = 4,
  MULTICAST   = 5,
  BLACKHOLE   = 6,
  UNREACHABLE = 7,
  PROHIBIT    = 8,
  THROW       = 9,
  NAT         = 10,
  XRESOLVE    = 11,
}, stringflag)

S.RTPROT = setmetatable({
  UNSPEC   = 0,
  REDIRECT = 1,
  KERNEL   = 2,
  BOOT     = 3,
  STATIC   = 4,
  GATED    = 8,
  RA       = 9,
  MRT      = 10,
  ZEBRA    = 11,
  BIRD     = 12,
  DNROUTED = 13,
  XORP     = 14,
  NTK      = 15,
  DHCP     = 16,
}, stringflag)

S.RT_SCOPE = setmetatable({
  UNIVERSE = 0,
  SITE = 200,
  LINK = 253,
  HOST = 254,
  NOWHERE = 255,
}, stringflag)

S.RTM_F_NOTIFY          = 0x100
S.RTM_F_CLONED          = 0x200
S.RTM_F_EQUALIZE        = 0x400
S.RTM_F_PREFIX          = 0x800

S.RT_TABLE = setmetatable({
  UNSPEC  = 0,
  COMPAT  = 252,
  DEFAULT = 253,
  MAIN    = 254,
  LOCAL   = 255,
  MAX     = 0xFFFFFFFF,
}, stringflag)

S.RTA = setmetatable({
  UNSPEC = 0,
  DST = 1,
  SRC = 2,
  IIF = 3,
  OIF = 4,
  GATEWAY = 5,
  PRIORITY = 6,
  PREFSRC = 7,
  METRICS = 8,
  MULTIPATH = 9,
  PROTOINFO = 10,
  FLOW = 11,
  CACHEINFO = 12,
  SESSION = 13,
  MP_ALGO = 14,
  TABLE = 15,
  MARK = 16,
}, stringflag)

-- route flags
S.RTF_UP          = 0x0001
S.RTF_GATEWAY     = 0x0002
S.RTF_HOST        = 0x0004
S.RTF_REINSTATE   = 0x0008
S.RTF_DYNAMIC     = 0x0010
S.RTF_MODIFIED    = 0x0020
S.RTF_MTU         = 0x0040
S.RTF_MSS         = S.RTF_MTU
S.RTF_WINDOW      = 0x0080
S.RTF_IRTT        = 0x0100
S.RTF_REJECT      = 0x0200

-- ipv6 route flags
S.RTF_DEFAULT     = 0x00010000
S.RTF_ALLONLINK   = 0x00020000
S.RTF_ADDRCONF    = 0x00040000
S.RTF_PREFIX_RT   = 0x00080000
S.RTF_ANYCAST     = 0x00100000
S.RTF_NONEXTHOP   = 0x00200000
S.RTF_EXPIRES     = 0x00400000
S.RTF_ROUTEINFO   = 0x00800000
S.RTF_CACHE       = 0x01000000
S.RTF_FLOW        = 0x02000000
S.RTF_POLICY      = 0x04000000
--#define RTF_PREF(pref)  ((pref) << 27)
--#define RTF_PREF_MASK   0x18000000
S.RTF_LOCAL       = 0x80000000

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

S.IFF_ALL        = 0xffffffff
S.IFF_NONE       = bit.bnot(0x7ffff) -- this is a bit of a fudge as zero should work, but does not for historical reasons see net/core/rtnetlink.c

-- not sure if we need these
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

S.IFF_VOLATILE = S.IFF_LOOPBACK + S.IFF_POINTOPOINT + S.IFF_BROADCAST + S.IFF_ECHO +
                 S.IFF_MASTER + S.IFF_SLAVE + S.IFF_RUNNING + S.IFF_LOWER_UP + S.IFF_DORMANT

-- netlink multicast groups
-- legacy names, which are masks.
S.RTMGRP_LINK            = 1
S.RTMGRP_NOTIFY          = 2
S.RTMGRP_NEIGH           = 4
S.RTMGRP_TC              = 8
S.RTMGRP_IPV4_IFADDR     = 0x10
S.RTMGRP_IPV4_MROUTE     = 0x20
S.RTMGRP_IPV4_ROUTE      = 0x40
S.RTMGRP_IPV4_RULE       = 0x80
S.RTMGRP_IPV6_IFADDR     = 0x100
S.RTMGRP_IPV6_MROUTE     = 0x200
S.RTMGRP_IPV6_ROUTE      = 0x400
S.RTMGRP_IPV6_IFINFO     = 0x800
--S.RTMGRP_DECNET_IFADDR   = 0x1000
--S.RTMGRP_DECNET_ROUTE    = 0x4000
S.RTMGRP_IPV6_PREFIX     = 0x20000

-- rtnetlink multicast groups (bit numbers not masks)
S.RTNLGRP_NONE = 0
S.RTNLGRP_LINK = 1
S.RTNLGRP_NOTIFY = 2
S.RTNLGRP_NEIGH = 3
S.RTNLGRP_TC = 4
S.RTNLGRP_IPV4_IFADDR = 5
S.RTNLGRP_IPV4_MROUTE = 6
S.RTNLGRP_IPV4_ROUTE = 7
S.RTNLGRP_IPV4_RULE = 8
S.RTNLGRP_IPV6_IFADDR = 9
S.RTNLGRP_IPV6_MROUTE = 10
S.RTNLGRP_IPV6_ROUTE = 11
S.RTNLGRP_IPV6_IFINFO = 12
--S.RTNLGRP_DECNET_IFADDR = 13
S.RTNLGRP_NOP2 = 14
--S.RTNLGRP_DECNET_ROUTE = 15
--S.RTNLGRP_DECNET_RULE = 16
S.RTNLGRP_NOP4 = 17
S.RTNLGRP_IPV6_PREFIX = 18
S.RTNLGRP_IPV6_RULE = 19
S.RTNLGRP_ND_USEROPT = 20
S.RTNLGRP_PHONET_IFADDR = 21
S.RTNLGRP_PHONET_ROUTE = 22
S.RTNLGRP_DCB = 23

-- address families
S.AF = setmetatable({
  UNSPEC     = 0,
  LOCAL      = 1,
  INET       = 2,
  AX25       = 3,
  IPX        = 4,
  APPLETALK  = 5,
  NETROM     = 6,
  BRIDGE     = 7,
  ATMPVC     = 8,
  X25        = 9,
  INET6      = 10,
  ROSE       = 11,
  DECNET     = 12,
  NETBEUI    = 13,
  SECURITY   = 14,
  KEY        = 15,
  NETLINK    = 16,
  PACKET     = 17,
  ASH        = 18,
  ECONET     = 19,
  ATMSVC     = 20,
  RDS        = 21,
  SNA        = 22,
  IRDA       = 23,
  PPPOX      = 24,
  WANPIPE    = 25,
  LLC        = 26,
  CAN        = 29,
  TIPC       = 30,
  BLUETOOTH  = 31,
  IUCV       = 32,
  RXRPC      = 33,
  ISDN       = 34,
  PHONET     = 35,
  IEEE802154 = 36,
  CAIF       = 37,
  ALG        = 38,
  NFC        = 39,
}, stringflag)

S.AF.UNIX       = S.AF.LOCAL
S.AF.FILE       = S.AF.LOCAL
S.AF.ROUTE      = S.AF.NETLINK

-- arp types, which are also interface types for ifi_type
S.ARPHRD = setmetatable({
  NETROM   = 0,
  ETHER    = 1,
  EETHER   = 2,
  AX25     = 3,
  PRONET   = 4,
  CHAOS    = 5,
  IEEE802  = 6,
  ARCNET   = 7,
  APPLETLK = 8,
  DLCI     = 15,
  ATM      = 19,
  METRICOM = 23,
  IEEE1394 = 24,
  EUI64    = 27,
  INFINIBAND = 32,
  SLIP     = 256,
  CSLIP    = 257,
  SLIP6    = 258,
  CSLIP6   = 259,
  RSRVD    = 260,
  ADAPT    = 264,
  ROSE     = 270,
  X25      = 271,
  HWX25    = 272,
  CAN      = 280,
  PPP      = 512,
  CISCO    = 513,
  LAPB     = 516,
  DDCMP    = 517,
  RAWHDLC  = 518,
  TUNNEL   = 768,
  TUNNEL6  = 769,
  FRAD     = 770,
  SKIP     = 771,
  LOOPBACK = 772,
  LOCALTLK = 773,
  FDDI     = 774,
  BIF      = 775,
  SIT      = 776,
  IPDDP    = 777,
  IPGRE    = 778,
  PIMREG   = 779,
  HIPPI    = 780,
  ASH      = 781,
  ECONET   = 782,
  IRDA     = 783,
  FCPP     = 784,
  FCAL     = 785,
  FCPL     = 786,
  FCFABRIC = 787,
  IEEE802_TR = 800,
  IEEE80211 = 801,
  IEEE80211_PRISM = 802,
  IEEE80211_RADIOTAP = 803,
  IEEE802154         = 804,
  PHONET   = 820,
  PHONET_PIPE = 821,
  CAIF     = 822,
  VOID     = 0xFFFF,
  NONE     = 0xFFFE,
}, stringflag)

S.ARPHRD.HDLC     = S.ARPHRD.CISCO

-- IP
S.IPPROTO = setmetatable({
  IP = 0,
  HOPOPTS = 0, -- TODO overloaded namespace?
  ICMP = 1,
  IGMP = 2,
  IPIP = 4,
  TCP = 6,
  EGP = 8,
  PUP = 12,
  UDP = 17,
  IDP = 22,
  TP = 29,
  DCCP = 33,
  IPV6 = 41,
  ROUTING = 43,
  FRAGMENT = 44,
  RSVP = 46,
  GRE = 47,
  ESP = 50,
  AH = 51,
  ICMPV6 = 58,
  NONE = 59,
  DSTOPTS = 60,
  MTP = 92,
  ENCAP = 98,
  PIM = 103,
  COMP = 108,
  SCTP = 132,
  UDPLITE = 136,
  RAW = 255,
}, stringflag)

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

-- fake flags
S.MS_RO = S.MS_RDONLY -- allow use of "ro" as flag as that is what /proc/mounts uses
S.MS_RW = 0           -- allow use of "rw" as flag as appears in /proc/mounts

S.MNT_FORCE = 1
S.MNT_DETACH = 2
S.MNT_EXPIRE = 4
S.UMOUNT_NOFOLLOW = 8

-- flags to `msync'.
S.MS_ASYNC       = 1
S.MS_SYNC        = 4
S.MS_INVALIDATE  = 2

-- reboot
S.LINUX_REBOOT_CMD = setmetatable({
  RESTART      =  0x01234567,
  HALT         =  0xCDEF0123,
  CAD_ON       =  0x89ABCDEF,
  CAD_OFF      =  0x00000000,
  POWER_OFF    =  0x4321FEDC,
  RESTART2     =  0xA1B2C3D4,
  SW_SUSPEND   =  0xD000FCE2,
  KEXEC        =  0x45584543,
}, stringflag)

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

--prctl
S.PR = setmetatable({
  SET_PDEATHSIG = 1,
  GET_PDEATHSIG = 2,
  GET_DUMPABLE  = 3,
  SET_DUMPABLE  = 4,
  GET_UNALIGN   = 5,
  SET_UNALIGN   = 6,
  GET_KEEPCAPS  = 7,
  SET_KEEPCAPS  = 8,
  GET_FPEMU     = 9,
  SET_FPEMU     = 10,
  GET_FPEXC     = 11,
  SET_FPEXC     = 12,
  GET_TIMING    = 13,
  SET_TIMING    = 14,
  SET_NAME      = 15,
  GET_NAME      = 16,
  GET_ENDIAN    = 19,
  SET_ENDIAN    = 20,
  GET_SECCOMP   = 21,
  SET_SECCOMP   = 22,
  CAPBSET_READ  = 23,
  CAPBSET_DROP  = 24,
  GET_TSC       = 25,
  SET_TSC       = 26,
  GET_SECUREBITS= 27,
  SET_SECUREBITS= 28,
  SET_TIMERSLACK= 29,
  GET_TIMERSLACK= 30,
  TASK_PERF_EVENTS_DISABLE=31,
  TASK_PERF_EVENTS_ENABLE=32,
  MCE_KILL      = 33,
  MCE_KILL_GET  = 34,
  SET_PTRACER   = 0x59616d61, -- Ubuntu extension
}, stringflag)

-- for PR get/set unalign
S.PR_UNALIGN = setmetatable({
  NOPRINT   = 1,
  SIGBUS    = 2,
}, stringflag)

-- for PR fpemu
S.PR_FPEMU = setmetatable({
  NOPRINT     = 1,
  SIGFPE      = 2,
}, stringflag)

-- for PR fpexc
S.PR_FP_EXC = setmetatable({
  SW_ENABLE  = 0x80,
  DIV        = 0x010000,
  OVF        = 0x020000,
  UND        = 0x040000,
  RES        = 0x080000,
  INV        = 0x100000,
  DISABLED   = 0,
  NONRECOV   = 1,
  ASYNC      = 2,
  PRECISE    = 3,
}, stringflag) -- TODO should be a combo of stringflag and flags

-- PR get set timing
S.PR_TIMING = setmetatable({
  STATISTICAL= 0,
  TIMESTAMP  = 1,
}, stringflag)

-- PR set endian
S.PR_ENDIAN = setmetatable({
  BIG         = 0,
  LITTLE      = 1,
  PPC_LITTLE  = 2,
}, stringflag)

-- PR TSC
S.PR_TSC = setmetatable({
  ENABLE         = 1,
  SIGSEGV        = 2,
}, stringflag)

S.PR_MCE_KILL = setmetatable({
  CLEAR     = 0,
  SET       = 1,
}, stringflag)

-- note rename, this is extra option see prctl code
S.PR_MCE_KILL_OPT = setmetatable({
  LATE         = 0,
  EARLY        = 1,
  DEFAULT      = 2,
}, stringflag)

-- capabilities
S.CAP = setmetatable({
  CHOWN = 0,
  DAC_OVERRIDE = 1,
  DAC_READ_SEARCH = 2,
  FOWNER = 3,
  FSETID = 4,
  KILL = 5,
  SETGID = 6,
  SETUID = 7,
  SETPCAP = 8,
  LINUX_IMMUTABLE = 9,
  NET_BIND_SERVICE = 10,
  NET_BROADCAST = 11,
  NET_ADMIN = 12,
  NET_RAW = 13,
  IPC_LOCK = 14,
  IPC_OWNER = 15,
  SYS_MODULE = 16,
  SYS_RAWIO = 17,
  SYS_CHROOT = 18,
  SYS_PTRACE = 19,
  SYS_PACCT = 20,
  SYS_ADMIN = 21,
  SYS_BOOT = 22,
  SYS_NICE = 23,
  SYS_RESOURCE = 24,
  SYS_TIME = 25,
  SYS_TTY_CONFIG = 26,
  MKNOD = 27,
  LEASE = 28,
  AUDIT_WRITE = 29,
  AUDIT_CONTROL = 30,
  SETFCAP = 31,
  MAC_OVERRIDE = 32,
  MAC_ADMIN = 33,
  SYSLOG = 34,
  WAKE_ALARM = 35,
}, stringflag)

-- new SECCOMP modes, now there is filter as well as strict
S.SECCOMP_MODE = setmetatable({
  DISABLED = 0,
  STRICT   = 1,
  FILTER   = 2,
}, stringflag)

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

-- TODO rework this with functions in a metatable
local bits_speed_map = { }
local speed_bits_map = { }
local function defspeed(speed, bits)
  bits = octal(bits)
  bits_speed_map[bits] = speed
  speed_bits_map[speed] = bits
  S['B'..speed] = bits
end
function S.bits_to_speed(bits)
  local speed = bits_speed_map[bits]
  if not speed then error("unknown speedbits: " .. bits) end
  return speed
end
function S.speed_to_bits(speed)
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

-- termios - tcflow() and TCXONC use these. renamed from TC to TCFLOW
S.TCFLOW = setmetatable({
  OOFF = 0,
  OON  = 1,
  IOFF = 2,
  ION  = 3,
}, stringflag)

-- termios - tcflush() and TCFLSH use these. renamed from TC to TCFLUSH
S.TCFLUSH = setmetatable({
  IFLUSH  = 0,
  OFLUSH  = 1,
  IOFLUSH = 2,
}, stringflag)

-- termios - tcsetattr uses these
S.TCSA = setmetatable({
  NOW   = 0,
  DRAIN = 1,
  FLUSH = 2,
}, stringflag)

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
S.TIOCGPTN	 = 0x80045430LL
S.TIOCSPTLCK	 = 0x40045431LL

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

-- errors
S.E = {
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
}

-- alternate names
S.E.EWOULDBLOCK    = S.E.EAGAIN
S.E.EDEADLOCK      = S.E.EDEADLK
S.E.ENOATTR        = S.E.ENODATA

return S

