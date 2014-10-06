-- tables of constants

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local abi = require "syscall.abi"

local bit = require "syscall.bit"

local tobit = bit.tobit

local arch = require("syscall.linux." .. abi.arch .. ".constants") -- architecture specific code

local h = require "syscall.helpers"

local octal, multiflags, charflags, swapflags, strflag, atflag, modeflags
  = h.octal, h.multiflags, h.charflags, h.swapflags, h.strflag, h.atflag, h.modeflags

local function addarch(tb, a, default)
  local add = a or default
  for k, v in pairs(add) do tb[k] = v end
end

local c = {}

c.errornames = require "syscall.linux.errors"

c.REG = arch.REG

-- TODO only define one of these
c.STD = strflag {
  IN_FILENO = 0,
  OUT_FILENO = 1,
  ERR_FILENO = 2,
  IN = 0,
  OUT = 1,
  ERR = 2,
}

-- sizes
c.PATH_MAX = 4096

-- open, fcntl TODO not setting largefile if matches exactly in upper case, potentially confusing
c.O = multiflags(arch.O or {
  RDONLY    = octal('0000'),
  WRONLY    = octal('0001'),
  RDWR      = octal('0002'),
  ACCMODE   = octal('0003'),
  CREAT     = octal('0100'),
  EXCL      = octal('0200'),
  NOCTTY    = octal('0400'),
  TRUNC     = octal('01000'),
  APPEND    = octal('02000'),
  NONBLOCK  = octal('04000'),
  DSYNC     = octal('010000'),
  ASYNC     = octal('020000'),
  DIRECT    = octal('040000'),
  DIRECTORY = octal('0200000'),
  NOFOLLOW  = octal('0400000'),
  NOATIME   = octal('01000000'),
  CLOEXEC   = octal('02000000'),
  SYNC      = octal('04010000'),
})

c.O.FSYNC     = c.O.SYNC
c.O.RSYNC     = c.O.SYNC
c.O.NDELAY    = c.O.NONBLOCK

if not c.O.LARGEFILE then -- also can be arch dependent
  if abi.abi32 then c.O.LARGEFILE = octal('0100000') else c.O.LARGEFILE = 0 end
end

-- just for pipe2
c.OPIPE = multiflags {
  NONBLOCK  = c.O.NONBLOCK,
  CLOEXEC   = c.O.CLOEXEC,
  DIRECT    = c.O.DIRECT,
}

-- for mq_attr NONBLOCK only flag allowed
c.OMQATTR = multiflags {
  NONBLOCK = c.O.NONBLOCK,
}

-- modes and file types. note renamed second set from S_ to MODE_ but duplicated in S for stat
c.S_I = modeflags {
  FMT   = octal('0170000'),
  FSOCK = octal('0140000'),
  FLNK  = octal('0120000'),
  FREG  = octal('0100000'),
  FBLK  = octal('0060000'),
  FDIR  = octal('0040000'),
  FCHR  = octal('0020000'),
  FIFO  = octal('0010000'),
  SUID  = octal('0004000'),
  SGID  = octal('0002000'),
  SVTX  = octal('0001000'),
  RWXU  = octal('00700'),
  RUSR  = octal('00400'),
  WUSR  = octal('00200'),
  XUSR  = octal('00100'),
  RWXG  = octal('00070'),
  RGRP  = octal('00040'),
  WGRP  = octal('00020'),
  XGRP  = octal('00010'),
  RWXO  = octal('00007'),
  ROTH  = octal('00004'),
  WOTH  = octal('00002'),
  XOTH  = octal('00001'),
}

c.MODE = modeflags {
  SUID = octal('04000'),
  SGID = octal('02000'),
  SVTX = octal('01000'),
  RWXU = octal('00700'),
  RUSR = octal('00400'),
  WUSR = octal('00200'),
  XUSR = octal('00100'),
  RWXG = octal('00070'),
  RGRP = octal('00040'),
  WGRP = octal('00020'),
  XGRP = octal('00010'),
  RWXO = octal('00007'),
  ROTH = octal('00004'),
  WOTH = octal('00002'),
  XOTH = octal('00001'),
}

-- access
c.OK = charflags {
  R = 4,
  W = 2,
  X = 1,
  F = 0,
}

-- fcntl
c.F = strflag(arch.F or {
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
})

-- messy
if abi.abi64 then
  c.F.GETLK64   = c.F.GETLK
  c.F.SETLK64   = c.F.SETLK
  c.F.SETLKW64  = c.F.SETLKW
else
  c.F.GETLK     = c.F.GETLK64
  c.F.SETLK     = c.F.SETLK64
  c.F.SETLKW    = c.F.SETLKW64
end

c.FD = multiflags {
  CLOEXEC = 1,
}

-- note changed from F_ to FCNTL_LOCK
c.FCNTL_LOCK = strflag {
  RDLCK = 0,
  WRLCK = 1,
  UNLCK = 2,
}

-- lockf, changed from F_ to LOCKF_
c.LOCKF = strflag {
  ULOCK = 0,
  LOCK  = 1,
  TLOCK = 2,
  TEST  = 3,
}

-- for flock (2)
c.LOCK = multiflags {
  SH        = 1,
  EX        = 2,
  NB        = 4,
  UN        = 8,
  MAND      = 32,
  READ      = 64,
  WRITE     = 128,
  RW        = 192,
}

--mmap
c.PROT = multiflags {
  NONE  = 0x0,
  READ  = 0x1,
  WRITE = 0x2,
  EXEC  = 0x4,
  GROWSDOWN = 0x01000000,
  GROWSUP   = 0x02000000,
}

addarch(c.PROT, arch.PROT, {})

-- Sharing types
c.MAP = multiflags(arch.MAP or {
  FILE       = 0,
  SHARED     = 0x01,
  PRIVATE    = 0x02,
  TYPE       = 0x0f,
  FIXED      = 0x10,
  ANONYMOUS  = 0x20,
  GROWSDOWN  = 0x00100,
  DENYWRITE  = 0x00800,
  EXECUTABLE = 0x01000,
  LOCKED     = 0x02000,
  NORESERVE  = 0x04000,
  POPULATE   = 0x08000,
  NONBLOCK   = 0x10000,
  STACK      = 0x20000,
  HUGETLB    = 0x40000,
})

if abi.abi64 then c.MAP["32BIT"] = 0x40 end

c.MAP.ANON       = c.MAP.ANONYMOUS

-- flags for `mlockall'.
c.MCL = strflag (arch.MCL or {
  CURRENT    = 1,
  FUTURE     = 2,
})

-- flags for `mremap'.
c.MREMAP = multiflags {
  MAYMOVE = 1,
  FIXED   = 2,
}

-- madvise advice parameter
c.MADV = strflag {
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
}

-- posix fadvise
c.POSIX_FADV = strflag {
  NORMAL       = 0,
  RANDOM       = 1,
  SEQUENTIAL   = 2,
  WILLNEED     = 3,
  DONTNEED     = 4,
  NOREUSE      = 5,
}

-- fallocate
c.FALLOC_FL = strflag {
  KEEP_SIZE  = 0x01,
  PUNCH_HOLE = 0x02,
}

-- getpriority, setpriority flags
c.PRIO = strflag {
  PROCESS = 0,
  PGRP = 1,
  USER = 2,
}

-- lseek
c.SEEK = strflag {
  SET = 0,
  CUR = 1,
  END = 2,
}

-- exit
c.EXIT = strflag {
  SUCCESS = 0,
  FAILURE = 1,
}

-- sigaction, note renamed SIGACT from SIG_
c.SIGACT = strflag {
  ERR = -1,
  DFL =  0,
  IGN =  1,
  HOLD = 2,
}

c.SIGEV = strflag {
  SIGNAL    = 0,
  NONE      = 1,
  THREAD    = 2,
  THREAD_ID = 4,
}

c.SIG = strflag(arch.SIG or {
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
})

c.SIG.IOT = c.SIG.ABRT
--c.SIG.UNUSED     = 31 -- TODO this looks arch dependent
c.SIG.CLD        = c.SIG.CHLD
c.SIG.POLL       = c.SIG.IO

-- sigprocmask note renaming of SIG to SIGPM
c.SIGPM = strflag(arch.SIGPM or {
  BLOCK     = 0,
  UNBLOCK   = 1,
  SETMASK   = 2,
})

-- signalfd
c.SFD = multiflags(arch.SFD or {
  CLOEXEC  = octal('02000000'),
  NONBLOCK = octal('04000'),
})

-- sockets note mix of single and multiple flags TODO code to handle temporarily using multi which is kind of ok
c.SOCK = multiflags(arch.SOCK or {
  STREAM    = 1,
  DGRAM     = 2,
  RAW       = 3,
  RDM       = 4,
  SEQPACKET = 5,
  DCCP      = 6,
  PACKET    = 10,

  CLOEXEC  = octal('02000000'),
  NONBLOCK = octal('04000'),
})

-- misc socket constants
c.SCM = strflag {
  RIGHTS = 0x01,
  CREDENTIALS = 0x02,
}

-- setsockopt
c.SOL = strflag {
  IP         = 0,
  IPV6       = 41,
  ICMPV6     = 58,
  RAW        = 255,
  DECNET     = 261,
  X25        = 262,
  PACKET     = 263,
  ATM        = 264,
  AAL        = 265,
  IRDA       = 266,
}

if arch.SOLSOCKET then c.SOL.SOCKET = arch.SOLSOCKET else c.SOL.SOCKET = 1 end

c.SO = strflag(arch.SO or {
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
--REUSEPORT   = 15, -- new, may not be defined yet
  PASSCRED    = 16,
  PEERCRED    = 17,
  RCVLOWAT    = 18,
  SNDLOWAT    = 19,
  RCVTIMEO    = 20,
  SNDTIMEO    = 21,
  SECURITY_AUTHENTICATION = 22,
  SECURITY_ENCRYPTION_TRANSPORT = 23,
  SECURITY_ENCRYPTION_NETWORK = 24,
  BINDTODEVICE       = 25,
  ATTACH_FILTER      = 26,
  DETACH_FILTER      = 27,
  PEERNAME           = 28,
  TIMESTAMP          = 29,
  ACCEPTCONN         = 30,
  PEERSEC            = 31,
  SNDBUFFORCE        = 32,
  RCVBUFFORCE        = 33,
  PASSSEC            = 34,
  TIMESTAMPNS        = 35,
  MARK               = 36,
  TIMESTAMPING       = 37,
  PROTOCOL           = 38,
  DOMAIN             = 39,
  RXQ_OVFL           = 40,
  WIFI_STATUS        = 41,
  PEEK_OFF           = 42,
  NOFCS              = 43,
})

c.SO.GET_FILTER = c.SO.ATTACH_FILTER

-- Maximum queue length specifiable by listen.
c.SOMAXCONN = 128

-- shutdown
c.SHUT = strflag {
  RD   = 0,
  WR   = 1,
  RDWR = 2,
}

-- waitpid 3rd arg
c.W = multiflags {
  NOHANG       = 1,
  UNTRACED     = 2,
  EXITED       = 4,
  CONTINUED    = 8,
  NOWAIT       = 0x01000000,
  NOTHREAD     = 0x20000000, -- __WNOTHREAD
  ALL          = 0x40000000, -- __WALL
  CLONE        = 0x80000000, -- __WCLONE
}

c.W.STOPPED      = c.W.UNTRACED

-- waitid
c.P = strflag{
  ALL  = 0,
  PID  = 1,
  PGID = 2,
}

-- struct siginfo, eg waitid
c.SI = strflag(arch.SI or {
  ASYNCNL = -60,
  TKILL = -6,
  SIGIO = -5,
  ASYNCIO = -4,
  MESGQ = -3,
  TIMER = -2,
  QUEUE = -1,
  USER = 0,
  KERNEL = 0x80,
})

-- note renamed ILL to SIGILL etc as POLL clashes

c.SIGILL = strflag {
  ILLOPC = 1,
  ILLOPN = 2,
  ILLADR = 3,
  ILLTRP = 4,
  PRVOPC = 5,
  PRVREG = 6,
  COPROC = 7,
  BADSTK = 8,
}

