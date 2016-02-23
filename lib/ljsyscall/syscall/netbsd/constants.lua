-- tables of constants for NetBSD

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local abi = require "syscall.abi"

local h = require "syscall.helpers"

local bit = require "syscall.bit"

local octal, multiflags, charflags, swapflags, strflag, atflag, modeflags
  = h.octal, h.multiflags, h.charflags, h.swapflags, h.strflag, h.atflag, h.modeflags

local c = {}

c.errornames = require "syscall.netbsd.errors"

c.SYS = require "syscall.netbsd.nr".SYS

c.IFNAMSIZ = 16

c.STD = strflag {
  IN_FILENO = 0,
  OUT_FILENO = 1,
  ERR_FILENO = 2,
  IN = 0,
  OUT = 1,
  ERR = 2,
}

c.PATH_MAX = 1024

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
  DEADLK	= 11,
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
  AGAIN		= 35,
  INPROGRESS	= 36,
  ALREADY	= 37,
  NOTSOCK	= 38,
  DESTADDRREQ	= 39,
  MSGSIZE	= 40,
  PROTOTYPE	= 41,
  NOPROTOOPT	= 42,
  PROTONOSUPPORT= 43,
  SOCKTNOSUPPORT= 44,
  OPNOTSUPP	= 45,
  PFNOSUPPORT	= 46,
  AFNOSUPPORT	= 47,
  ADDRINUSE	= 48,
  ADDRNOTAVAIL	= 49,
  NETDOWN	= 50,
  NETUNREACH	= 51,
  NETRESET	= 52,
  CONNABORTED	= 53,
  CONNRESET	= 54,
  NOBUFS	= 55,
  ISCONN	= 56,
  NOTCONN	= 57,
  SHUTDOWN	= 58,
  TOOMANYREFS	= 59,
  TIMEDOUT	= 60,
  CONNREFUSED	= 61,
  LOOP		= 62,
  NAMETOOLONG	= 63,
  HOSTDOWN	= 64,
  HOSTUNREACH	= 65,
  NOTEMPTY	= 66,
  PROCLIM	= 67,
  USERS		= 68,
  DQUOT		= 69,
  STALE		= 70,
  REMOTE	= 71,
  BADRPC	= 72,
  RPCMISMATCH	= 73,
  PROGUNAVAIL	= 74,
  PROGMISMATCH	= 75,
  PROCUNAVAIL	= 76,
  NOLCK		= 77,
  NOSYS		= 78,
  FTYPE		= 79,
  AUTH		= 80,
  NEEDAUTH	= 81,
  IDRM		= 82,
  NOMSG		= 83,
  OVERFLOW	= 84,
  ILSEQ		= 85,
  NOTSUP	= 86,
  CANCELED	= 87,
  BADMSG	= 88,
  NODATA	= 89,
  NOSR		= 90,
  NOSTR		= 91,
  TIME		= 92,
  NOATTR	= 93,
  MULTIHOP	= 94,
  NOLINK	= 95,
  PROTO		= 96,
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
  NS          = 6,
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
  OROUTE      = 17,
  LINK        = 18,
-- #define pseudo_AF_XTP   19
  COIP        = 20,
  CNT         = 21,
-- #define pseudo_AF_RTIP  22
  IPX         = 23,
  INET6       = 24,
-- pseudo_AF_PIP   25
  ISDN        = 26,
  NATM        = 27,
  ARP         = 28,
-- #define pseudo_AF_KEY   29
-- #define pseudo_AF_HDRCMPLT 30
  BLUETOOTH   = 31,
  IEEE80211   = 32,
  MPLS        = 33,
  ROUTE       = 34,
}

c.AF.UNIX = c.AF.LOCAL
c.AF.OSI = c.AF.ISO
c.AF.E164 = c.AF.ISDN

c.O = multiflags {
  RDONLY      = 0x00000000,
  WRONLY      = 0x00000001,
  RDWR        = 0x00000002,
  ACCMODE     = 0x00000003,
  NONBLOCK    = 0x00000004,
  APPEND      = 0x00000008,
  SHLOCK      = 0x00000010,
  EXLOCK      = 0x00000020,
  ASYNC       = 0x00000040,
  NOFOLLOW    = 0x00000100,
  CREAT       = 0x00000200,
  TRUNC       = 0x00000400,
  EXCL        = 0x00000800,
  NOCTTY      = 0x00008000,
  DSYNC       = 0x00010000,
  RSYNC       = 0x00020000,
  ALT_IO      = 0x00040000,
  DIRECT      = 0x00080000,
  DIRECTORY   = 0x00200000,
  CLOEXEC     = 0x00400000,
  SEARCH      = 0x00800000,
  NOSIGPIPE   = 0x01000000,
}

