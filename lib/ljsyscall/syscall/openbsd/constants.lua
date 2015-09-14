-- tables of constants for NetBSD

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, select = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, select

local abi = require "syscall.abi"

local h = require "syscall.helpers"

local bit = require "syscall.bit"

local version = require "syscall.openbsd.version".version

local octal, multiflags, charflags, swapflags, strflag, atflag, modeflags
  = h.octal, h.multiflags, h.charflags, h.swapflags, h.strflag, h.atflag, h.modeflags

local ffi = require "ffi"

local function charp(n) return ffi.cast("char *", n) end

local c = {}

c.errornames = require "syscall.openbsd.errors"

c.STD = strflag {
  IN_FILENO = 0,
  OUT_FILENO = 1,
  ERR_FILENO = 2,
  IN = 0,
  OUT = 1,
  ERR = 2,
}

c.E = strflag {
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
  DEADLK        = 11,
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
  AGAIN         = 35,
  INPROGRESS    = 36,
  ALREADY       = 37,
  NOTSOCK       = 38,
  DESTADDRREQ   = 39,
  MSGSIZE       = 40,
  PROTOTYPE     = 41,
  NOPROTOOPT    = 42,
  PROTONOSUPPORT= 43,
  SOCKTNOSUPPORT= 44,
  OPNOTSUPP     = 45,
  PFNOSUPPORT   = 46,
  AFNOSUPPORT   = 47,
  ADDRINUSE     = 48,
  ADDRNOTAVAIL  = 49,
  NETDOWN       = 50,
  NETUNREACH    = 51,
  NETRESET      = 52,
  CONNABORTED   = 53,
  CONNRESET     = 54,
  NOBUFS        = 55,
  ISCONN        = 56,
  NOTCONN       = 57,
  SHUTDOWN      = 58,
  TOOMANYREFS   = 59,
  TIMEDOUT      = 60,
  CONNREFUSED   = 61,
  LOOP          = 62,
  NAMETOOLONG   = 63,
  HOSTDOWN      = 64,
  HOSTUNREACH   = 65,
  NOTEMPTY      = 66,
  PROCLIM       = 67,
  USERS         = 68,
  DQUOT         = 69,
  STALE         = 70,
  REMOTE        = 71,
  BADRPC        = 72,
  BADRPC        = 72,
  RPCMISMATCH   = 73,
  PROGUNAVAIL   = 74,
  PROGMISMATCH  = 75,
  PROCUNAVAIL   = 76,
  NOLCK         = 77,
  NOSYS         = 78,
  FTYPE         = 79,
  AUTH          = 80,
  NEEDAUTH      = 81,
  IPSEC         = 82,
  NOATTR        = 83,
  ILSEQ         = 84,
  NOMEDIUM      = 85,
  MEDIUMTYPE    = 86,
  OVERFLOW      = 87,
  CANCELED      = 88,
  IDRM          = 89,
  NOMSG         = 90,
  NOTSUP        = 91,
}

-- alternate names
c.EALIAS = {
  WOULDBLOCK    = c.E.AGAIN,
}

c.AF = strflag {
  UNSPEC      = 0,
  LOCAL       = 1,
  INET        = 2,
  IMPLINK     = 3,
  PUP         = 4,
  CHAOS       = 5,
  ISO         = 7,
  ECMA        = 8,
  DATAKIT     = 9,
  CCITT       = 10,
  SNA         = 11,
  DECNET      = 12,
  DLI         = 13,
  LAT         = 14,
  HYLINK      = 15,
  APPLETALK   = 16,
  ROUTE       = 17,
  LINK        = 18,
-- pseudo_AF_XTP   19
  COIP        = 20,
  CNT         = 21,
-- pseudo_AF_RTIP  22
  IPX         = 23,
  INET6       = 24,
-- pseudo_AF_PIP   25
  ISDN        = 26,
  NATM        = 27,
  ENCAP       = 28,
  SIP         = 29,
  KEY         = 30,
-- pseudo_AF_HDRCMPLT 31
  BLUETOOTH   = 32,
  MPLS        = 33,
-- pseudo_AF_PFLOW 34
-- pseudo_AF_PIPEX 35
}