c.SIGFPE = strflag {
  INTDIV = 1,
  INTOVF = 2,
  FLTDIV = 3,
  FLTOVF = 4,
  FLTUND = 5,
  FLTRES = 6,
  FLTINV = 7,
  FLTSUB = 8,
}

c.SIGSEGV = strflag {
  MAPERR = 1,
  ACCERR = 2,
}

c.SIGBUS = strflag {
  ADRALN = 1,
  ADRERR = 2,
  OBJERR = 3,
}

c.SIGTRAP = strflag {
  BRKPT = 1,
  TRACE = 2,
}

c.SIGCLD = strflag {
  EXITED    = 1,
  KILLED    = 2,
  DUMPED    = 3,
  TRAPPED   = 4,
  STOPPED   = 5,
  CONTINUED = 6,
}

c.SIGPOLL = strflag {
  IN  = 1,
  OUT = 2,
  MSG = 3,
  ERR = 4,
  PRI = 5,
  HUP = 6,
}

-- sigaction -- note not cast to (void *)(int) as we do not know type here
c.SA = multiflags(arch.SA or {
  NOCLDSTOP = 0x00000001,
  NOCLDWAIT = 0x00000002,
  SIGINFO   = 0x00000004,
  ONSTACK   = 0x08000000,
  RESTART   = 0x10000000,
  NODEFER   = 0x40000000,
  RESETHAND = 0x80000000,
  RESTORER  = 0x04000000,
})

c.SA.NOMASK    = c.SA.NODEFER
c.SA.ONESHOT   = c.SA.RESETHAND

-- timers
c.ITIMER = strflag {
  REAL    = 0,
  VIRTUAL = 1,
  PROF    = 2,
}

-- clocks
c.CLOCK = strflag {
  REALTIME           = 0,
  MONOTONIC          = 1,
  PROCESS_CPUTIME_ID = 2,
  THREAD_CPUTIME_ID  = 3,
  MONOTONIC_RAW      = 4,
  REALTIME_COARSE    = 5,
  MONOTONIC_COARSE   = 6,
}

c.TIMER = strflag {
  ABSTIME = 1,
}

-- adjtimex
c.ADJ = multiflags {
  OFFSET             = 0x0001,
  FREQUENCY          = 0x0002,
  MAXERROR           = 0x0004,
  ESTERROR           = 0x0008,
  STATUS             = 0x0010,
  TIMECONST          = 0x0020,
  TAI                = 0x0080,
  MICRO              = 0x1000,
  NANO               = 0x2000,
  TICK               = 0x4000,
  OFFSET_SINGLESHOT  = 0x8001,
  OFFSET_SS_READ     = 0xa001,
}

c.STA = multiflags {
  PLL         = 0x0001,
  PPSFREQ     = 0x0002,
  PPSTIME     = 0x0004,
  FLL         = 0x0008,
  INS         = 0x0010,
  DEL         = 0x0020,
  UNSYNC      = 0x0040,
  FREQHOLD    = 0x0080,
  PPSSIGNAL   = 0x0100,
  PPSJITTER   = 0x0200,
  PPSWANDER   = 0x0400,
  PPSERROR    = 0x0800,
  CLOCKERR    = 0x1000,
  NANO        = 0x2000,
  MODE        = 0x4000,
  CLK         = 0x8000,
}

-- return values for adjtimex
c.TIME = strflag {
  OK         = 0,
  INS        = 1,
  DEL        = 2,
  OOP        = 3,
  WAIT       = 4,
  ERROR      = 5,
}

c.TIME.BAD        = c.TIME.ERROR

-- xattr; defined as multi as 0 is default, even though both flags makes no sense
c.XATTR = multiflags {
  CREATE  = 1,
  REPLACE = 2,
}

-- utime
c.UTIME = strflag {
  NOW  = bit.lshift(1, 30) - 1,
  OMIT = bit.lshift(1, 30) - 2,
}

c.AT_FDCWD = atflag {
  FDCWD = -100,
}

-- not all combinations valid
c.AT = multiflags {
  SYMLINK_NOFOLLOW = 0x100,
  REMOVEDIR        = 0x200,
  EACCESS          = 0x200,
  SYMLINK_FOLLOW   = 0x400,
  NO_AUTOMOUNT     = 0x800,
  EMPTY_PATH       = 0x1000,
}

-- send, recv etc
c.MSG = multiflags {
  OOB             = 0x01,
  PEEK            = 0x02,
  DONTROUTE       = 0x04,
  CTRUNC          = 0x08,
  PROXY           = 0x10,
  TRUNC           = 0x20,
  DONTWAIT        = 0x40,
  EOR             = 0x80,
  WAITALL         = 0x100,
  FIN             = 0x200,
  SYN             = 0x400,
  CONFIRM         = 0x800,
  RST             = 0x1000,
  ERRQUEUE        = 0x2000,
  NOSIGNAL        = 0x4000,
  MORE            = 0x8000,
  WAITFORONE      = 0x10000,
  CMSG_CLOEXEC    = 0x40000000,
}

c.MSG.TRYHARD         = c.MSG.DONTROUTE

-- rlimit
c.RLIMIT = strflag(arch.RLIMIT or {
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
})

c.RLIMIT.OFILE = c.RLIMIT.NOFILE

c.RLIM = strflag {
  INFINITY = h.uint64_max,
}

-- timerfd
c.TFD = multiflags(arch.TFD or {
  CLOEXEC  = octal("02000000"),
  NONBLOCK = octal("04000"),
})

c.TFD_TIMER = strflag {
  ABSTIME = 1,
}

-- poll
c.POLL = multiflags(arch.POLL or {
  IN          = 0x001,
  PRI         = 0x002,
  OUT         = 0x004,
  ERR         = 0x008,
  HUP         = 0x010,
  NVAL        = 0x020,
  RDNORM      = 0x040,
  RDBAND      = 0x080,
  WRNORM      = 0x100,
  WRBAND      = 0x200,
  MSG         = 0x400,
  REMOVE      = 0x1000,
  RDHUP       = 0x2000,
})

-- epoll renamed from EPOLL_ to EPOLLCREATE
c.EPOLLCREATE = multiflags {
  CLOEXEC = octal("02000000"),
  NONBLOCK = octal("04000"),
}

c.EPOLL = multiflags {
  IN  = 0x001,
  PRI = 0x002,
  OUT = 0x004,
  RDNORM = 0x040,
  RDBAND = 0x080,
  WRNORM = 0x100,
  WRBAND = 0x200,
  MSG = 0x400,
  ERR = 0x008,
  HUP = 0x010,
  RDHUP = 0x2000,
  ONESHOT = bit.lshift(1, 30),
  ET = bit.lshift(1, 30) * 2, -- 2^31 but making sure no sign issue
}

c.EPOLL_CTL = strflag {
  ADD = 1,
  DEL = 2,
  MOD = 3,
}

-- splice etc
c.SPLICE_F = multiflags {
  MOVE         = 1,
  NONBLOCK     = 2,
  MORE         = 4,
  GIFT         = 8,
}

-- aio - see /usr/include/linux/aio_abi.h
c.IOCB_CMD = strflag {
  PREAD   = 0,
  PWRITE  = 1,
  FSYNC   = 2,
  FDSYNC  = 3,
-- PREADX = 4,
-- POLL   = 5,
  NOOP    = 6,
  PREADV  = 7,
  PWRITEV = 8,
}

c.IOCB_FLAG = strflag {
  RESFD = 1,
}

-- file types in directory
c.DT = strflag {
  UNKNOWN = 0,
  FIFO = 1,
  CHR = 2,
  DIR = 4,
  BLK = 6,
  REG = 8,
  LNK = 10,
  SOCK = 12,
  WHT = 14,
}

-- sync file range
c.SYNC_FILE_RANGE = multiflags {
  WAIT_BEFORE = 1,
  WRITE       = 2,
  WAIT_AFTER  = 4,
}

-- netlink
c.NETLINK = strflag {
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
}

-- see man netlink(7) for details. Note us of flags by context
c.NLM_F = multiflags {
  REQUEST = 1,
  MULTI   = 2,
  ACK     = 4,
  ECHO    = 8,
-- for GET
  ROOT    = 0x100,
  MATCH   = 0x200,
  ATOMIC  = 0x400,
-- for NEW
  REPLACE = 0x100,
  EXCL    = 0x200,
  CREATE  = 0x400,
  APPEND  = 0x800,
}

c.NLM_F.DUMP = bit.bor(c.NLM_F.ROOT, c.NLM_F.MATCH)

-- generic types. These are part of same sequence as RTM
c.NLMSG = strflag{
  NOOP     = 0x1,
  ERROR    = 0x2,
  DONE     = 0x3,
  OVERRUN  = 0x4,
}

-- routing
c.RTM = strflag {
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
}

-- linux/if_linc.h
c.IFLA = strflag {
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
}

c.IFLA_INET = strflag {
  UNSPEC = 0,
  CONF   = 1,
}

c.IFLA_INET6 = strflag {
  UNSPEC = 0,
  FLAGS  = 1,
  CONF   = 2,
  STATS  = 3,
  MCAST  = 4,
  CACHEINFO  = 5,
  ICMP6STATS = 6,
}

c.IFLA_INFO = strflag {
  UNSPEC = 0,
  KIND   = 1,
  DATA   = 2,
  XSTATS = 3,
}

c.IFLA_VLAN = strflag {
  UNSPEC = 0,
  ID     = 1,
  FLAGS  = 2,
  EGRESS_QOS  = 3,
  INGRESS_QOS = 4,
}

c.IFLA_VLAN_QOS = strflag {
  UNSPEC  = 0,
  MAPPING = 1,
}

c.IFLA_MACVLAN = strflag {
  UNSPEC = 0,
  MODE   = 1,
}

c.MACVLAN_MODE = multiflags {
  PRIVATE = 1,
  VEPA    = 2,
  BRIDGE  = 4,
  PASSTHRU = 8,
}

c.IFLA_VF_INFO = strflag {
  UNSPEC = 0,
  INFO   = 1, -- note renamed IFLA_VF_INFO to IFLA_VF_INFO.INFO
}

c.IFLA_VF = strflag {
  UNSPEC   = 0,
  MAC      = 1,
  VLAN     = 2,
  TX_RATE  = 3,
  SPOOFCHK = 4,
}

c.IFLA_VF_PORT = strflag {
  UNSPEC = 0,
  PORT   = 1, -- note renamed from IFLA_VF_PORT to IFLA_VF_PORT.PORT?
}

c.IFLA_PORT = strflag {
  UNSPEC    = 0,
  VF        = 1,
  PROFILE   = 2,
  VSI_TYPE  = 3,
  INSTANCE_UUID = 4,
  HOST_UUID = 5,
  REQUEST   = 6,
  RESPONSE  = 7,
}

c.VETH_INFO = strflag {
  UNSPEC = 0,
  PEER   = 1,
}

c.PORT = strflag {
  PROFILE_MAX      =  40,
  UUID_MAX         =  16,
  SELF_VF          =  -1,
}

c.PORT_REQUEST = strflag {
  PREASSOCIATE    = 0,
  PREASSOCIATE_RR = 1,
  ASSOCIATE       = 2,
  DISASSOCIATE    = 3,
}

c.PORT_VDP_RESPONSE = strflag {
  SUCCESS = 0,
  INVALID_FORMAT = 1,
  INSUFFICIENT_RESOURCES = 2,
  UNUSED_VTID = 3,
  VTID_VIOLATION = 4,
  VTID_VERSION_VIOALTION = 5, -- seems to be misspelled in headers TODO fix
  OUT_OF_SYNC = 6,
}

c.PORT_PROFILE_RESPONSE = strflag {
  SUCCESS = 0x100,
  INPROGRESS = 0x101,
  INVALID = 0x102,
  BADSTATE = 0x103,
  INSUFFICIENT_RESOURCES = 0x104,
  ERROR = 0x105,
}

-- from if_addr.h interface address types and flags
c.IFA = strflag {
  UNSPEC    = 0,
  ADDRESS   = 1,
  LOCAL     = 2,
  LABEL     = 3,
  BROADCAST = 4,
  ANYCAST   = 5,
  CACHEINFO = 6,
  MULTICAST = 7,
}