-- sigaction, note renamed SIGACT from SIG_
c.SIGACT = strflag {
  ERR = -1,
  DFL =  0,
  IGN =  1,
  HOLD = 3,
}

c.SIGEV = strflag {
  NONE      = 0,
  SIGNAL    = 1,
  THREAD    = 2,
  SA        = 3,
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
  PWR = 32,
}

c.SIG.IOT = c.SIG.ABRT

-- sigprocmask note renaming of SIG to SIGPM
c.SIGPM = strflag {
  BLOCK     = 1,
  UNBLOCK   = 2,
  SETMASK   = 3,
}

c.SA = multiflags {
  ONSTACK   = 0x0001,
  RESTART   = 0x0002,
  RESETHAND = 0x0004,
  NOCLDSTOP = 0x0008,
  NODEFER   = 0x0010,
  NOCLDWAIT = 0x0020,
  SIGINFO   = 0x0040,
  NOKERNINFO= 0x0080,
}

c.EXIT = strflag {
  SUCCESS = 0,
  FAILURE = 1,
}

c.OK = charflags {
  R = 4,
  W = 2,
  X = 1,
  F = 0,
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
  SET = 0,
  CUR = 1,
  END = 2,
}

c.SOCK = multiflags {
  STREAM    = 1,
  DGRAM     = 2,
  RAW       = 3,
  RDM       = 4,
  SEQPACKET = 5,

  CLOEXEC   = 0x10000000,
  NONBLOCK  = 0x20000000,
  NOSIGPIPE = 0x40000000,
  FLAGS_MASK= 0xf0000000,
}

c.SOL = strflag {
  SOCKET    = 0xffff,
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
  IPV6_ICMP      = 58,
  ICMPV6         = 58,
  NONE           = 59,
  DSTOPTS        = 60,
  EON            = 80,
  ETHERIP        = 97,
  ENCAP          = 98,
  PIM            = 103,
  IPCOMP         = 108,
  VRRP           = 112,
  CARP           = 112,
  PFSYNC         = 240,
  RAW            = 255,
}