c.AF.UNIX = c.AF.LOCAL
c.AF.OSI = c.AF.ISO
c.AF.E164 = c.AF.ISDN

c.O = multiflags {
  RDONLY      = 0x0000,
  WRONLY      = 0x0001,
  RDWR        = 0x0002,
  ACCMODE     = 0x0003,
  NONBLOCK    = 0x0004,
  APPEND      = 0x0008,
  SHLOCK      = 0x0010,
  EXLOCK      = 0x0020,
  ASYNC       = 0x0040,
  FSYNC       = 0x0080,
  SYNC        = 0x0080,
  NOFOLLOW    = 0x0100,
  CREAT       = 0x0200,
  TRUNC       = 0x0400,
  EXCL        = 0x0800,
  NOCTTY      = 0x8000,
  CLOEXEC     = 0x10000,
  DIRECTORY   = 0x20000,
}

-- for pipe2, selected flags from c.O
c.OPIPE = multiflags {
  NONBLOCK  = 0x0004,
  CLOEXEC   = 0x10000,
}

-- sigaction, note renamed SIGACT from SIG_
c.SIGACT = strflag {
  ERR = -1,
  DFL =  0,
  IGN =  1,
  HOLD = 3,
}

c.SIG = strflag {
  HUP = 1,
  INT = 2,
  QUIT = 3,
  ILL = 4,
  TRAP = 5,
  ABRT = 6,
  EMT = 7,
  FPE = 8,
  KILL = 9,
  BUS = 10,
  SEGV = 11,
  SYS = 12,
  PIPE = 13,
  ALRM = 14,
  TERM = 15,
  URG = 16,
  STOP = 17,
  TSTP = 18,
  CONT = 19,
  CHLD = 20,
  TTIN = 21,
  TTOU = 22,
  IO   = 23,
  XCPU = 24,
  XFSZ = 25,
  VTALRM = 26,
  PROF = 27,
  WINCH = 28,
  INFO = 29,
  USR1 = 30,
  USR2 = 31,
  THR = 32,
}

c.EXIT = strflag {
  SUCCESS = 0,
  FAILURE = 1,
}

c.OK = charflags {
  F = 0,
  X = 0x01,
  W = 0x02,
  R = 0x04,
}