c.IFA_F = multiflags {
  SECONDARY   = 0x01,
  NODAD       = 0x02,
  OPTIMISTIC  = 0x04,
  DADFAILED   = 0x08,
  HOMEADDRESS = 0x10,
  DEPRECATED  = 0x20,
  TENTATIVE   = 0x40,
  PERMANENT   = 0x80,
}

c.IFA_F.TEMPORARY   = c.IFA_F.SECONDARY

-- routing
c.RTN = strflag {
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
}

c.RTPROT = strflag {
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
}

c.RT_SCOPE = strflag {
  UNIVERSE = 0,
  SITE = 200,
  LINK = 253,
  HOST = 254,
  NOWHERE = 255,
}

c.RTM_F = multiflags {
  NOTIFY          = 0x100,
  CLONED          = 0x200,
  EQUALIZE        = 0x400,
  PREFIX          = 0x800,
}

c.RT_TABLE = strflag {
  UNSPEC  = 0,
  COMPAT  = 252,
  DEFAULT = 253,
  MAIN    = 254,
  LOCAL   = 255,
  MAX     = 0xFFFFFFFF,
}

c.RTA = strflag {
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
}

-- route flags
c.RTF = multiflags {
  UP          = 0x0001,
  GATEWAY     = 0x0002,
  HOST        = 0x0004,
  REINSTATE   = 0x0008,
  DYNAMIC     = 0x0010,
  MODIFIED    = 0x0020,
  MTU         = 0x0040,
  WINDOW      = 0x0080,
  IRTT        = 0x0100,
  REJECT      = 0x0200,
-- ipv6 route flags
  DEFAULT     = 0x00010000,
  ALLONLINK   = 0x00020000,
  ADDRCONF    = 0x00040000,
  PREFIX_RT   = 0x00080000,
  ANYCAST     = 0x00100000,
  NONEXTHOP   = 0x00200000,
  EXPIRES     = 0x00400000,
  ROUTEINFO   = 0x00800000,
  CACHE       = 0x01000000,
  FLOW        = 0x02000000,
  POLICY      = 0x04000000,
  LOCAL       = 0x80000000,
}

c.RTF.MSS         = c.RTF.MTU

--#define RTF_PREF(pref)  ((pref) << 27)
--#define RTF_PREF_MASK   0x18000000

-- interface flags
c.IFF = multiflags {
  UP         = 0x1,
  BROADCAST  = 0x2,
  DEBUG      = 0x4,
  LOOPBACK   = 0x8,
  POINTOPOINT= 0x10,
  NOTRAILERS = 0x20,
  RUNNING    = 0x40,
  NOARP      = 0x80,
  PROMISC    = 0x100,
  ALLMULTI   = 0x200,
  MASTER     = 0x400,
  SLAVE      = 0x800,
  MULTICAST  = 0x1000,
  PORTSEL    = 0x2000,
  AUTOMEDIA  = 0x4000,
  DYNAMIC    = 0x8000,
  LOWER_UP   = 0x10000,
  DORMANT    = 0x20000,
  ECHO       = 0x40000,
}

c.IFF.ALL        = 0xffffffff
c.IFF.NONE       = bit.bnot(0x7ffff) -- this is a bit of a fudge as zero should work, but does not for historical reasons see net/core/rtnetlinc.c

c.IFF.VOLATILE = c.IFF.LOOPBACK + c.IFF.POINTOPOINT + c.IFF.BROADCAST + c.IFF.ECHO +
                 c.IFF.MASTER + c.IFF.SLAVE + c.IFF.RUNNING + c.IFF.LOWER_UP + c.IFF.DORMANT

-- netlink multicast groups
-- legacy names, which are masks.
c.RTMGRP = multiflags {
  LINK            = 1,
  NOTIFY          = 2,
  NEIGH           = 4,
  TC              = 8,
  IPV4_IFADDR     = 0x10,
  IPV4_MROUTE     = 0x20,
  IPV4_ROUTE      = 0x40,
  IPV4_RULE       = 0x80,
  IPV6_IFADDR     = 0x100,
  IPV6_MROUTE     = 0x200,
  IPV6_ROUTE      = 0x400,
  IPV6_IFINFO     = 0x800,
--DECNET_IFADDR   = 0x1000,
--DECNET_ROUTE    = 0x4000,
  IPV6_PREFIX     = 0x20000,
}

-- rtnetlink multicast groups (bit numbers not masks)
c.RTNLGRP = strflag {
  NONE = 0,
  LINK = 1,
  NOTIFY = 2,
  NEIGH = 3,
  TC = 4,
  IPV4_IFADDR = 5,
  IPV4_MROUTE = 6,
  IPV4_ROUTE = 7,
  IPV4_RULE = 8,
  IPV6_IFADDR = 9,
  IPV6_MROUTE = 10,
  IPV6_ROUTE = 11,
  IPV6_IFINFO = 12,
-- DECNET_IFADDR = 13,
  NOP2 = 14,
-- DECNET_ROUTE = 15,
-- DECNET_RULE = 16,
  NOP4 = 17,
  IPV6_PREFIX = 18,
  IPV6_RULE = 19,
  ND_USEROPT = 20,
  PHONET_IFADDR = 21,
  PHONET_ROUTE = 22,
  DCB = 23,
}

-- netlink neighbours (arp)
c.NDA = strflag {
  UNSPEC = 0,
  DST = 1,
  LLADDR = 2,
  CACHEINFO = 3,
  PROBES = 4,
}

c.NTF = multiflags {
  USE        = 0x01,
  PROXY      = 0x08,
  ROUTER     = 0x80,
  SELF       = 0x02,
  MASTER     = 0x04,
}

c.NUD = multiflags {
  INCOMPLETE = 0x01,
  REACHABLE  = 0x02,
  STALE      = 0x04,
  DELAY      = 0x08,
  PROBE      = 0x10,
  FAILED     = 0x20,
  NOARP      = 0x40,
  PERMANENT  = 0x80,
  NONE       = 0x00,
}

c.NDTPA = strflag {
  UNSPEC = 0,
  IFINDEX = 1,
  REFCNT = 2,
  REACHABLE_TIME = 3,
  BASE_REACHABLE_TIME = 4,
  RETRANS_TIME = 5,
  GC_STALETIME = 6,
  DELAY_PROBE_TIME = 7,
  QUEUE_LEN = 8,
  APP_PROBES = 9,
  UCAST_PROBES = 10,
  MCAST_PROBES = 11,
  ANYCAST_DELAY = 12,
  PROXY_DELAY = 13,
  PROXY_QLEN = 14,
  LOCKTIME = 15,
  QUEUE_LENBYTES = 16,
}

c.NDTA = strflag {
  UNSPEC = 0,
  NAME = 1,
  THRESH1 = 2,
  THRESH2 = 3,
  THRESH3 = 4,
  CONFIG = 5,
  PARMS = 6,
  STATS = 7,
  GC_INTERVAL = 8,
}

-- address families
c.AF = strflag {
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
}

c.AF.UNIX       = c.AF.LOCAL
c.AF.FILE       = c.AF.LOCAL
c.AF.ROUTE      = c.AF.NETLINK

-- arp types, which are also interface types for ifi_type
c.ARPHRD = strflag {
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
}

c.ARPHRD.HDLC     = c.ARPHRD.CISCO

-- IP
c.IPPROTO = strflag {
  IP = 0,
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
}

c.IP = strflag {
  TOS          = 1,
  TTL          = 2,
  HDRINCL      = 3,
  OPTIONS      = 4,
  ROUTER_ALERT = 5,
  RECVOPTS     = 6,
  RETOPTS      = 7,
  PKTINFO      = 8,
  PKTOPTIONS   = 9,
  MTU_DISCOVER = 10,
  RECVERR      = 11,
  RECVTTL      = 12,
  RECVTOS      = 13,
  MTU          = 14,
  FREEBIND     = 15,
  IPSEC_POLICY = 16,
  XFRM_POLICY  = 17,
  PASSSEC      = 18,
  TRANSPARENT  = 19,
  ORIGDSTADDR  = 20,
  MINTTL       = 21,
  NODEFRAG     = 22,
  MULTICAST_IF                 = 32,
  MULTICAST_TTL                = 33,
  MULTICAST_LOOP               = 34,
  ADD_MEMBERSHIP               = 35,
  DROP_MEMBERSHIP              = 36,
  UNBLOCK_SOURCE               = 37,
  BLOCK_SOURCE                 = 38,
  ADD_SOURCE_MEMBERSHIP        = 39,
  DROP_SOURCE_MEMBERSHIP       = 40,
  MSFILTER                     = 41,

  MULTICAST_ALL                = 49, 
  UNICAST_IF                   = 50,
}

c.ETH_P = strflag {
  LOOP      = 0x0060,
  PUP       = 0x0200,
  PUPAT     = 0x0201,
  IP        = 0x0800,
  X25       = 0x0805,
  ARP       = 0x0806,
  BPQ       = 0x08FF,
  IEEEPUP   = 0x0a00,
  IEEEPUPAT = 0x0a01,
  DEC       = 0x6000,
  DNA_DL    = 0x6001,
  DNA_RC    = 0x6002,
  DNA_RT    = 0x6003,
  LAT       = 0x6004,
  DIAG      = 0x6005,
  CUST      = 0x6006,
  SCA       = 0x6007,
  TEB       = 0x6558,
  RARP      = 0x8035,
  ATALK     = 0x809B,
  AARP      = 0x80F3,
  ["8021Q"] = 0x8100,
  IPX       = 0x8137,
  IPV6      = 0x86DD,
  PAUSE     = 0x8808,
  SLOW      = 0x8809,
  WCCP      = 0x883E,
  PPP_DISC  = 0x8863,
  PPP_SES   = 0x8864,
  MPLS_UC   = 0x8847,
  MPLS_MC   = 0x8848,
  ATMMPOA   = 0x884c,
  LINK_CTL  = 0x886c,
  ATMFATE   = 0x8884,
  PAE       = 0x888E,
  AOE       = 0x88A2,
  ["8021AD"]= 0x88A8,
  ["802_EX1"]= 0x88B5,
  TIPC      = 0x88CA,
  ["8021AH"]= 0x88E7,
  ["1588"]  = 0x88F7,
  FCOE      = 0x8906,
  TDLS      = 0x890D,
  FIP       = 0x8914,
  QINQ1     = 0x9100,
  QINQ2     = 0x9200,
  QINQ3     = 0x9300,
  EDSA      = 0xDADA,
  AF_IUCV   = 0xFBFB,
  ["802_3"] = 0x0001,
  AX25      = 0x0002,
  ALL       = 0x0003,
  ["802_2"] = 0x0004,
  SNAP      = 0x0005,
  DDCMP     = 0x0006,
  WAN_PPP   = 0x0007,
  PPP_MP    = 0x0008,
  LOCALTALK = 0x0009,
  CAN       = 0x000C,
  PPPTALK   = 0x0010,
  TR_802_2  = 0x0011,
  MOBITEX   = 0x0015,
  CONTROL   = 0x0016,
  IRDA      = 0x0017,
  ECONET    = 0x0018,
  HDLC      = 0x0019,
  ARCNET    = 0x001A,
  DSA       = 0x001B,
  TRAILER   = 0x001C,
  PHONET    = 0x00F5,
  IEEE802154= 0x00F6,
  CAIF      = 0x00F7,
}

c.ETHERTYPE = strflag {
  PUP          = 0x0200,
  SPRITE       = 0x0500,
  IP           = 0x0800,
  ARP          = 0x0806,
  REVARP       = 0x8035,
  AT           = 0x809B,
  AARP         = 0x80F3,
  VLAN         = 0x8100,
  IPX          = 0x8137,
  IPV6         = 0x86dd,
  LOOPBACK     = 0x9000,
  TRAIL        = 0x1000,
}

-- eventfd
c.EFD = multiflags {
  SEMAPHORE = 1,
  CLOEXEC = c.O.CLOEXEC,
  NONBLOCK = c.O.NONBLOCK,
}