c.MSG = multiflags {
  OOB             = 0x0001,
  PEEK            = 0x0002,
  DONTROUTE       = 0x0004,
  EOR             = 0x0008,
  TRUNC           = 0x0010,
  CTRUNC          = 0x0020,
  WAITALL         = 0x0040,
  DONTWAIT        = 0x0080,
  BCAST           = 0x0100,
  MCAST           = 0x0200,
  NOSIGNAL        = 0x0400,
  CMSG_CLOEXEC    = 0x0800,
  NBIO            = 0x1000,
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
  CLOSEM      = 10,
  MAXFD       = 11,
  DUPFD_CLOEXEC= 12,
  GETNOSIGPIPE= 13,
  SETNOSIGPIPE= 14,
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

c.S_I = modeflags {
  FMT   = octal('0170000'),
  FWHT  = octal('0160000'),
  FSOCK = octal('0140000'),
  FLNK  = octal('0120000'),
  FREG  = octal('0100000'),
  FBLK  = octal('0060000'),
  FDIR  = octal('0040000'),
  FCHR  = octal('0020000'),
  FIFO  = octal('0010000'),
  SUID  = octal('0004000'),
  SGID  = octal('0002000'),
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

c.SOMAXCONN = 128

c.SHUT = strflag {
  RD   = 0,
  WR   = 1,
  RDWR = 2,
}

c.MNT = multiflags {
  RDONLY      = 0x00000001,
  SYNCHRONOUS = 0x00000002,
  NOEXEC      = 0x00000004,
  NOSUID      = 0x00000008,
  NODEV       = 0x00000010,
  UNION       = 0x00000020,
  ASYNC       = 0x00000040,
  NOCOREDUMP  = 0x00008000,
  RELATIME    = 0x00020000,
  FORCE       = 0x00080000,
  IGNORE      = 0x00100000,
  EXTATTR     = 0x01000000,
  LOG         = 0x02000000,
  NOATIME     = 0x04000000,
  SYMPERM     = 0x20000000,
  NODEVMTIME  = 0x40000000,
  SOFTDEP     = 0x80000000,

  EXRDONLY    = 0x00000080,
  EXPORTED    = 0x00000100,
  DEFEXPORTED = 0x00000200,
  EXPORTANON  = 0x00000400,
  EXKERB      = 0x00000800,
  EXNORESPORT = 0x08000000,
  EXPUBLIC    = 0x10000000,

  LOCAL       = 0x00001000,
  QUOTA       = 0x00002000,
  ROOTFS      = 0x00004000,

  UPDATE      = 0x00010000,
  RELOAD      = 0x00040000,
  FORCE       = 0x00080000,
  GETARGS     = 0x00400000,
}

c.VFSMNT = strflag { -- note renamed, for vfs_sync() and getvfsstat() (also specified as ST_)
  WAIT       = 1,
  NOWAIT     = 2,
  LAZY       = 3,
}

c.RB = multiflags {
  ASKNAME     = 0x00000001,
  SINGLE      = 0x00000002,
  NOSYNC      = 0x00000004,
  HALT        = 0x00000008,
  INITNAME    = 0x00000010,
  KDB         = 0x00000040,
  RDONLY      = 0x00000080,
  DUMP        = 0x00000100,
  MINIROOT    = 0x00000200,
  STRING      = 0x00000400,
  USERCONF    = 0x00001000,
}

c.RB.POWERDOWN = c.RB.HALT + 0x800

c.TMPFS_ARGS = strflag {
  VERSION = 1,
}

c.MODULE_CLASS = strflag {
  ANY = 0,
  MISC = 1,
  VFS = 2,
  DRIVER = 3,
  EXEC = 4,
  SECMODEL = 5,
}

c.MODULE_SOURCE = strflag {
  KERNEL = 0,
  BOOT = 1,
  FILESYS = 2,
}

c.MODULE_CMD = strflag {
  INIT = 0,
  FINI = 1,
  STAT = 2,
  AUTOUNLOAD = 3,
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
  WHT = 14,
}

c.UTIME = strflag {
  NOW  = bit.lshift(1, 30) - 1,
  OMIT = bit.lshift(1, 30) - 2,
}

-- for pipe2, selected flags from c.O
c.OPIPE = multiflags {
  NONBLOCK  = 0x00000004,
  CLOEXEC   = 0x00400000,
  NOSIGPIPE = 0x01000000,
}

c.PROT = multiflags {
  NONE  = 0x0,
  READ  = 0x1,
  WRITE = 0x2,
  EXEC  = 0x4,
}

local function map_aligned(n) return bit.lshift(n, 24) end

c.MAP = multiflags {
  SHARED     = 0x0001,
  PRIVATE    = 0x0002,
  FILE       = 0x0000,
  FIXED      = 0x0010,
  RENAME     = 0x0020,
  NORESERVE  = 0x0040,
  INHERIT    = 0x0080,
  HASSEMAPHORE= 0x0200,
  TRYFIXED   = 0x0400,
  WIRED      = 0x0800,
  ANON       = 0x1000,
  STACK      = 0x2000,
  ALIGNMENT_64KB   = map_aligned(16),
  ALIGNMENT_16MB   = map_aligned(24),
  ALIGNMENT_4GB    = map_aligned(32),
  ALIGNMENT_1TB    = map_aligned(40),
  ALIGNMENT_256TB  = map_aligned(48),
  ALIGNMENT_64PB   = map_aligned(56),
}

c.MCL = strflag {
  CURRENT    = 0x01,
  FUTURE     = 0x02,
}

-- flags to `msync'. - note was MS_ renamed to MSYNC_
c.MSYNC = multiflags {
  ASYNC       = 0x01,
  INVALIDATE  = 0x02,
  SYNC        = 0x04,
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

c.IFF = multiflags {
  UP          = 0x0001,
  BROADCAST   = 0x0002,
  DEBUG       = 0x0004,
  LOOPBACK    = 0x0008,
  POINTOPOINT = 0x0010,
  NOTRAILERS  = 0x0020,
  RUNNING     = 0x0040,
  NOARP       = 0x0080,
  PROMISC     = 0x0100,
  ALLMULTI    = 0x0200,
  OACTIVE     = 0x0400,
  SIMPLEX     = 0x0800,
  LINK0       = 0x1000,
  LINK1       = 0x2000,
  LINK2       = 0x4000,
  MULTICAST   = 0x8000,
}

c.IFF.CANTCHANGE = c.IFF.BROADCAST + c.IFF.POINTOPOINT + c.IFF.RUNNING + c.IFF.OACTIVE + 
                   c.IFF.SIMPLEX + c.IFF.MULTICAST + c.IFF.ALLMULTI + c.IFF.PROMISC

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
  RECVIF             = 20,
  ERRORMTU           = 21,
  IPSEC_POLICY       = 22,
  RECVTTL            = 23,
  MINTTL             = 24,
}

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
  NOSIGPIPE    = 0x0800,
  ACCEPTFILTER = 0x1000,
  TIMESTAMP    = 0x2000,
  SNDBUF       = 0x1001,
  RCVBUF       = 0x1002,
  SNDLOWAT     = 0x1003,
  RCVLOWAT     = 0x1004,
  ERROR        = 0x1007,
  TYPE         = 0x1008,
  OVERFLOWED   = 0x1009,
  NOHEADER     = 0x100a,
  SNDTIMEO     = 0x100b,
  RCVTIMEO     = 0x100c,
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

-- for chflags and stat. note these have no prefix
c.CHFLAGS = multiflags {
  UF_IMMUTABLE   = 0x00000002,
  UF_APPEND      = 0x00000004,
  UF_OPAQUE      = 0x00000008,
  SF_ARCHIVED    = 0x00010000,
  SF_IMMUTABLE   = 0x00020000,
  SF_APPEND      = 0x00040000,
  SF_SNAPSHOT    = 0x00200000,
  SF_LOG         = 0x00400000,
  SF_SNAPINVAL   = 0x00800000,
}

c.CHFLAGS.IMMUTABLE = c.CHFLAGS.UF_IMMUTABLE -- common forms
c.CHFLAGS.APPEND = c.CHFLAGS.UF_APPEND
c.CHFLAGS.OPAQUE = c.CHFLAGS.UF_OPAQUE

c.PC = strflag {
  LINK_MAX          =  1,
  MAX_CANON         =  2,
  MAX_INPUT         =  3,
  NAME_MAX          =  4,
  PATH_MAX          =  5,
  PIPE_BUF          =  6,
  CHOWN_RESTRICTED  =  7,
  NO_TRUNC          =  8,
  VDISABLE          =  9,
  SYNC_IO           = 10,
  FILESIZEBITS      = 11,
  SYMLINK_MAX       = 12,
  ["2_SYMLINKS"]    = 13,
  ACL_EXTENDED      = 14,
  MIN_HOLE_SIZE     = 15,
}

-- constants for fsync_range - note complex rename from FDATASYNC to FSYNC.DATA
c.FSYNC = multiflags {
  DATA = 0x0010,
  FILE = 0x0020,
  DISK = 0x0040,
}

-- Baud rates just the identity function in NetBSD...
c.B = strflag {}

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
  ONOCR          = 0x00000020,
  ONLRET         = 0x00000040,
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
  CDTRCTS        = 0x00020000,
  MDMBUF         = 0x00100000,
}

c.CFLAG.CRTS_IFLOW = c.CFLAG.CRTSCTS
c.CFLAG.CCTS_OFLOW = c.CFLAG.CRTSCTS
c.CFLAG.CHWFLOW    = c.CFLAG.MDMBUF + c.CFLAG.CRTSCTS + c.CFLAG.CDTRCTS

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
  READ     = 0,
  WRITE    = 1,
  AIO      = 2,
  VNODE    = 3,
  PROC     = 4,
  SIGNAL   = 5,
  TIMER    = 6,
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

c.RUSAGE = strflag {
  SELF     =  0,
  CHILDREN = -1,
}

-- getpriority, setpriority flags
c.PRIO = strflag {
  PROCESS = 0,
  PGRP = 1,
  USER = 2,
}

c.W = multiflags {
  NOHANG      = 0x00000001,
  UNTRACED    = 0x00000002,
  ALTSIG      = 0x00000004,
  ALLSIG      = 0x00000008,
  NOWAIT      = 0x00010000,
  NOZOMBIE    = 0x00020000,
  OPTSCHECKED = 0x00040000,
}

c.W.WCLONE = c.W.WALTSIG -- __WCLONE
c.W.WALL   = c.W.WALLSIG -- __WALL

-- waitpid and wait4 pid
c.WAIT = strflag {
  ANY      = -1,
  MYPGRP   = 0,
}

c.AT_FDCWD = atflag {
  FDCWD = -100,
}

c.AT = multiflags {
  EACCESS          = 0x100,
  SYMLINK_NOFOLLOW = 0x200,
  SYMLINK_FOLLOW   = 0x400,
  REMOVEDIR        = 0x800,
}

c.KTR = strflag {
  SYSCALL  = 1,
  SYSRET   = 2,
  NAMEI    = 3,
  GENIO    = 4,
  PSIG     = 5,
  CSW      = 6,
  EMUL     = 7,
  USER     = 8,
  EXEC_ARG = 10,
  EXEC_ENV = 11,
  SAUPCALL = 13, 
  MIB      = 14,
  EXEC_FD  = 15,
}

c.KTRFAC = multiflags {
  MASK       = 0x00ffffff,
  SYSCALL    = bit.lshift(1, c.KTR.SYSCALL),
  SYSRET     = bit.lshift(1, c.KTR.SYSRET),
  NAMEI      = bit.lshift(1, c.KTR.NAMEI),
  GENIO      = bit.lshift(1, c.KTR.GENIO),
  PSIG       = bit.lshift(1, c.KTR.PSIG),
  CSW        = bit.lshift(1, c.KTR.CSW),
  EMUL       = bit.lshift(1, c.KTR.EMUL),
  USER       = bit.lshift(1, c.KTR.USER),
  EXEC_ARG   = bit.lshift(1, c.KTR.EXEC_ARG),
  EXEC_ENV   = bit.lshift(1, c.KTR.EXEC_ENV),
--SAUPCALL   = bit.lshift(1, c.KTR.SAUPCALL), -- appears to be gone in NetBSD 7
  MIB        = bit.lshift(1, c.KTR.MIB),
  EXEC_FD    = bit.lshift(1, c.KTR.EXEC_FD),
  PERSISTENT = 0x80000000,
  INHERIT    = 0x40000000,
  TRC_EMUL   = 0x10000000,
  VER_MASK   = 0x0f000000,
  V0         = bit.lshift(0, 24),
  V1         = bit.lshift(1, 24),
  V2         = bit.lshift(2, 24),
}

c.KTROP = multiflags {
  SET              = 0,
  CLEAR            = 1,
  CLEARFILE        = 2,
  DESCEND          = 4,
}

-- enum uio
c.UIO = strflag {
  READ = 0,
  WRITE = 1,
}

c.SCM = multiflags {
  RIGHTS     = 0x01,
--           = 0x02,
  CREDS      = 0x04,
  TIMESTAMP  = 0x08,
}

c.BRDG = strflag {
  ADD      = 0,
  DEL      = 1,
  GIFFLGS  = 2,
  SIFFLGS  = 3,
  SCACHE   = 4,
  GCACHE   = 5,
  GIFS     = 6,
  RTS      = 7,
  SADDR    = 8,
  STO      = 9,
  GTO      = 10,
  DADDR    = 11,
  FLUSH    = 12,
  GPRI     = 13,
  SPRI     = 14,
  GHT      = 15,
  SHT      = 16,
  GFD      = 17,
  SFD      = 18,
  GMA      = 19,
  SMA      = 20,
  SIFPRIO  = 21,
  SIFCOST  = 22,
  GFILT    = 23,
  SFILT    = 24,
}

c.ND6 = strflag {
  INFINITE_LIFETIME = h.uint32_max,
}

c.TCP = strflag {
  NODELAY    = 1,
  MAXSEG     = 2,
  KEEPIDLE   = 3,
  KEEPINTVL  = 5,
  KEEPCNT    = 6,
  KEEPINIT   = 7,
  MD5SIG     = 0x10,
  CONGCTL    = 0x20,
}

c.ITIMER = strflag {
  REAL    = 0,
  VIRTUAL = 1,
  PROF    = 2,
  MONOTONIC = 3,
}

c.TIMER = strflag {
  RELTIME = 0x0,
  ABSTIME = 0x1,
}

-- ipv6 sockopts
c.IPV6 = strflag {
  SOCKOPT_RESERVED1 = 3,
  UNICAST_HOPS      = 4,
  MULTICAST_IF      = 9,
  MULTICAST_HOPS    = 10,
  MULTICAST_LOOP    = 11,
  JOIN_GROUP        = 12,
  LEAVE_GROUP       = 13,
  PORTRANGE         = 14,
--PORTALGO          = 17, -- netbsd 7 only
--ICMP6_FILTER      = 18, -- not namespaced as IPV6
  CHECKSUM          = 26,
  V6ONLY            = 27,
  IPSEC_POLICY      = 28,
  FAITH             = 29,
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

c.RTF = multiflags {
  UP         = 0x1,
  GATEWAY    = 0x2,
  HOST       = 0x4,
  REJECT     = 0x8,
  DYNAMIC    = 0x10,
  MODIFIED   = 0x20,
  DONE       = 0x40,
  MASK       = 0x80,
  CLONING    = 0x100,
  XRESOLVE   = 0x200,
  LLINFO     = 0x400,
  STATIC     = 0x800,
  BLACKHOLE  = 0x1000,
  CLONED     = 0x2000,
  PROTO2     = 0x4000,
  PROTO1     = 0x8000,
  SRC        = 0x10000,
  ANNOUNCE   = 0x20000,
}

c.RTM = strflag {
  VERSION    = 4,

  ADD        = 0x1,
  DELETE     = 0x2,
  CHANGE     = 0x3,
  GET        = 0x4,
  LOSING     = 0x5,
  REDIRECT   = 0x6,
  MISS       = 0x7,
  LOCK       = 0x8,
  OLDADD     = 0x9,
  OLDDEL     = 0xa,
  RESOLVE    = 0xb,
  NEWADDR    = 0xc,
  DELADDR    = 0xd,
  OOIFINFO   = 0xe,
  OIFINFO    = 0xf,
  IFANNOUNCE = 0x10,
  IEEE80211  = 0x11,
  SETGATE    = 0x12,
  LLINFO_UPD = 0x13,
  IFINFO     = 0x14,
  CHGADDR    = 0x15,
}

c.RTV = multiflags {
  MTU        = 0x1,
  HOPCOUNT   = 0x2,
  EXPIRE     = 0x4,
  RPIPE      = 0x8,
  SPIPE      = 0x10,
  SSTHRESH   = 0x20,
  RTT        = 0x40,
  RTTVAR     = 0x80,
}

c.RTA = multiflags {
  DST        = 0x1,
  GATEWAY    = 0x2,
  NETMASK    = 0x4,
  GENMASK    = 0x8,
  IFP        = 0x10,
  IFA        = 0x20,
  AUTHOR     = 0x40,
  BRD        = 0x80,
  TAG        = 0x100,
}

c.RTAX = strflag {
  DST       = 0,
  GATEWAY   = 1,
  NETMASK   = 2,
  GENMASK   = 3,
  IFP       = 4,
  IFA       = 5,
  AUTHOR    = 6,
  BRD       = 7,
  TAG       = 8,
  MAX       = 9,
}

c.CLOCK = strflag {
  REALTIME           = 0,
  VIRTUAL            = 1,
  PROF               = 2,
  MONOTONIC          = 3,
}

c.EXTATTR_NAMESPACE = strflag {
  USER         = 0x00000001,
  SYSTEM       = 0x00000002,
}

c.XATTR = multiflags {
  CREATE           = 0x01,
  REPLACE          = 0x02,
}

c.AIO = strflag {
  CANCELED         = 0x1,
  NOTCANCELED      = 0x2,
  ALLDONE          = 0x3,
}

c.LIO = strflag {
-- LIO opcodes
  NOP                = 0x0,
  WRITE              = 0x1,
  READ               = 0x2,
-- LIO modes
  NOWAIT             = 0x0,
  WAIT               = 0x1,
}

c.CTLTYPE = strflag {
  NODE    = 1,
  INT     = 2,
  STRING  = 3,
  QUAD    = 4,
  STRUCT  = 5,
  BOOL    = 6,
}

if abi.abi64 then
  c.CTLTYPE.LONG = c.CTLTYPE.QUAD
else
  c.CTLTYPE_LONG = c.CTLTYPE.INT
end

c.CTLFLAG = multiflags {
  READONLY       = 0x00000000,
  READWRITE      = 0x00000070,
  ANYWRITE       = 0x00000080,
  PRIVATE        = 0x00000100,
  PERMANENT      = 0x00000200,
  OWNDATA        = 0x00000400,
  IMMEDIATE      = 0x00000800,
  HEX            = 0x00001000,
  ROOT           = 0x00002000,
  ANYNUMBER      = 0x00004000,
  HIDDEN         = 0x00008000,
  ALIAS          = 0x00010000,
  MMAP           = 0x00020000,
  OWNDESC        = 0x00040000,
  UNSIGNED       = 0x00080000,
}

c.CTL = strflag {
  -- meta
  EOL        = -1,
  QUERY      = -2,
  CREATE     = -3,
  CREATESYM  = -4,
  DESTROY    = -5,
  MMAP       = -6,
  DESCRIBE   = -7,
  -- top level
  UNSPEC     = 0,
  KERN       = 1,
  VM         = 2,
  VFS        = 3,
  NET        = 4,
  DEBUG      = 5,
  HW         = 6,
  MACHDEP    = 7,
  USER       = 8,
  DDB        = 9,
  PROC       = 10,
  VENDOR     = 11,
  EMUL       = 12,
  SECURITY   = 13,
  MAXID      = 14,
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
  VNODE             = 13,
  PROC              = 14,
  FILE              = 15,
  PROF              = 16,
  POSIX1            = 17,
  NGROUPS           = 18,
  JOB_CONTROL       = 19,
  SAVED_IDS         = 20,
  OBOOTTIME         = 21,
  DOMAINNAME        = 22,
  MAXPARTITIONS     = 23,
  RAWPARTITION      = 24,
  NTPTIME           = 25,
  TIMEX             = 26,
  AUTONICETIME      = 27,
  AUTONICEVAL       = 28,
  RTC_OFFSET        = 29,
  ROOT_DEVICE       = 30,
  MSGBUFSIZE        = 31,
  FSYNC             = 32,
  OLDSYSVMSG        = 33,
  OLDSYSVSEM        = 34,
  OLDSYSVSHM        = 35,
  OLDSHORTCORENAME  = 36,
  SYNCHRONIZED_IO   = 37,
  IOV_MAX           = 38,
  MBUF              = 39,
  MAPPED_FILES      = 40,
  MEMLOCK           = 41,
  MEMLOCK_RANGE     = 42,
  MEMORY_PROTECTION = 43,
  LOGIN_NAME_MAX    = 44,
  DEFCORENAME       = 45,
  LOGSIGEXIT        = 46,
  PROC2             = 47,
  PROC_ARGS         = 48,
  FSCALE            = 49,
  CCPU              = 50,
  CP_TIME           = 51,
  OLDSYSVIPC_INFO   = 52,
  MSGBUF            = 53,
  CONSDEV           = 54,
  MAXPTYS           = 55,
  PIPE              = 56,
  MAXPHYS           = 57,
  SBMAX             = 58,
  TKSTAT            = 59,
  MONOTONIC_CLOCK   = 60,
  URND              = 61,
  LABELSECTOR       = 62,
  LABELOFFSET       = 63,
  LWP               = 64,
  FORKFSLEEP        = 65,
  POSIX_THREADS     = 66,
  POSIX_SEMAPHORES  = 67,
  POSIX_BARRIERS    = 68,
  POSIX_TIMERS      = 69,
  POSIX_SPIN_LOCKS  = 70,
  POSIX_READER_WRITER_LOCKS = 71,
  DUMP_ON_PANIC     = 72,
  SOMAXKVA          = 73,
  ROOT_PARTITION    = 74,
  DRIVERS           = 75,
  BUF               = 76,
  FILE2             = 77,
  VERIEXEC          = 78,
  CP_ID             = 79,
  HARDCLOCK_TICKS   = 80,
  ARND              = 81,
  SYSVIPC           = 82,
  BOOTTIME          = 83,
  EVCNT             = 84,
  MAXID             = 85,
}

c.KERN_PIPE = strflag {
  MAXKVASZ          = 1,
  LIMITKVA          = 2,
  MAXBIGPIPES       = 3,
  NBIGPIPES         = 4,
  KVASIZE           = 5,
}

c.KERN_PIPE.MAXLOANKVASZ = c.KERN_PIPE.LIMITKVA -- alternate name TODO move to aliases

c.KERN_TKSTAT = strflag {
  NIN               = 1,
  NOUT              = 2,
  CANCC             = 3,
  RAWCC             = 4,
}

c.HW = strflag {
  MACHINE     =  1,
  MODEL       =  2,
  NCPU        =  3,
  BYTEORDER   =  4,
  PHYSMEM     =  5,
  USERMEM     =  6,
  PAGESIZE    =  7,
  DISKNAMES   =  8,
  IOSTATS     =  9,
  MACHINE_ARCH= 10,
  ALIGNBYTES  = 11,
  CNMAGIC     = 12,
  PHYSMEM64   = 13,
  USERMEM64   = 14,
  IOSTATNAMES = 15,
  NCPUONLINE  = 16,
}

c.VM = strflag {
  METER       = 1,
  LOADAVG     = 2,
  UVMEXP      = 3,
  NKMEMPAGES  = 4,
  UVMEXP2     = 5,
  ANONMIN     = 6,
  EXECMIN     = 7,
  FILEMIN     = 8,
  MAXSLP      = 9,
  USPACE      = 10,
  ANONMAX     = 11,
  EXECMAX     = 12,
  FILEMAX     = 13,
}

c.IPCTL = strflag {
  FORWARDING      =  1,
  SENDREDIRECTS   =  2,
  DEFTTL          =  3,
--DEFMTU          =  4,
  FORWSRCRT       =  5,
  DIRECTEDBCAST   =  6,
  ALLOWSRCRT      =  7,
  SUBNETSARELOCAL =  8,
  MTUDISC         =  9,
  ANONPORTMIN     = 10,
  ANONPORTMAX     = 11,
  MTUDISCTIMEOUT  = 12,
  MAXFLOWS        = 13,
  HOSTZEROBROADCAST = 14,
  GIF_TTL         = 15,
  LOWPORTMIN      = 16,
  LOWPORTMAX      = 17,
  MAXFRAGPACKETS  = 18,
  GRE_TTL         = 19,
  CHECKINTERFACE  = 20,
  IFQ             = 21,
  RANDOMID        = 22,
  LOOPBACKCKSUM   = 23,
  STATS           = 24,
}

c.IPV6CTL = strflag {
  FORWARDING     = 1,
  SENDREDIRECTS  = 2,
  DEFHLIM        = 3,
--DEFMTU         = 4,
  FORWSRCRT      = 5,
  STATS          = 6,
  MRTSTATS       = 7,
  MRTPROTO       = 8,
  MAXFRAGPACKETS = 9,
  SOURCECHECK    = 10,
  SOURCECHECK_LOGINT = 11,
  ACCEPT_RTADV   = 12,
  KEEPFAITH      = 13,
  LOG_INTERVAL   = 14,
  HDRNESTLIMIT   = 15,
  DAD_COUNT      = 16,
  AUTO_FLOWLABEL = 17,
  DEFMCASTHLIM   = 18,
  GIF_HLIM       = 19,
  KAME_VERSION   = 20,
  USE_DEPRECATED = 21,
  RR_PRUNE       = 22,
  V6ONLY         = 24,
  ANONPORTMIN    = 28,
  ANONPORTMAX    = 29,
  LOWPORTMIN     = 30,
  LOWPORTMAX     = 31,
  USE_DEFAULTZONE= 39,
  MAXFRAGS       = 41,
  IFQ            = 42,
  RTADV_MAXROUTES= 43,
  RTADV_NUMROUTES= 44,
}

c.USER = strflag {
  CS_PATH           =  1,
  BC_BASE_MAX       =  2,
  BC_DIM_MAX        =  3,
  BC_SCALE_MAX      =  4,
  BC_STRING_MAX     =  5,
  COLL_WEIGHTS_MAX  =  6,
  EXPR_NEST_MAX     =  7,
  LINE_MAX          =  8,
  RE_DUP_MAX        =  9,
  POSIX2_VERSION    = 10,
  POSIX2_C_BIND     = 11,
  POSIX2_C_DEV      = 12,
  POSIX2_CHAR_TERM  = 13,
  POSIX2_FORT_DEV   = 14,
  POSIX2_FORT_RUN   = 15,
  POSIX2_LOCALEDEF  = 16,
  POSIX2_SW_DEV     = 17,
  POSIX2_UPE        = 18,
  STREAM_MAX        = 19,
  TZNAME_MAX        = 20,
  ATEXIT_MAX        = 21,
}

return c