c.MODE = modeflags {
  SUID = octal('04000'),
  SGID = octal('02000'),
  STXT = octal('01000'),
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

c.SEEK = strflag {
  SET  = 0,
  CUR  = 1,
  END  = 2,
}

c.SOCK = multiflags {
  STREAM    = 1,
  DGRAM     = 2,
  RAW       = 3,
  RDM       = 4,
  SEQPACKET = 5,
}

if version >= 201505 then
  c.SOCK.NONBLOCK  = 0x4000
  c.SOCK.CLOEXEC   = 0x8000
end

c.SOL = strflag {
  SOCKET    = 0xffff,
}

c.POLL = multiflags {
  IN         = 0x0001,
  PRI        = 0x0002,
  OUT        = 0x0004,
  RDNORM     = 0x0040,
  RDBAND     = 0x0080,
  WRBAND     = 0x0100,
  ERR        = 0x0008,
  HUP        = 0x0010,
  NVAL       = 0x0020,
}

c.POLL.WRNORM = c.POLL.OUT

c.AT_FDCWD = atflag {
  FDCWD = -100,
}

c.AT = multiflags {
  EACCESS             = 0x01,
  SYMLINK_NOFOLLOW    = 0x02,
  SYMLINK_FOLLOW      = 0x04,
  REMOVEDIR           = 0x08,
}

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
  STXT  = octal('0001000'),
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

c.S_I.READ  = c.S_I.RUSR
c.S_I.WRITE = c.S_I.WUSR
c.S_I.EXEC  = c.S_I.XUSR

c.PROT = multiflags {
  NONE  = 0x0,
  READ  = 0x1,
  WRITE = 0x2,
  EXEC  = 0x4,
}

c.MAP = multiflags {
  SHARED     = 0x0001,
  PRIVATE    = 0x0002,
  FILE       = 0x0000,
  FIXED      = 0x0010,
  ANON       = 0x1000,
}

if version < 201411 then -- defined in 5.6 but as zero so no effect
  c.MAP.RENAME       = 0x0020
  c.MAP.NORESERVE    = 0x0040
  c.MAP.HASSEMAPHORE = 0x0200
end

c.MCL = strflag {
  CURRENT    = 0x01,
  FUTURE     = 0x02,
}

-- flags to `msync'. - note was MS_ renamed to MSYNC_
c.MSYNC = multiflags {
  ASYNC       = 0x01,
  SYNC        = 0x02,
  INVALIDATE  = 0x04,
}

c.MADV = strflag {
  NORMAL      = 0,
  RANDOM      = 1,
  SEQUENTIAL  = 2,
  WILLNEED    = 3,
  DONTNEED    = 4,
  SPACEAVAIL  = 5,
  FREE        = 6,
}

c.IPPROTO = strflag {
  IP             = 0,
  HOPOPTS        = 0,
  ICMP           = 1,
  IGMP           = 2,
  GGP            = 3,
  IPV4           = 4,
  IPIP           = 4,
  TCP            = 6,
  EGP            = 8,
  PUP            = 12,
  UDP            = 17,
  IDP            = 22,
  TP             = 29,
  IPV6           = 41,
  ROUTING        = 43,
  FRAGMENT       = 44,
  RSVP           = 46,
  GRE            = 47,
  ESP            = 50,
  AH             = 51,
  MOBILE         = 55,
  ICMPV6         = 58,
  NONE           = 59,
  DSTOPTS        = 60,
  EON            = 80,
  ETHERIP        = 97,
  ENCAP          = 98,
  PIM            = 103,
  IPCOMP         = 108,
  CARP           = 112,
  MPLS           = 137,
  PFSYNC         = 240,
  RAW            = 255,
}

c.SCM = multiflags {
  RIGHTS     = 0x01,
  TIMESTAMP  = 0x04,
}

c.F = strflag {
  DUPFD       = 0,
  GETFD       = 1,
  SETFD       = 2,
  GETFL       = 3,
  SETFL       = 4,
  GETOWN      = 5,
  SETOWN      = 6,
  GETLK       = 7,
  SETLK       = 8,
  SETLKW      = 9,
  DUPFD_CLOEXEC= 10,
}

c.FD = multiflags {
  CLOEXEC = 1,
}

-- note changed from F_ to FCNTL_LOCK
c.FCNTL_LOCK = strflag {
  RDLCK = 1,
  UNLCK = 2,
  WRLCK = 3,
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
  SH        = 0x01,
  EX        = 0x02,
  NB        = 0x04,
  UN        = 0x08,
}

c.W = multiflags {
  NOHANG      = 1,
  UNTRACED    = 2,
  CONTINUED   = 8,
  STOPPED     = octal "0177",
}

if version < 201405 then
  c.W.ALTSIG = 4
end

-- waitpid and wait4 pid
c.WAIT = strflag {
  ANY      = -1,
  MYPGRP   = 0,
}

c.MSG = multiflags {
  OOB         = 0x1,
  PEEK        = 0x2,
  DONTROUTE   = 0x4,
  EOR         = 0x8,
  TRUNC       = 0x10,
  CTRUNC      = 0x20,
  WAITALL     = 0x40,
  DONTWAIT    = 0x80,
  BCAST       = 0x100,
  MCAST       = 0x200,
  NOSIGNAL    = 0x400,
}

c.PC = strflag {
  LINK_MAX          = 1,
  MAX_CANON         = 2,
  MAX_INPUT         = 3,
  NAME_MAX          = 4,
  PATH_MAX          = 5,
  PIPE_BUF          = 6,
  CHOWN_RESTRICTED  = 7,
  NO_TRUNC          = 8,
  VDISABLE          = 9,
  ["2_SYMLINKS"]    = 10,
  ALLOC_SIZE_MIN    = 11,
  ASYNC_IO          = 12,
  FILESIZEBITS      = 13,
  PRIO_IO           = 14,
  REC_INCR_XFER_SIZE= 15,
  REC_MAX_XFER_SIZE = 16,
  REC_MIN_XFER_SIZE = 17,
  REC_XFER_ALIGN    = 18,
  SYMLINK_MAX       = 19,
  SYNC_IO           = 20,
  TIMESTAMP_RESOLUTION = 21,
}

-- getpriority, setpriority flags
c.PRIO = strflag {
  PROCESS = 0,
  PGRP = 1,
  USER = 2,
  MIN = -20, -- TODO useful to have for other OSs
  MAX = 20,
}

c.RUSAGE = strflag {
  SELF     =  0,
  CHILDREN = -1,
  THREAD   = 1,
}

c.SOMAXCONN = 128

c.SO = strflag {
  DEBUG        = 0x0001,
  ACCEPTCONN   = 0x0002,
  REUSEADDR    = 0x0004,
  KEEPALIVE    = 0x0008,
  DONTROUTE    = 0x0010,
  BROADCAST    = 0x0020,
  USELOOPBACK  = 0x0040,
  LINGER       = 0x0080,
  OOBINLINE    = 0x0100,
  REUSEPORT    = 0x0200,
  TIMESTAMP    = 0x0800,
  BINDANY      = 0x1000,
  SNDBUF       = 0x1001,
  RCVBUF       = 0x1002,
  SNDLOWAT     = 0x1003,
  RCVLOWAT     = 0x1004,
  SNDTIMEO     = 0x1005,
  RCVTIMEO     = 0x1006,
  ERROR        = 0x1007,
  TYPE         = 0x1008,
  NETPROC      = 0x1020,
  RTABLE       = 0x1021,
  PEERCRED     = 0x1022,
  SPLICE       = 0x1023,
}

c.DT = strflag {
  UNKNOWN = 0,
  FIFO = 1,
  CHR = 2,
  DIR = 4,
  BLK = 6,
  REG = 8,
  LNK = 10,
  SOCK = 12,
}

c.IP = strflag {
  OPTIONS            = 1,
  HDRINCL            = 2,
  TOS                = 3,
  TTL                = 4,
  RECVOPTS           = 5,
  RECVRETOPTS        = 6,
  RECVDSTADDR        = 7,
  RETOPTS            = 8,
  MULTICAST_IF       = 9,
  MULTICAST_TTL      = 10,
  MULTICAST_LOOP     = 11,
  ADD_MEMBERSHIP     = 12,
  DROP_MEMBERSHIP    = 13,

  PORTRANGE          = 19,
  AUTH_LEVEL         = 20,
  ESP_TRANS_LEVEL    = 21,
  ESP_NETWORK_LEVEL  = 22,
  IPSEC_LOCAL_ID     = 23,
  IPSEC_REMOTE_ID    = 24,
  IPSEC_LOCAL_CRED   = 25,
  IPSEC_REMOTE_CRED  = 26,
  IPSEC_LOCAL_AUTH   = 27,
  IPSEC_REMOTE_AUTH  = 28,
  IPCOMP_LEVEL       = 29,
  RECVIF             = 30,
  RECVTTL            = 31,
  MINTTL             = 32,
  RECVDSTPORT        = 33,
  PIPEX              = 34,
  RECVRTABLE         = 35,
  IPSECFLOWINFO      = 36,

  RTABLE             = 0x1021,
  DIVERTFL           = 0x1022,
}

-- Baud rates just the identity function  other than EXTA, EXTB TODO check
c.B = strflag {
}

c.CC = strflag {
  VEOF           = 0,
  VEOL           = 1,
  VEOL2          = 2,
  VERASE         = 3,
  VWERASE        = 4,
  VKILL          = 5,
  VREPRINT       = 6,
  VINTR          = 8,
  VQUIT          = 9,
  VSUSP          = 10,
  VDSUSP         = 11,
  VSTART         = 12,
  VSTOP          = 13,
  VLNEXT         = 14,
  VDISCARD       = 15,
  VMIN           = 16,
  VTIME          = 17,
  VSTATUS        = 18,
}

c.IFLAG = multiflags {
  IGNBRK         = 0x00000001,
  BRKINT         = 0x00000002,
  IGNPAR         = 0x00000004,
  PARMRK         = 0x00000008,
  INPCK          = 0x00000010,
  ISTRIP         = 0x00000020,
  INLCR          = 0x00000040,
  IGNCR          = 0x00000080,
  ICRNL          = 0x00000100,
  IXON           = 0x00000200,
  IXOFF          = 0x00000400,
  IXANY          = 0x00000800,
  IMAXBEL        = 0x00002000,
}

c.OFLAG = multiflags {
  OPOST          = 0x00000001,
  ONLCR          = 0x00000002,
  OXTABS         = 0x00000004,
  ONOEOT         = 0x00000008,
  OCRNL          = 0x00000010,
  OLCUC          = 0x00000020,
  ONOCR          = 0x00000040,
  ONLRET         = 0x00000080,
}

c.CFLAG = multiflags {
  CIGNORE        = 0x00000001,
  CSIZE          = 0x00000300,
  CS5            = 0x00000000,
  CS6            = 0x00000100,
  CS7            = 0x00000200,
  CS8            = 0x00000300,
  CSTOPB         = 0x00000400,
  CREAD          = 0x00000800,
  PARENB         = 0x00001000,
  PARODD         = 0x00002000,
  HUPCL          = 0x00004000,
  CLOCAL         = 0x00008000,
  CRTSCTS        = 0x00010000,
  MDMBUF         = 0x00100000,
}

c.CFLAG.CRTS_IFLOW = c.CFLAG.CRTSCTS
c.CFLAG.CCTS_OFLOW = c.CFLAG.CRTSCTS
c.CFLAG.CHWFLOW = c.CFLAG.MDMBUF + c.CFLAG.CRTSCTS

c.LFLAG = multiflags {
  ECHOKE         = 0x00000001,
  ECHOE          = 0x00000002,
  ECHOK          = 0x00000004,
  ECHO           = 0x00000008,
  ECHONL         = 0x00000010,
  ECHOPRT        = 0x00000020,
  ECHOCTL        = 0x00000040,
  ISIG           = 0x00000080,
  ICANON         = 0x00000100,
  ALTWERASE      = 0x00000200,
  IEXTEN         = 0x00000400,
  EXTPROC        = 0x00000800,
  TOSTOP         = 0x00400000,
  FLUSHO         = 0x00800000,
  NOKERNINFO     = 0x02000000,
  PENDIN         = 0x20000000,
  NOFLSH         = 0x80000000,
}

c.TCSA = multiflags { -- this is another odd one, where you can have one flag plus SOFT
  NOW   = 0,
  DRAIN = 1,
  FLUSH = 2,
  SOFT  = 0x10,
}

-- tcflush(), renamed from TC to TCFLUSH
c.TCFLUSH = strflag {
  IFLUSH  = 1,
  OFLUSH  = 2,
  IOFLUSH = 3,
}

-- termios - tcflow() and TCXONC use these. renamed from TC to TCFLOW
c.TCFLOW = strflag {
  OOFF = 1,
  OON  = 2,
  IOFF = 3,
  ION  = 4,
}

-- for chflags and stat. note these have no prefix
c.CHFLAGS = multiflags {
  UF_NODUMP      = 0x00000001,
  UF_IMMUTABLE   = 0x00000002,
  UF_APPEND      = 0x00000004,
  UF_OPAQUE      = 0x00000008,

  SF_ARCHIVED    = 0x00010000,
  SF_IMMUTABLE   = 0x00020000,
  SF_APPEND      = 0x00040000,
}

c.CHFLAGS.IMMUTABLE = c.CHFLAGS.UF_IMMUTABLE + c.CHFLAGS.SF_IMMUTABLE
c.CHFLAGS.APPEND = c.CHFLAGS.UF_APPEND + c.CHFLAGS.SF_APPEND
c.CHFLAGS.OPAQUE = c.CHFLAGS.UF_OPAQUE

c.TCP = strflag {
  NODELAY     = 0x01,
  MAXSEG      = 0x02,
  MD5SIG      = 0x04,
  SACK_ENABLE = 0x08,
}

c.RB = multiflags {
  AUTOBOOT    = 0,
  ASKNAME     = 0x0001,
  SINGLE      = 0x0002,
  NOSYNC      = 0x0004,
  HALT        = 0x0008,
  INITNAME    = 0x0010,
  DFLTROOT    = 0x0020,
  KDB         = 0x0040,
  RDONLY      = 0x0080,
  DUMP        = 0x0100,
  MINIROOT    = 0x0200,
  CONFIG      = 0x0400,
  TIMEBAD     = 0x0800,
  POWERDOWN   = 0x1000,
  SERCONS     = 0x2000,
  USERREQ     = 0x4000,
}

-- kqueue
c.EV = multiflags {
  ADD      = 0x0001,
  DELETE   = 0x0002,
  ENABLE   = 0x0004,
  DISABLE  = 0x0008,
  ONESHOT  = 0x0010,
  CLEAR    = 0x0020,
  SYSFLAGS = 0xF000,
  FLAG1    = 0x2000,
  EOF      = 0x8000,
  ERROR    = 0x4000,
}

c.EVFILT = strflag {
  READ     = -1,
  WRITE    = -2,
  AIO      = -3,
  VNODE    = -4,
  PROC     = -5,
  SIGNAL   = -6,
  TIMER    = -7,
  SYSCOUNT = 7,
}

c.NOTE = multiflags {
-- read and write
  LOWAT     = 0x0001,
-- vnode
  DELETE    = 0x0001,
  WRITE     = 0x0002,
  EXTEND    = 0x0004,
  ATTRIB    = 0x0008,
  LINK      = 0x0010,
  RENAME    = 0x0020,
  REVOKE    = 0x0040,
-- proc
  EXIT      = 0x80000000,
  FORK      = 0x40000000,
  EXEC      = 0x20000000,
  PCTRLMASK = 0xf0000000,
  PDATAMASK = 0x000fffff,
  TRACK     = 0x00000001,
  TRACKERR  = 0x00000002,
  CHILD     = 0x00000004,
}

c.ITIMER = strflag {
  REAL    = 0,
  VIRTUAL = 1,
  PROF    = 2,
}

c.SA = multiflags {
  ONSTACK   = 0x0001,
  RESTART   = 0x0002,
  RESETHAND = 0x0004,
  NOCLDSTOP = 0x0008,
  NODEFER   = 0x0010,
  NOCLDWAIT = 0x0020,
  SIGINFO   = 0x0040,
}

-- ipv6 sockopts
c.IPV6 = strflag {
  UNICAST_HOPS      = 4,
  MULTICAST_IF      = 9,
  MULTICAST_HOPS    = 10,
  MULTICAST_LOOP    = 11,
  JOIN_GROUP        = 12,
  LEAVE_GROUP       = 13,
  PORTRANGE         = 14,
--ICMP6_FILTER      = 18, -- not namespaced as IPV6
  CHECKSUM          = 26,
  V6ONLY            = 27,
  RTHDRDSTOPTS      = 35,
  RECVPKTINFO       = 36,
  RECVHOPLIMIT      = 37,
  RECVRTHDR         = 38,
  RECVHOPOPTS       = 39,
  RECVDSTOPTS       = 40,
  USE_MIN_MTU       = 42,
  RECVPATHMTU       = 43,
  PATHMTU           = 44,
  PKTINFO           = 46,
  HOPLIMIT          = 47,
  NEXTHOP           = 48,
  HOPOPTS           = 49,
  DSTOPTS           = 50,
  RTHDR             = 51,
  RECVTCLASS        = 57,
  TCLASS            = 61,
  DONTFRAG          = 62,
}

if version < 201405 then
  c.IPV6.SOCKOPT_RESERVED1 = 3
  c.IPV6.FAITH = 29
end

c.CLOCK = strflag {
  REALTIME                 = 0,
  PROCESS_CPUTIME_ID       = 2,
  MONOTONIC                = 3,
  THREAD_CPUTIME_ID        = 4,
}

if version < 201505 then
  c.CLOCK.VIRTUAL = 1
end

if version >= 201505 then
  c.CLOCK.UPTIME = 5
end

c.UTIME = strflag {
  NOW      = -2,
  OMIT     = -1,
}

c.PATH_MAX = 1024

c.CTL = strflag {
  UNSPEC     = 0,
  KERN       = 1,
  VM         = 2,
  FS         = 3,
  NET        = 4,
  DEBUG      = 5,
  HW         = 6,
  MACHDEP    = 7,
  DDB        = 9,
  VFS        = 10,
  MAXID      = 11,
}

c.KERN = strflag {
  OSTYPE            =  1,
  OSRELEASE         =  2,
  OSREV             =  3,
  VERSION           =  4,
  MAXVNODES         =  5,
  MAXPROC           =  6,
  MAXFILES          =  7,
  ARGMAX            =  8,
  SECURELVL         =  9,
  HOSTNAME          = 10,
  HOSTID            = 11,
  CLOCKRATE         = 12,
  PROF              = 16,
  POSIX1            = 17,
  NGROUPS           = 18,
  JOB_CONTROL       = 19,
  SAVED_IDS         = 20,
  BOOTTIME          = 21,
  DOMAINNAME        = 22,
  MAXPARTITIONS     = 23,
  RAWPARTITION      = 24,
  MAXTHREAD         = 25,
  NTHREADS          = 26,
  OSVERSION         = 27,
  SOMAXCONN         = 28,
  SOMINCONN         = 29,
  USERMOUNT         = 30,
  RND               = 31,
  NOSUIDCOREDUMP    = 32,
  FSYNC             = 33,
  SYSVMSG           = 34,
  SYSVSEM           = 35,
  SYSVSHM           = 36,
  ARND              = 37,
  MSGBUFSIZE        = 38,
  MALLOCSTATS       = 39,
  CPTIME            = 40,
  NCHSTATS          = 41,
  FORKSTAT          = 42,
  NSELCOLL          = 43,
  TTY               = 44,
  CCPU              = 45,
  FSCALE            = 46,
  NPROCS            = 47,
  MSGBUF            = 48,
  POOL              = 49,
  STACKGAPRANDOM    = 50,
  SYSVIPC_INFO      = 51,
  SPLASSERT         = 54,
  PROC_ARGS         = 55,
  NFILES            = 56,
  TTYCOUNT          = 57,
  NUMVNODES         = 58,
  MBSTAT            = 59,
  SEMINFO           = 61,
  SHMINFO           = 62,
  INTRCNT           = 63,
  WATCHDOG          = 64,
  EMUL              = 65,
  PROC              = 66,
  MAXCLUSTERS       = 67,
  EVCOUNT           = 68,
  TIMECOUNTER       = 69,
  MAXLOCKSPERUID    = 70,
  CPTIME2           = 71,
  CACHEPCT          = 72,
  FILE              = 73,
  CONSDEV           = 75,
  NETLIVELOCKS      = 76,
  POOL_DEBUG        = 77,
  PROC_CWD          = 78,
}

if version < 201405 then
  c.KERN.FILE = 15
  c.KERN.FILE2 = 73
end

if version >= 201411 then
  c.KERN.PROC_NOBROADCASTKILL = 79
end

if version < 201505 then
  c.KERN.VNODE = 13
  c.KERN.USERCRYPTO = 52
  c.KERN.CRYPTODEVALLOWSOFT = 53
  c.KERN.USERASYMCRYPTO = 60
end

return c