-- mount
c.MS = multiflags {
  RDONLY = 1,
  NOSUID = 2,
  NODEV = 4,
  NOEXEC = 8,
  SYNCHRONOUS = 16,
  REMOUNT = 32,
  MANDLOCK = 64,
  DIRSYNC = 128,
  NOATIME = 1024,
  NODIRATIME = 2048,
  BIND = 4096,
  MOVE = 8192,
  REC = 16384,
  SILENT = 32768,
  POSIXACL = bit.lshift(1, 16),
  UNBINDABLE = bit.lshift(1, 17),
  PRIVATE = bit.lshift(1, 18),
  SLAVE = bit.lshift(1, 19),
  SHARED = bit.lshift(1, 20),
  RELATIME = bit.lshift(1, 21),
  KERNMOUNT = bit.lshift(1, 22),
  I_VERSION = bit.lshift(1, 23),
  STRICTATIME = bit.lshift(1, 24),
  ACTIVE = bit.lshift(1, 30),
  NOUSER = bit.lshift(1, 31),
}

-- fake flags
c.MS.RO = c.MS.RDONLY -- allow use of "ro" as flag as that is what /proc/mounts uses
c.MS.RW = 0           -- allow use of "rw" as flag as appears in /proc/mounts
c.MS.SECLABEL = 0     -- appears in /proc/mounts in some distros, ignore

-- flags to `msync'. - note was MS_ renamed to MSYNC_
c.MSYNC = multiflags {
  ASYNC       = 1,
  INVALIDATE  = 2,
  SYNC        = 4,
}

-- one table for umount as it uses MNT_ and UMOUNT_ options
c.UMOUNT = multiflags {
  FORCE    = 1,
  DETACH   = 2,
  EXPIRE   = 4,
  NOFOLLOW = 8,
}

-- reboot
c.LINUX_REBOOT_CMD = strflag {
  RESTART      =  0x01234567,
  HALT         =  0xCDEF0123,
  CAD_ON       =  0x89ABCDEF,
  CAD_OFF      =  0x00000000,
  POWER_OFF    =  0x4321FEDC,
  RESTART2     =  0xA1B2C3D4,
  SW_SUSPEND   =  0xD000FCE2,
  KEXEC        =  0x45584543,
}

-- clone
c.CLONE = multiflags {
  VM      = 0x00000100,
  FS      = 0x00000200,
  FILES   = 0x00000400,
  SIGHAND = 0x00000800,
  PTRACE  = 0x00002000,
  VFORK   = 0x00004000,
  PARENT  = 0x00008000,
  THREAD  = 0x00010000,
  NEWNS   = 0x00020000,
  SYSVSEM = 0x00040000,
  SETTLS  = 0x00080000,
  PARENT_SETTID  = 0x00100000,
  CHILD_CLEARTID = 0x00200000,
  DETACHED = 0x00400000,
  UNTRACED = 0x00800000,
  CHILD_SETTID = 0x01000000,
  NEWUTS   = 0x04000000,
  NEWIPC   = 0x08000000,
  NEWUSER  = 0x10000000,
  NEWPID   = 0x20000000,
  NEWNET   = 0x40000000,
  IO       = 0x80000000,
}

-- inotify
-- flags note rename from IN_ to IN_INIT
c.IN_INIT = multiflags(arch.IN_INIT or {
  CLOEXEC = octal("02000000"),
  NONBLOCK = octal("04000"),
})

-- events
c.IN = multiflags {
  ACCESS        = 0x00000001,
  MODIFY        = 0x00000002,
  ATTRIB        = 0x00000004,
  CLOSE_WRITE   = 0x00000008,
  CLOSE_NOWRITE = 0x00000010,
  OPEN          = 0x00000020,
  MOVED_FROM    = 0x00000040,
  MOVED_TO      = 0x00000080,
  CREATE        = 0x00000100,
  DELETE        = 0x00000200,
  DELETE_SELF   = 0x00000400,
  MOVE_SELF     = 0x00000800,
  UNMOUNT       = 0x00002000,
  Q_OVERFLOW    = 0x00004000,
  IGNORED       = 0x00008000,

  ONLYDIR       = 0x01000000,
  DONT_FOLLOW   = 0x02000000,
  EXCL_UNLINK   = 0x04000000,
  MASK_ADD      = 0x20000000,
  ISDIR         = 0x40000000,
  ONESHOT       = 0x80000000,
}

c.IN.CLOSE         = c.IN.CLOSE_WRITE + c.IN.CLOSE_NOWRITE
c.IN.MOVE          = c.IN.MOVED_FROM + c.IN.MOVED_TO

c.IN.ALL_EVENTS    = c.IN.ACCESS + c.IN.MODIFY + c.IN.ATTRIB + c.IN.CLOSE_WRITE
                       + c.IN.CLOSE_NOWRITE + c.IN.OPEN + c.IN.MOVED_FROM
                       + c.IN.MOVED_TO + c.IN.CREATE + c.IN.DELETE
                       + c.IN.DELETE_SELF + c.IN.MOVE_SELF

--prctl
c.PR = strflag {
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
  SET_NO_NEW_PRIVS = 38,
  GET_NO_NEW_PRIVS = 39,
  GET_TID_ADDRESS = 40,
}

-- for PR get/set unalign
c.PR_UNALIGN = strflag {
  NOPRINT   = 1,
  SIGBUS    = 2,
}

-- for PR fpemu
c.PR_FPEMU = strflag {
  NOPRINT     = 1,
  SIGFPE      = 2,
}

-- for PR fpexc -- TODO should be a combo of stringflag and flags
c.PR_FP_EXC = multiflags {
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
}

-- PR get set timing
c.PR_TIMING = strflag {
  STATISTICAL= 0,
  TIMESTAMP  = 1,
}

-- PR set endian
c.PR_ENDIAN = strflag {
  BIG         = 0,
  LITTLE      = 1,
  PPC_LITTLE  = 2,
}

-- PR TSC
c.PR_TSC = strflag {
  ENABLE         = 1,
  SIGSEGV        = 2,
}

-- somewhat confusing as there are some in PR too.
c.PR_MCE_KILL = strflag {
  CLEAR     = 0,
  SET       = 1,
}

-- note rename, this is extra option see prctl code
c.PR_MCE_KILL_OPT = strflag {
  LATE         = 0,
  EARLY        = 1,
  DEFAULT      = 2,
}

c.LINUX_CAPABILITY_VERSION = {0x19980330, 0x20071026, 0x20080522}
c.LINUX_CAPABILITY_U32S = {1, 2, 2}

-- capabilities NB these are bit shifts
c.CAP = strflag {
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
}

-- capabilities as stored on file system in xattr
c.VFS_CAP = strflag {
  REVISION_MASK   = 0xFF000000,
  REVISION_SHIFT  = 24,
  REVISION_1      = 0x01000000,
  U32_1           = 1,
  REVISION_2      = 0x02000000,
  U32_2           = 2,
}

c.VFS_CAP.FLAGS_MASK = bit.bnot(c.VFS_CAP.REVISION_MASK)
c.VFS_CAP.U32      = c.VFS_CAP.U32_2
c.VFS_CAP.REVISION = c.VFS_CAP.REVISION_2

c.VFS_CAP_FLAGS = strflag {
  EFFECTIVE = 0x000001,
}

c.XATTR_CAPS = strflag {
  SZ_1 = 4 * (1 + 2 * c.VFS_CAP.U32_1),
  SZ_2 = 4 * (1 + 2 * c.VFS_CAP.U32_2),
}

c.XATTR_CAPS.SZ = c.XATTR_CAPS.SZ_2

-- new SECCOMP modes, now there is filter as well as strict
c.SECCOMP_MODE = strflag {
  DISABLED = 0,
  STRICT   = 1,
  FILTER   = 2,
}

c.SECCOMP_RET = multiflags {
  KILL      = 0x00000000,
  TRAP      = 0x00030000,
  ERRNO     = 0x00050000,
  TRACE     = 0x7ff00000,
  ALLOW     = 0x7fff0000,

  ACTION    = 0x7fff0000, -- mask
  DATA      = 0x0000ffff, -- mask
}

-- Elf machine flags
c.EM = strflag {
  NONE        = 0,
  M32         = 1,
  SPARC       = 2,
  ["386"]     = 3,
  ["68K"]     = 4,
  ["88K"]     = 5,
  ["860"]     = 7,
  MIPS        = 8,
  MIPS_RS3_LE = 10,
  MIPS_RS4_BE = 10,
  PARISC      = 15,
  SPARC32PLUS = 18,
  PPC         = 20,
  PPC64       = 21,
  S390        = 22,
  SPU         = 23,
  ARM         = 40,
  SH          = 42,
  SPARCV9     = 43,
  H8_300      = 46,
  IA_64       = 50,
  X86_64      = 62,
  CRIS        = 76,
  V850        = 87,
  M32R        = 88,
  MN10300     = 89,
  BLACKFIN    = 106,
  TI_C6000    = 140,
  FRV         = 0x5441,
  AVR32       = 0x18ad,
  ALPHA       = 0x9026,
  CYGNUS_V850 = 0x9080,
  CYGNUS_M32R = 0x9041,
  S390_OLD    = 0xA390,
  CYGNUS_MN10300 = 0xbeef,
}

-- audit flags (lots missing from linux/audit.h)

-- I don't think we need to export these
local __AUDIT_ARCH_64BIT = 0x80000000
local __AUDIT_ARCH_LE    = 0x40000000

c.AUDIT_ARCH = strflag {
  ALPHA = c.EM.ALPHA + __AUDIT_ARCH_64BIT + __AUDIT_ARCH_LE,
  ARM = c.EM.ARM + __AUDIT_ARCH_LE,
  ARMEB = c.EM.ARM,
  CRIS = c.EM.CRIS + __AUDIT_ARCH_LE,
  FRV = c.EM.FRV,
  H8300 = c.EM.H8_300,
  I386 = c.EM["386"] + __AUDIT_ARCH_LE,
  IA64 = c.EM.IA_64 + __AUDIT_ARCH_64BIT + __AUDIT_ARCH_LE,
  M32R = c.EM.M32R,
  M68K = c.EM["68K"],
  MIPS = c.EM.MIPS,
  MIPSEL = c.EM.MIPS + __AUDIT_ARCH_LE,
  MIPS64 = c.EM.MIPS + __AUDIT_ARCH_64BIT,
  MIPSEL64 = c.EM.MIPS + __AUDIT_ARCH_64BIT + __AUDIT_ARCH_LE,
  PARISC = c.EM.PARISC,
  PARISC64 = c.EM.PARISC + __AUDIT_ARCH_64BIT,
  PPC = c.EM.PPC,
  PPC64 = c.EM.PPC64 + __AUDIT_ARCH_64BIT,
  S390 = c.EM.S390,
  S390X = c.EM.S390 + __AUDIT_ARCH_64BIT,
  SH = c.EM.SH,
  SHEL = c.EM.SH + __AUDIT_ARCH_LE,
  SH64 = c.EM.SH + __AUDIT_ARCH_64BIT,
  SHEL64 =c.EM.SH + __AUDIT_ARCH_64BIT + __AUDIT_ARCH_LE,
  SPARC =c.EM.SPARC,
  SPARC64 =c.EM.SPARCV9 + __AUDIT_ARCH_64BIT,
  X86_64 = c.EM.X86_64 + __AUDIT_ARCH_64BIT + __AUDIT_ARCH_LE,
}

-- BPF socket filter
c.BPF = multiflags {
-- class
  LD         = 0x00,
  LDX        = 0x01,
  ST         = 0x02,
  STX        = 0x03,
  ALU        = 0x04,
  JMP        = 0x05,
  RET        = 0x06,
  MISC       = 0x07,
-- size
  W          = 0x00,
  H          = 0x08,
  B          = 0x10,
-- mode
  IMM        = 0x00,
  ABS        = 0x20,
  IND        = 0x40,
  MEM        = 0x60,
  LEN        = 0x80,
  MSH        = 0xa0,
-- op
  ADD        = 0x00,
  SUB        = 0x10,
  MUL        = 0x20,
  DIV        = 0x30,
  OR         = 0x40,
  AND        = 0x50,
  LSH        = 0x60,
  RSH        = 0x70,
  NEG        = 0x80,
  JA         = 0x00,
  JEQ        = 0x10,
  JGT        = 0x20,
  JGE        = 0x30,
  JSET       = 0x40,
-- src
  K          = 0x00,
  X          = 0x08,
-- rval
  A          = 0x10,
-- miscop
  TAX        = 0x00,
  TXA        = 0x80,
}

-- termios - c_cc characters
c.CC = strflag(arch.CC or {
  VINTR    = 0,
  VQUIT    = 1,
  VERASE   = 2,
  VKILL    = 3,
  VEOF     = 4,
  VTIME    = 5,
  VMIN     = 6,
  VSWTC    = 7,
  VSTART   = 8,
  VSTOP    = 9,
  VSUSP    = 10,
  VEOL     = 11,
  VREPRINT = 12,
  VDISCARD = 13,
  VWERASE  = 14,
  VLNEXT   = 15,
  VEOL2    = 16,
})

-- termios - c_iflag bits
c.IFLAG = multiflags(arch.IFLAG or {
  IGNBRK  = octal('0000001'),
  BRKINT  = octal('0000002'),
  IGNPAR  = octal('0000004'),
  PARMRK  = octal('0000010'),
  INPCK   = octal('0000020'),
  ISTRIP  = octal('0000040'),
  INLCR   = octal('0000100'),
  IGNCR   = octal('0000200'),
  ICRNL   = octal('0000400'),
  IUCLC   = octal('0001000'),
  IXON    = octal('0002000'),
  IXANY   = octal('0004000'),
  IXOFF   = octal('0010000'),
  IMAXBEL = octal('0020000'),
  IUTF8   = octal('0040000'),
})

-- termios - c_oflag bits
c.OFLAG = multiflags(arch.OFLAG or {
  OPOST  = octal('0000001'),
  OLCUC  = octal('0000002'),
  ONLCR  = octal('0000004'),
  OCRNL  = octal('0000010'),
  ONOCR  = octal('0000020'),
  ONLRET = octal('0000040'),
  OFILL  = octal('0000100'),
  OFDEL  = octal('0000200'),
  NLDLY  = octal('0000400'),
  NL0    = octal('0000000'),
  NL1    = octal('0000400'),
  CRDLY  = octal('0003000'),
  CR0    = octal('0000000'),
  CR1    = octal('0001000'),
  CR2    = octal('0002000'),
  CR3    = octal('0003000'),
  TABDLY = octal('0014000'),
  TAB0   = octal('0000000'),
  TAB1   = octal('0004000'),
  TAB2   = octal('0010000'),
  TAB3   = octal('0014000'),
  BSDLY  = octal('0020000'),
  BS0    = octal('0000000'),
  BS1    = octal('0020000'),
  FFDLY  = octal('0100000'),
  FF0    = octal('0000000'),
  FF1    = octal('0100000'),
  VTDLY  = octal('0040000'),
  VT0    = octal('0000000'),
  VT1    = octal('0040000'),
  XTABS  = octal('0014000'),
})

-- using string keys as sparse array uses a lot of memory
c.B = setmetatable(arch.B or {
  ['0'] = octal('0000000'),
  ['50'] = octal('0000001'),
  ['75'] = octal('0000002'),
  ['110'] = octal('0000003'),
  ['134'] = octal('0000004'),
  ['150'] = octal('0000005'),
  ['200'] = octal('0000006'),
  ['300'] = octal('0000007'),
  ['600'] = octal('0000010'),
  ['1200'] = octal('0000011'),
  ['1800'] = octal('0000012'),
  ['2400'] = octal('0000013'),
  ['4800'] = octal('0000014'),
  ['9600'] = octal('0000015'),
  ['19200'] = octal('0000016'),
  ['38400'] = octal('0000017'),
  ['57600'] = octal('0010001'),
  ['115200'] = octal('0010002'),
  ['230400'] = octal('0010003'),
  ['460800'] = octal('0010004'),
  ['500000'] = octal('0010005'),
  ['576000'] = octal('0010006'),
  ['921600'] = octal('0010007'),
  ['1000000'] = octal('0010010'),
  ['1152000'] = octal('0010011'),
  ['1500000'] = octal('0010012'),
  ['2000000'] = octal('0010013'),
  ['2500000'] = octal('0010014'),
  ['3000000'] = octal('0010015'),
  ['3500000'] = octal('0010016'),
  ['4000000'] = octal('0010017'),
}, {
  __index = function(b, k)
    return b[tostring(k)]
  end,
})

--[[
c.__MAX_BAUD = c.B4000000
c.EXTA       = c.B19200
c.EXTB       = c.B38400
]]

-- TODO clean up how to handle these (used for custom speeds)
c.CBAUD      = arch.CBAUD or octal('0010017')
c.CBAUDEX    = arch.CBAUDEX or octal('0010000')
c.CIBAUD     = arch.CIBAUD or octal('002003600000') -- input baud rate (not used)

c.CMSPAR     = octal('010000000000') -- mark or space (stick) parity
c.CRTSCTS    = octal('020000000000') -- flow control

-- termios - c_cflag bits
c.CFLAG = multiflags(arch.CFLAG or {
  CSIZE      = octal('0000060'),
  CS5        = octal('0000000'),
  CS6        = octal('0000020'),
  CS7        = octal('0000040'),
  CS8        = octal('0000060'),
  CSTOPB     = octal('0000100'),
  CREAD      = octal('0000200'),
  PARENB     = octal('0000400'),
  PARODD     = octal('0001000'),
  HUPCL      = octal('0002000'),
  CLOCAL     = octal('0004000'),
})

-- termios - c_lflag bits
c.LFLAG = multiflags(arch.LFLAG or {
  ISIG    = octal('0000001'),
  ICANON  = octal('0000002'),
  XCASE   = octal('0000004'),
  ECHO    = octal('0000010'),
  ECHOE   = octal('0000020'),
  ECHOK   = octal('0000040'),
  ECHONL  = octal('0000100'),
  NOFLSH  = octal('0000200'),
  TOSTOP  = octal('0000400'),
  ECHOCTL = octal('0001000'),
  ECHOPRT = octal('0002000'),
  ECHOKE  = octal('0004000'),
  FLUSHO  = octal('0010000'),
  PENDIN  = octal('0040000'),
  IEXTEN  = octal('0100000'),
  EXTPROC = octal('0200000'),
})

-- termios - tcflow() and TCXONC use these. renamed from TC to TCFLOW
c.TCFLOW = strflag {
  OOFF = 0,
  OON  = 1,
  IOFF = 2,
  ION  = 3,
}

-- termios - tcflush() and TCFLSH use these. renamed from TC to TCFLUSH
c.TCFLUSH = strflag {
  IFLUSH  = 0,
  OFLUSH  = 1,
  IOFLUSH = 2,
}

-- termios - tcsetattr uses these
c.TCSA = strflag {
  NOW   = 0,
  DRAIN = 1,
  FLUSH = 2,
}

-- TIOCM
c.TIOCM = multiflags(arch.TIOCM or {
  LE  = 0x001,
  DTR = 0x002,
  RTS = 0x004,
  ST  = 0x008,
  SR  = 0x010,
  CTS = 0x020,
  CAR = 0x040,
  RNG = 0x080,
  DSR = 0x100,
})

c.TIOCM.CD  = c.TIOCM.CAR
c.TIOCM.RI  = c.TIOCM.RNG

-- sysfs values
c.SYSFS_BRIDGE_ATTR        = "bridge"
c.SYSFS_BRIDGE_FDB         = "brforward"
c.SYSFS_BRIDGE_PORT_SUBDIR = "brif"
c.SYSFS_BRIDGE_PORT_ATTR   = "brport"
c.SYSFS_BRIDGE_PORT_LINK   = "bridge"

-- sizes -- TODO in tables?
c.HOST_NAME_MAX = 64
c.IFNAMSIZ      = 16
c.IFHWADDRLEN   = 6

-- input subsystem. TODO split into another file as a lot of them
c.INPUT_PROP = strflag {
  POINTER              = 0x00,
  DIRECT               = 0x01,
  BUTTONPAD            = 0x02,
  SEMI_MT              = 0x03,
}

c.EV = strflag {
  SYN                  = 0x00,
  KEY                  = 0x01,
  REL                  = 0x02,
  ABS                  = 0x03,
  MSC                  = 0x04,
  SW                   = 0x05,
  LED                  = 0x11,
  SND                  = 0x12,
  REP                  = 0x14,
  FF                   = 0x15,
  PWR                  = 0x16,
  FF_STATUS    	       = 0x17,
  MAX                  = 0x1f,
}

c.SYN = strflag {
  REPORT              = 0,
  CONFIG              = 1,
  MT_REPORT   	      = 2,
  DROPPED             = 3,
}

-- TODO odd namespacing issue with KEY and BTN, not sure best resolution, maybe have KEYBTN table with both
c.KEY = strflag {
  RESERVED            = 0,
  ESC                 = 1,
  ["1"]               = 2,
  ["2"]               = 3,
  ["3"]               = 4,
  ["4"]               = 5,
  ["5"]               = 6,
  ["6"]               = 7,
  ["7"]               = 8,
  ["8"]               = 9,
  ["9"]               = 10,
  ["0"]               = 11,
  MINUS               = 12,
  EQUAL               = 13,
  BACKSPACE           = 14,
  TAB                 = 15,
  Q                   = 16,
  W                   = 17,
  E                   = 18,
  R                   = 19,
  T                   = 20,
  Y                   = 21,
  U                   = 22,
  I                   = 23,
  O                   = 24,
  P                   = 25,
  LEFTBRACE           = 26,
  RIGHTBRACE          = 27,
  ENTER               = 28,
  LEFTCTRL            = 29,
  A                   = 30,
  S                   = 31,
  D                   = 32,
  F                   = 33,
  G                   = 34,
  H                   = 35,
  J                   = 36,
  K                   = 37,
  L                   = 38,
  SEMICOLON           = 39,
  APOSTROPHE          = 40,
  GRAVE               = 41,
  LEFTSHIFT           = 42,
  BACKSLASH           = 43,
  Z                   = 44,
  X                   = 45,
  C                   = 46,
  V                   = 47,
  B                   = 48,
  N                   = 49,
  M                   = 50,
  COMMA               = 51,
  DOT                 = 52,
  SLASH               = 53,
  RIGHTSHIFT          = 54,
  KPASTERISK          = 55,
  LEFTALT             = 56,
  SPACE               = 57,
  CAPSLOCK            = 58,
  F1                  = 59,
  F2                  = 60,
  F3                  = 61,
  F4                  = 62,
  F5                  = 63,
  F6                  = 64,
  F7                  = 65,
  F8                  = 66,
  F9                  = 67,
  F10                 = 68,
  NUMLOCK             = 69,
  SCROLLLOCK          = 70,
  KP7                 = 71,
  KP8                 = 72,
  KP9                 = 73,
  KPMINUS             = 74,
  KP4                 = 75,
  KP5                 = 76,
  KP6                 = 77,
  KPPLUS              = 78,
  KP1                 = 79,
  KP2                 = 80,
  KP3                 = 81,
  KP0                 = 82,
  KPDOT               = 83,
  ZENKAKUHANKAKU      = 85,
  ["102ND"]           = 86,
  F11                 = 87,
  F12                 = 88,
  RO                  = 89,
  KATAKANA            = 90,
  HIRAGANA            = 91,
  HENKAN              = 92,
  KATAKANAHIRAGANA    = 93,
  MUHENKAN            = 94,
  KPJPCOMMA           = 95,
  KPENTER             = 96,
  RIGHTCTRL           = 97,
  KPSLASH             = 98,
  SYSRQ               = 99,
  RIGHTALT            = 100,
  LINEFEED            = 101,
  HOME                = 102,
  UP                  = 103,
  PAGEUP              = 104,
  LEFT                = 105,
  RIGHT               = 106,
  END                 = 107,
  DOWN                = 108,
  PAGEDOWN            = 109,
  INSERT              = 110,
  DELETE              = 111,
  MACRO               = 112,
  MUTE                = 113,
  VOLUMEDOWN          = 114,
  VOLUMEUP            = 115,
  POWER               = 116,
  KPEQUAL             = 117,
  KPPLUSMINUS         = 118,
  PAUSE               = 119,
  SCALE               = 120,
  KPCOMMA             = 121,
  HANGEUL             = 122,
  HANJA               = 123,
  YEN                 = 124,
  LEFTMETA            = 125,
  RIGHTMETA           = 126,
  COMPOSE             = 127,
  STOP                = 128,
  AGAIN               = 129,
  PROPS               = 130,
  UNDO                = 131,
  FRONT               = 132,
  COPY                = 133,
  OPEN                = 134,
  PASTE               = 135,
  FIND                = 136,
  CUT                 = 137,
  HELP                = 138,
  MENU                = 139,
  CALC                = 140,
  SETUP               = 141,
  SLEEP               = 142,
  WAKEUP              = 143,
  FILE                = 144,
  SENDFILE            = 145,
  DELETEFILE          = 146,
  XFER                = 147,
  PROG1               = 148,
  PROG2               = 149,
  WWW                 = 150,
  MSDOS               = 151,
  COFFEE              = 152,
  DIRECTION           = 153,
  CYCLEWINDOWS        = 154,
  MAIL                = 155,
  BOOKMARKS           = 156,
  COMPUTER            = 157,
  BACK                = 158,
  FORWARD             = 159,
  CLOSECD             = 160,
  EJECTCD             = 161,
  EJECTCLOSECD        = 162,
  NEXTSONG            = 163,
  PLAYPAUSE           = 164,
  PREVIOUSSONG        = 165,
  STOPCD              = 166,
  RECORD              = 167,
  REWIND              = 168,
  PHONE               = 169,
  ISO                 = 170,
  CONFIG              = 171,
  HOMEPAGE            = 172,
  REFRESH             = 173,
  EXIT                = 174,
  MOVE                = 175,
  EDIT                = 176,
  SCROLLUP            = 177,
  SCROLLDOWN          = 178,
  KPLEFTPAREN         = 179,
  KPRIGHTPAREN        = 180,
  NEW                 = 181,
  REDO                = 182,
  F13                 = 183,
  F14                 = 184,
  F15                 = 185,
  F16                 = 186,
  F17                 = 187,
  F18                 = 188,
  F19                 = 189,
  F20                 = 190,
  F21                 = 191,
  F22                 = 192,
  F23                 = 193,
  F24                 = 194,
  PLAYCD              = 200,
  PAUSECD             = 201,
  PROG3               = 202,
  PROG4               = 203,
  DASHBOARD           = 204,
  SUSPEND             = 205,
  CLOSE               = 206,
  PLAY                = 207,
  FASTFORWARD         = 208,
  BASSBOOST           = 209,
  PRINT               = 210,
  HP                  = 211,
  CAMERA              = 212,
  SOUND               = 213,
  QUESTION            = 214,
  EMAIL               = 215,
  CHAT                = 216,
  SEARCH              = 217,
  CONNECT             = 218,
  FINANCE             = 219,
  SPORT               = 220,
  SHOP                = 221,
  ALTERASE            = 222,
  CANCEL              = 223,
  BRIGHTNESSDOWN      = 224,
  BRIGHTNESSUP        = 225,
  MEDIA               = 226,
  SWITCHVIDEOMODE     = 227,
  KBDILLUMTOGGLE      = 228,
  KBDILLUMDOWN        = 229,
  KBDILLUMUP          = 230,
  SEND                = 231,
  REPLY               = 232,
  FORWARDMAIL         = 233,
  SAVE                = 234,
  DOCUMENTS           = 235,
  BATTERY             = 236,
  BLUETOOTH           = 237,
  WLAN                = 238,
  UWB                 = 239,
  UNKNOWN             = 240,
  VIDEO_NEXT          = 241,
  VIDEO_PREV          = 242,
  BRIGHTNESS_CYCLE    = 243,
  BRIGHTNESS_ZERO     = 244,
  DISPLAY_OFF         = 245,
  WIMAX               = 246,
  RFKILL              = 247,
  MICMUTE             = 248,
-- BTN values go in here
  OK                  = 0x160,
  SELECT              = 0x161,
  GOTO                = 0x162,
  CLEAR               = 0x163,
  POWER2              = 0x164,
  OPTION              = 0x165,
  INFO                = 0x166,
  TIME                = 0x167,
  VENDOR              = 0x168,
  ARCHIVE             = 0x169,
  PROGRAM             = 0x16a,
  CHANNEL             = 0x16b,
  FAVORITES           = 0x16c,
  EPG                 = 0x16d,
  PVR                 = 0x16e,
  MHP                 = 0x16f,
  LANGUAGE            = 0x170,
  TITLE               = 0x171,
  SUBTITLE            = 0x172,
  ANGLE               = 0x173,
  ZOOM                = 0x174,
  MODE                = 0x175,
  KEYBOARD            = 0x176,
  SCREEN              = 0x177,
  PC                  = 0x178,
  TV                  = 0x179,
  TV2                 = 0x17a,
  VCR                 = 0x17b,
  VCR2                = 0x17c,
  SAT                 = 0x17d,
  SAT2                = 0x17e,
  CD                  = 0x17f,
  TAPE                = 0x180,
  RADIO               = 0x181,
  TUNER               = 0x182,
  PLAYER              = 0x183,
  TEXT                = 0x184,
  DVD                 = 0x185,
  AUX                 = 0x186,
  MP3                 = 0x187,
  AUDIO               = 0x188,
  VIDEO               = 0x189,
  DIRECTORY           = 0x18a,
  LIST                = 0x18b,
  MEMO                = 0x18c,
  CALENDAR            = 0x18d,
  RED                 = 0x18e,
  GREEN               = 0x18f,
  YELLOW              = 0x190,
  BLUE                = 0x191,
  CHANNELUP           = 0x192,
  CHANNELDOWN         = 0x193,
  FIRST               = 0x194,
  LAST                = 0x195,
  AB                  = 0x196,
  NEXT                = 0x197,
  RESTART             = 0x198,
  SLOW                = 0x199,
  SHUFFLE             = 0x19a,
  BREAK               = 0x19b,
  PREVIOUS            = 0x19c,
  DIGITS              = 0x19d,
  TEEN                = 0x19e,
  TWEN                = 0x19f,
  VIDEOPHONE          = 0x1a0,
  GAMES               = 0x1a1,
  ZOOMIN              = 0x1a2,
  ZOOMOUT             = 0x1a3,
  ZOOMRESET           = 0x1a4,
  WORDPROCESSOR       = 0x1a5,
  EDITOR              = 0x1a6,
  SPREADSHEET         = 0x1a7,
  GRAPHICSEDITOR      = 0x1a8,
  PRESENTATION        = 0x1a9,
  DATABASE            = 0x1aa,
  NEWS                = 0x1ab,
  VOICEMAIL           = 0x1ac,
  ADDRESSBOOK         = 0x1ad,
  MESSENGER           = 0x1ae,
  DISPLAYTOGGLE       = 0x1af,
  SPELLCHECK          = 0x1b0,
  LOGOFF              = 0x1b1,
  DOLLAR              = 0x1b2,
  EURO                = 0x1b3,
  FRAMEBACK           = 0x1b4,
  FRAMEFORWARD        = 0x1b5,
  CONTEXT_MENU        = 0x1b6,
  MEDIA_REPEAT        = 0x1b7,
  ["10CHANNELSUP"]    = 0x1b8,
  ["10CHANNELSDOWN"]  = 0x1b9,
  IMAGES              = 0x1ba,
  DEL_EOL             = 0x1c0,
  DEL_EOS             = 0x1c1,
  INS_LINE            = 0x1c2,
  DEL_LINE            = 0x1c3,
  FN                  = 0x1d0,
  FN_ESC              = 0x1d1,
  FN_F1               = 0x1d2,
  FN_F2               = 0x1d3,
  FN_F3               = 0x1d4,
  FN_F4               = 0x1d5,
  FN_F5               = 0x1d6,
  FN_F6               = 0x1d7,
  FN_F7               = 0x1d8,
  FN_F8               = 0x1d9,
  FN_F9               = 0x1da,
  FN_F10              = 0x1db,
  FN_F11              = 0x1dc,
  FN_F12              = 0x1dd,
  FN_1                = 0x1de,
  FN_2                = 0x1df,
  FN_D                = 0x1e0,
  FN_E                = 0x1e1,
  FN_F                = 0x1e2,
  FN_S                = 0x1e3,
  FN_B                = 0x1e4,
  BRL_DOT1            = 0x1f1,
  BRL_DOT2            = 0x1f2,
  BRL_DOT3            = 0x1f3,
  BRL_DOT4            = 0x1f4,
  BRL_DOT5            = 0x1f5,
  BRL_DOT6            = 0x1f6,
  BRL_DOT7            = 0x1f7,
  BRL_DOT8            = 0x1f8,
  BRL_DOT9            = 0x1f9,
  BRL_DOT10           = 0x1fa,
  NUMERIC_0           = 0x200,
  NUMERIC_1           = 0x201,
  NUMERIC_2           = 0x202,
  NUMERIC_3           = 0x203,
  NUMERIC_4           = 0x204,
  NUMERIC_5           = 0x205,
  NUMERIC_6           = 0x206,
  NUMERIC_7           = 0x207,
  NUMERIC_8           = 0x208,
  NUMERIC_9           = 0x209,
  NUMERIC_STAR        = 0x20a,
  NUMERIC_POUND       = 0x20b,
  CAMERA_FOCUS        = 0x210,
  WPS_BUTTON          = 0x211,
  TOUCHPAD_TOGGLE     = 0x212,
  TOUCHPAD_ON         = 0x213,
  TOUCHPAD_OFF        = 0x214,
  CAMERA_ZOOMIN       = 0x215,
  CAMERA_ZOOMOUT      = 0x216,
  CAMERA_UP           = 0x217,
  CAMERA_DOWN         = 0x218,
  CAMERA_LEFT         = 0x219,
  CAMERA_RIGHT        = 0x21a,
}

c.KEY.SCREENLOCK = c.KEY.COFFEE
c.KEY.HANGUEL    = c.KEY.HANGEUL

c.BTN = strflag {
  MISC                = 0x100,
  ["0"]               = 0x100,
  ["1"]               = 0x101,
  ["2"]               = 0x102,
  ["3"]               = 0x103,
  ["4"]               = 0x104,
  ["5"]               = 0x105,
  ["6"]               = 0x106,
  ["7"]               = 0x107,
  ["8"]               = 0x108,
  ["9"]               = 0x109,
  MOUSE               = 0x110,
  LEFT                = 0x110,
  RIGHT               = 0x111,
  MIDDLE              = 0x112,
  SIDE                = 0x113,
  EXTRA               = 0x114,
  FORWARD             = 0x115,
  BACK                = 0x116,
  TASK                = 0x117,
  JOYSTICK            = 0x120,
  TRIGGER             = 0x120,
  THUMB               = 0x121,
  THUMB2              = 0x122,
  TOP                 = 0x123,
  TOP2                = 0x124,
  PINKIE              = 0x125,
  BASE                = 0x126,
  BASE2               = 0x127,
  BASE3               = 0x128,
  BASE4               = 0x129,
  BASE5               = 0x12a,
  BASE6               = 0x12b,
  DEAD                = 0x12f,
  GAMEPAD             = 0x130,
  A                   = 0x130,
  B                   = 0x131,
  C                   = 0x132,
  X                   = 0x133,
  Y                   = 0x134,
  Z                   = 0x135,
  TL                  = 0x136,
  TR                  = 0x137,
  TL2                 = 0x138,
  TR2                 = 0x139,
  SELECT              = 0x13a,
  START               = 0x13b,
  MODE                = 0x13c,
  THUMBL              = 0x13d,
  THUMBR              = 0x13e,
  DIGI                = 0x140,
  TOOL_PEN            = 0x140,
  TOOL_RUBBER         = 0x141,
  TOOL_BRUSH          = 0x142,
  TOOL_PENCIL         = 0x143,
  TOOL_AIRBRUSH       = 0x144,
  TOOL_FINGER         = 0x145,
  TOOL_MOUSE          = 0x146,
  TOOL_LENS           = 0x147,
  TOOL_QUINTTAP       = 0x148,
  TOUCH               = 0x14a,
  STYLUS              = 0x14b,
  STYLUS2             = 0x14c,
  TOOL_DOUBLETAP      = 0x14d,
  TOOL_TRIPLETAP      = 0x14e,
  TOOL_QUADTAP        = 0x14f,
  WHEEL               = 0x150,
  GEAR_DOWN           = 0x150,
  GEAR_UP             = 0x151,

  TRIGGER_HAPPY               = 0x2c0,
  TRIGGER_HAPPY1              = 0x2c0,
  TRIGGER_HAPPY2              = 0x2c1,
  TRIGGER_HAPPY3              = 0x2c2,
  TRIGGER_HAPPY4              = 0x2c3,
  TRIGGER_HAPPY5              = 0x2c4,
  TRIGGER_HAPPY6              = 0x2c5,
  TRIGGER_HAPPY7              = 0x2c6,
  TRIGGER_HAPPY8              = 0x2c7,
  TRIGGER_HAPPY9              = 0x2c8,
  TRIGGER_HAPPY10             = 0x2c9,
  TRIGGER_HAPPY11             = 0x2ca,
  TRIGGER_HAPPY12             = 0x2cb,
  TRIGGER_HAPPY13             = 0x2cc,
  TRIGGER_HAPPY14             = 0x2cd,
  TRIGGER_HAPPY15             = 0x2ce,
  TRIGGER_HAPPY16             = 0x2cf,
  TRIGGER_HAPPY17             = 0x2d0,
  TRIGGER_HAPPY18             = 0x2d1,
  TRIGGER_HAPPY19             = 0x2d2,
  TRIGGER_HAPPY20             = 0x2d3,
  TRIGGER_HAPPY21             = 0x2d4,
  TRIGGER_HAPPY22             = 0x2d5,
  TRIGGER_HAPPY23             = 0x2d6,
  TRIGGER_HAPPY24             = 0x2d7,
  TRIGGER_HAPPY25             = 0x2d8,
  TRIGGER_HAPPY26             = 0x2d9,
  TRIGGER_HAPPY27             = 0x2da,
  TRIGGER_HAPPY28             = 0x2db,
  TRIGGER_HAPPY29             = 0x2dc,
  TRIGGER_HAPPY30             = 0x2dd,
  TRIGGER_HAPPY31             = 0x2de,
  TRIGGER_HAPPY32             = 0x2df,
  TRIGGER_HAPPY33             = 0x2e0,
  TRIGGER_HAPPY34             = 0x2e1,
  TRIGGER_HAPPY35             = 0x2e2,
  TRIGGER_HAPPY36             = 0x2e3,
  TRIGGER_HAPPY37             = 0x2e4,
  TRIGGER_HAPPY38             = 0x2e5,
  TRIGGER_HAPPY39             = 0x2e6,
  TRIGGER_HAPPY40             = 0x2e7,
}

c.REL = strflag {
  X                   = 0x00,
  Y                   = 0x01,
  Z                   = 0x02,
  RX                  = 0x03,
  RY                  = 0x04,
  RZ                  = 0x05,
  HWHEEL              = 0x06,
  DIAL                = 0x07,
  WHEEL               = 0x08,
  MISC                = 0x09,
  MAX                 = 0x0f,
}

c.ABS = strflag {
  X                   = 0x00,
  Y                   = 0x01,
  Z                   = 0x02,
  RX                  = 0x03,
  RY                  = 0x04,
  RZ                  = 0x05,
  THROTTLE            = 0x06,
  RUDDER              = 0x07,
  WHEEL               = 0x08,
  GAS                 = 0x09,
  BRAKE               = 0x0a,
  HAT0X               = 0x10,
  HAT0Y               = 0x11,
  HAT1X               = 0x12,
  HAT1Y               = 0x13,
  HAT2X               = 0x14,
  HAT2Y               = 0x15,
  HAT3X               = 0x16,
  HAT3Y               = 0x17,
  PRESSURE            = 0x18,
  DISTANCE            = 0x19,
  TILT_X              = 0x1a,
  TILT_Y              = 0x1b,
  TOOL_WIDTH          = 0x1c,
  VOLUME              = 0x20,
  MISC                = 0x28,
  MT_SLOT             = 0x2f,
  MT_TOUCH_MAJOR      = 0x30,
  MT_TOUCH_MINOR      = 0x31,
  MT_WIDTH_MAJOR      = 0x32,
  MT_WIDTH_MINOR      = 0x33,
  MT_ORIENTATION      = 0x34,
  MT_POSITION_X       = 0x35,
  MT_POSITION_Y       = 0x36,
  MT_TOOL_TYPE        = 0x37,
  MT_BLOB_ID          = 0x38,
  MT_TRACKING_ID      = 0x39,
  MT_PRESSURE         = 0x3a,
  MT_DISTANCE         = 0x3b,
  MAX                 = 0x3f,
}

c.MSC = strflag {
  SERIAL              = 0x00,
  PULSELED            = 0x01,
  GESTURE             = 0x02,
  RAW                 = 0x03,
  SCAN                = 0x04,
  MAX                 = 0x07,
}

c.LED = strflag {
  NUML                = 0x00,
  CAPSL               = 0x01,
  SCROLLL             = 0x02,
  COMPOSE             = 0x03,
  KANA                = 0x04,
  SLEEP               = 0x05,
  SUSPEND             = 0x06,
  MUTE                = 0x07,
  MISC                = 0x08,
  MAIL                = 0x09,
  CHARGING            = 0x0a,
  MAX                 = 0x0f,
}

c.REP = strflag {
  DELAY               = 0x00,
  PERIOD              = 0x01,
  MAX                 = 0x01,
}

c.SND = strflag {
  CLICK               = 0x00,
  BELL                = 0x01,
  TONE                = 0x02,
  MAX                 = 0x07,
}

c.ID = strflag {
  BUS                  = 0,
  VENDOR               = 1,
  PRODUCT              = 2,
  VERSION              = 3,
}

c.BUS = strflag {
  PCI                 = 0x01,
  ISAPNP              = 0x02,
  USB                 = 0x03,
  HIL                 = 0x04,
  BLUETOOTH           = 0x05,
  VIRTUAL             = 0x06,
  ISA                 = 0x10,
  I8042               = 0x11,
  XTKBD               = 0x12,
  RS232               = 0x13,
  GAMEPORT            = 0x14,
  PARPORT             = 0x15,
  AMIGA               = 0x16,
  ADB                 = 0x17,
  I2C                 = 0x18,
  HOST                = 0x19,
  GSC                 = 0x1A,
  ATARI               = 0x1B,
  SPI                 = 0x1C,
}

c.MT_TOOL = strflag {
  FINGER  = 0,
  PEN     = 1,
  MAX     = 1,
}

c.FF_STATUS = strflag {
  STOPPED       = 0x00,
  PLAYING       = 0x01,
  MAX           = 0x01,
}

-- TODO note these are split into different categories eg EFFECT, WAVEFORM unclear how best to handle (FF_STATUS too?)
c.FF = strflag {
-- EFFECT
  RUMBLE       = 0x50,
  PERIODIC     = 0x51,
  CONSTANT     = 0x52,
  SPRING       = 0x53,
  FRICTION     = 0x54,
  DAMPER       = 0x55,
  INERTIA      = 0x56,
  RAMP         = 0x57,
-- WAVEFORM
  SQUARE       = 0x58,
  TRIANGLE     = 0x59,
  SINE         = 0x5a,
  SAW_UP       = 0x5b,
  SAW_DOWN     = 0x5c,
  CUSTOM       = 0x5d,
-- dev props
  GAIN         = 0x60,
  AUTOCENTER   = 0x61,
}

-- errors
c.E = strflag(arch.E or {
  PERM          =  1,
  NOENT         =  2,
  SRCH          =  3,
  INTR          =  4,
  IO            =  5,
  NXIO          =  6,
  ["2BIG"]      =  7,
  NOEXEC        =  8,
  BADF          =  9,
  CHILD         = 10,
  AGAIN         = 11,
  NOMEM         = 12,
  ACCES         = 13,
  FAULT         = 14,
  NOTBLK        = 15,
  BUSY          = 16,
  EXIST         = 17,
  XDEV          = 18,
  NODEV         = 19,
  NOTDIR        = 20,
  ISDIR         = 21,
  INVAL         = 22,
  NFILE         = 23,
  MFILE         = 24,
  NOTTY         = 25,
  TXTBSY        = 26,
  FBIG          = 27,
  NOSPC         = 28,
  SPIPE         = 29,
  ROFS          = 30,
  MLINK         = 31,
  PIPE          = 32,
  DOM           = 33,
  RANGE         = 34,
  DEADLK        = 35,
  NAMETOOLONG   = 36,
  NOLCK         = 37,
  NOSYS         = 38,
  NOTEMPTY      = 39,
  LOOP          = 40,
  NOMSG         = 42,
  IDRM          = 43,
  CHRNG         = 44,
  L2NSYNC       = 45,
  L3HLT         = 46,
  L3RST         = 47,
  LNRNG         = 48,
  UNATCH        = 49,
  NOCSI         = 50,
  L2HLT         = 51,
  BADE          = 52,
  BADR          = 53,
  XFULL         = 54,
  NOANO         = 55,
  BADRQC        = 56,
  BADSLT        = 57,
  BFONT         = 59,
  NOSTR         = 60,
  NODATA        = 61,
  TIME          = 62,
  NOSR          = 63,
  NONET         = 64,
  NOPKG         = 65,
  REMOTE        = 66,
  NOLINK        = 67,
  ADV           = 68,
  SRMNT         = 69,
  COMM          = 70,
  PROTO         = 71,
  MULTIHOP      = 72,
  DOTDOT        = 73,
  BADMSG        = 74,
  OVERFLOW      = 75,
  NOTUNIQ       = 76,
  BADFD         = 77,
  REMCHG        = 78,
  LIBACC        = 79,
  LIBBAD        = 80,
  LIBSCN        = 81,
  LIBMAX        = 82,
  LIBEXEC       = 83,
  ILSEQ         = 84,
  RESTART       = 85,
  STRPIPE       = 86,
  USERS         = 87,
  NOTSOCK       = 88,
  DESTADDRREQ   = 89,
  MSGSIZE       = 90,
  PROTOTYPE     = 91,
  NOPROTOOPT    = 92,
  PROTONOSUPPORT= 93,
  SOCKTNOSUPPORT= 94,
  OPNOTSUPP     = 95,
  PFNOSUPPORT   = 96,
  AFNOSUPPORT   = 97,
  ADDRINUSE     = 98,
  ADDRNOTAVAIL  = 99,
  NETDOWN       = 100,
  NETUNREACH    = 101,
  NETRESET      = 102,
  CONNABORTED   = 103,
  CONNRESET     = 104,
  NOBUFS        = 105,
  ISCONN        = 106,
  NOTCONN       = 107,
  SHUTDOWN      = 108,
  TOOMANYREFS   = 109,
  TIMEDOUT      = 110,
  CONNREFUSED   = 111,
  HOSTDOWN      = 112,
  HOSTUNREACH   = 113,
  ALREADY       = 114,
  INPROGRESS    = 115,
  STALE         = 116,
  UCLEAN        = 117,
  NOTNAM        = 118,
  NAVAIL        = 119,
  ISNAM         = 120,
  REMOTEIO      = 121,
  DQUOT         = 122,
  NOMEDIUM      = 123,
  MEDIUMTYPE    = 124,
  CANCELED      = 125,
  NOKEY         = 126,
  KEYEXPIRED    = 127,
  KEYREVOKED    = 128,
  KEYREJECTED   = 129,
  OWNERDEAD     = 130,
  NOTRECOVERABLE= 131,
  RFKILL        = 132,
})

-- ppc only redefines DEADLOCK, mips redefines all
if arch.EDEADLOCK then c.E.DEADLOCK = arch.EDEADLOCK end

-- alternate names
c.EALIAS = {
  WOULDBLOCK    = c.E.AGAIN,
  NOATTR        = c.E.NODATA,
  NOTSUP        = c.E.OPNOTSUPP,
}
-- for most architectures this is an alias, but not ppc, mips
if not c.E.DEADLOCK then c.EALIAS.DEADLOCK = c.E.DEADLK end

c.SWAP_FLAG = swapflags {
  PREFER       = 0x8000,
  PRIO_MASK    = 0x7fff,
  PRIO_SHIFT   = 0,
  DISCARD      = 0x10000,
}

--c.FUTEX = 

-- iptables/xtables

c.NF = strflag {
  DROP = 0,
  ACCEPT = 1,
  STOLEN = 2,
  QUEUE = 3,
  REPEAT = 4,
  STOP = 5,
}

-- misc values, just gathered in a table as better namespacing
c.XT = strflag {
  FUNCTION_MAXNAMELEN  = 30,
  EXTENSION_MAXNAMELEN = 29,
  TABLE_MAXNAMELEN     = 32,
}

local IPT_BASE_CTL = 64

c.IPT_SO_SET = strflag {
  REPLACE      = IPT_BASE_CTL,
  ADD_COUNTERS = IPT_BASE_CTL + 1,
}

c.IPT_SO_GET = strflag {
  INFO                 = IPT_BASE_CTL,
  ENTRIES              = IPT_BASE_CTL + 1,
  REVISION_MATCH       = IPT_BASE_CTL + 2,
  REVISION_TARGET      = IPT_BASE_CTL + 3,
}

c.SCHED = multiflags {
  NORMAL           = 0,
  OTHER            = 0,
  FIFO             = 1,
  RR               = 2,
  BATCH            = 3,
  -- ISO
  IDLE             = 5,
  RESET_ON_FORK    = 0x40000000, -- TODO only this flag can be ORed
}

c.TUN_READQ = strflag {
  SIZE = 500,
}

c.TUN = multiflags {
  TUN_DEV    = 0x0001, 
  TAP_DEV    = 0x0002,
  TYPE_MASK  = 0x000f,
  FASYNC     = 0x0010,
  NOCHECKSUM = 0x0020,
  NO_PI      = 0x0040,
  ONE_QUEUE  = 0x0080,
  PERSIST    = 0x0100,
  VNET_HDR   = 0x0200,
  TAP_MQ     = 0x0400,
}

-- note that these are IFF_ but that is a duplicated prefix so using this.
-- These are valid options for struct ifreq flags, while the other IFF_ are for ifinfo
c.IFREQ = multiflags {
-- for tun tap interfaces
  TUN          = 0x0001,
  TAP          = 0x0002,
  NO_PI        = 0x1000,
  ONE_QUEUE    = 0x2000,
  VNET_HDR     = 0x4000,
  TUN_EXCL     = 0x8000,
  MULTI_QUEUE  = 0x0100,
  ATTACH_QUEUE = 0x0200,
  DETACH_QUEUE = 0x0400,
-- for bridge interfaces
  SLAVE_NEEDARP = 0x40,
  ISATAP        = 0x80,
  MASTER_ARPMON = 0x100,
  WAN_HDLC      = 0x200,
  XMIT_DST_RELEASE = 0x400,
  DONT_BRIDGE   = 0x800,
  DISABLE_NETPOLL  = 0x1000,
  MACVLAN_PORT     = 0x2000,
  BRIDGE_PORT   = 0x4000,
  OVS_DATAPATH     = 0x8000,
  TX_SKB_SHARING   = 0x10000,
  UNICAST_FLT   = 0x20000,
}

c.TUN_F = multiflags {
  CSUM     = 0x01,
  TSO4     = 0x02,
  TSO6     = 0x04,
  TSO_ECN  = 0x08,
  UFO      = 0x10,
}

c.TUN_PKT = strflag {
  STRIP = 0x0001,
}

c.TUN_FLT = strflag {
  ALLMULTI = 0x0001,
}

c.PC = strflag {
  LINK_MAX          =  0,
  MAX_CANON         =  1,
  MAX_INPUT         =  2,
  NAME_MAX          =  3,
  PATH_MAX          =  4,
  PIPE_BUF          =  5,
  CHOWN_RESTRICTED  =  6,
  NO_TRUNC          =  7,
  VDISABLE          =  8,
  SYNC_IO           =  9,
  ASYNC_IO          = 10,
  PRIO_IO           = 11,
  SOCK_MAXBUF       = 12,
  FILESIZEBITS      = 13,
  REC_INCR_XFER_SIZE= 14,
  REC_MAX_XFER_SIZE = 15,
  REC_MIN_XFER_SIZE = 16,
  REC_XFER_ALIGN    = 17,
  ALLOC_SIZE_MIN    = 18,
  SYMLINK_MAX       = 19,
  ["2_SYMLINKS"]    = 20,
}

c.RUSAGE = strflag {
  SELF     =  0,
  CHILDREN = -1,
  BOTH     = -2,
  THREAD   =  1,
}

-- waitpid and wait4 pid
c.WAIT = strflag {
  ANY      = -1,
  MYPGRP   = 0,
}

-- virtio functions
c.VIRTIO = strflag {
  PCI_HOST_FEATURES       = 0,
  PCI_GUEST_FEATURES      = 4,
  PCI_QUEUE_PFN           = 8,
  PCI_QUEUE_NUM           = 12,
  PCI_QUEUE_SEL           = 14,
  PCI_QUEUE_NOTIFY        = 16,
  PCI_STATUS              = 18,
  PCI_ISR                 = 19,
  PCI_ISR_CONFIG          = 0x2,
  MSI_CONFIG_VECTOR       = 20,
  MSI_QUEUE_VECTOR        = 22,
  MSI_NO_VECTOR           = 0xffff,
  PCI_ABI_VERSION         = 0,
  PCI_QUEUE_ADDR_SHIFT    = 12,
  PCI_VRING_ALIGN         = 4096,
  -- TODO VIRTIO_PCI_CONFIG_OFF(msix_enabled)     ((msix_enabled) ? 24 : 20)
}

-- from linux/pci_regs.h
c.PCI = strflag {
  VENDOR_ID          = 0x00,
  DEVICE_ID          = 0x02,
  COMMAND            = 0x04,
  STATUS             = 0x06,
  CLASS_REVISION     = 0x08,
  REVISION_ID        = 0x08,
  CLASS_PROG         = 0x09,
  CLASS_DEVICE       = 0x0a,
  CACHE_LINE_SIZE    = 0x0c,
  LATENCY_TIMER      = 0x0d,
  HEADER_TYPE        = 0x0e,
  CACHE_LINE_SIZE    = 0x0c,
  LATENCY_TIMER      = 0x0d,
  HEADER_TYPE        = 0x0e,
  BIST               = 0x0f,
  BASE_ADDRESS_0     = 0x10,
  BASE_ADDRESS_1     = 0x14,
  BASE_ADDRESS_2     = 0x18,
  BASE_ADDRESS_3     = 0x1c,
  BASE_ADDRESS_4     = 0x20,
  BASE_ADDRESS_5     = 0x24,
-- Header type 0 (Normal)
  CARDBUS_CIS        = 0x28,
  SUBSYSTEM_VENDOR_ID= 0x2c,
  SUBSYSTEM_ID       = 0x2e,
  ROM_ADDRESS        = 0x30,
  CAPABILITY_LIST    = 0x34,
  INTERRUPT_LINE     = 0x3c,
  INTERRUPT_PIN      = 0x3d,
  MIN_GNT            = 0x3e,
  MAX_LAT            = 0x3f,
-- Header type 1 (PCI-to-PCI bridges)
  PRIMARY_BUS        = 0x18,
  SECONDARY_BUS      = 0x19,
  SUBORDINATE_BUS    = 0x1a,
  SEC_LATENCY_TIMER  = 0x1b,
  IO_BASE            = 0x1c,
  IO_LIMIT           = 0x1d,
  SEC_STATUS         = 0x1e,
  MEMORY_BASE        = 0x20,
  MEMORY_LIMIT       = 0x22,
  PREF_MEMORY_BASE   = 0x24,
  PREF_MEMORY_LIMIT  = 0x26,
  PREF_BASE_UPPER32  = 0x28,
  PREF_LIMIT_UPPER32 = 0x2c,
  IO_BASE_UPPER16    = 0x30,
  IO_LIMIT_UPPER16   = 0x32,
  ROM_ADDRESS1       = 0x38,
  BRIDGE_CONTROL     = 0x3e,
-- Header type 2 (CardBus bridges)
  CB_CAPABILITY_LIST = 0x14,
  CB_SEC_STATUS      = 0x16,
  CB_PRIMARY_BUS     = 0x18,
  CB_CARD_BUS        = 0x19,
  CB_SUBORDINATE_BUS = 0x1a,
  CB_LATENCY_TIMER   = 0x1b,
  CB_MEMORY_BASE_0   = 0x1c,
  CB_MEMORY_LIMIT_0  = 0x20,
  CB_MEMORY_BASE_1   = 0x24,
  CB_MEMORY_LIMIT_1  = 0x28,
  CB_IO_BASE_0       = 0x2c,
  CB_IO_BASE_0_HI    = 0x2e,
  CB_IO_LIMIT_0      = 0x30,
  CB_IO_LIMIT_0_HI   = 0x32,
  CB_IO_BASE_1       = 0x34,
  CB_IO_BASE_1_HI    = 0x36,
  CB_IO_LIMIT_1      = 0x38,
  CB_IO_LIMIT_1_HI   = 0x3a,
  CB_BRIDGE_CONTROL  = 0x3e,
  CB_SUBSYSTEM_VENDOR_ID = 0x40,
  CB_SUBSYSTEM_ID        = 0x42,
  CB_LEGACY_MODE_BASE    = 0x44,
}

-- unclear how best to group these, maybe just put everything in PCI and let app fix it
c.PCI_BASE_ADDRESS = strflag {
  SPACE         = 0x01,
  SPACE_IO      = 0x01,
  SPACE_MEMORY  = 0x00,
  MEM_TYPE_MASK = 0x06,
  MEM_TYPE_32   = 0x00,
  MEM_TYPE_1M   = 0x02,
  MEM_TYPE_64   = 0x04,
  MEM_PREFETCH  = 0x08,
  --MEM_MASK      (~0x0fUL)
  --IO_MASK       (~0x03UL)
}

c.TCP = strflag {
  NODELAY            = 1,
  MAXSEG             = 2,
  CORK               = 3,
  KEEPIDLE           = 4,
  KEEPINTVL          = 5,
  KEEPCNT            = 6,
  SYNCNT             = 7,
  LINGER2            = 8,
  DEFER_ACCEPT       = 9,
  WINDOW_CLAMP       = 10,
  INFO               = 11,
  QUICKACK           = 12,
  CONGESTION         = 13,
  MD5SIG             = 14,
  THIN_LINEAR_TIMEOUTS= 16,
  THIN_DUPACK        = 17,
  USER_TIMEOUT       = 18,
  REPAIR             = 19,
  REPAIR_QUEUE       = 20,
  QUEUE_SEQ          = 21,
  REPAIR_OPTIONS     = 22,
  FASTOPEN           = 23,
  TIMESTAMP          = 24,
}

-- ipv6 sockopts
c.IPV6 = strflag {
  ADDRFORM          = 1,
  ["2292PKTINFO"]   = 2,
  ["2292HOPOPTS"]   = 3,
  ["2292DSTOPTS"]   = 4,
  ["2292RTHDR"]     = 5,
  ["2292PKTOPTIONS"]= 6,
  CHECKSUM          = 7,
  ["2292HOPLIMIT"]  = 8,
  NEXTHOP           = 9,
  AUTHHDR           = 10,
  FLOWINFO          = 11,
  UNICAST_HOPS      = 16,
  MULTICAST_IF      = 17,
  MULTICAST_HOPS    = 18,
  MULTICAST_LOOP    = 19,
  ADD_MEMBERSHIP    = 20,
  DROP_MEMBERSHIP   = 21,
  ROUTER_ALERT      = 22,
  MTU_DISCOVER      = 23,
  MTU               = 24,
  RECVERR           = 25,
  V6ONLY            = 26,
  JOIN_ANYCAST      = 27,
  LEAVE_ANYCAST     = 28,
}

-- need to use tobit to make sure within int range
c.LINUX_REBOOT = strflag {
  MAGIC1    = tobit(0xfee1dead),
  MAGIC2    = tobit(672274793),
  MAGIC2A   = tobit(85072278),
  MAGIC2B   = tobit(369367448),
  MAGIC2C   = tobit(537993216),
}

c.GRND = multiflags {
  NONBLOCK = 0x0001,
  RANDOM   = 0x0002,
}

c.MFD = multiflags {
  CLOEXEC            = 0x0001,
  ALLOW_SEALING      = 0x0002,
}

return c

