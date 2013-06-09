-- tables of constants for BSD

-- TODO add test that we do not reallocate

local h = require "syscall.helpers"

local octal, multiflags, charflags, swapflags, strflag, atflag, modeflags
  = h.octal, h.multiflags, h.charflags, h.swapflags, h.strflag, h.atflag, h.modeflags

local c = {}

-- TODO incomplete
c.SYS = strflag {
  __getcwd = 296,
  mount50 = 410,
  stat50 = 439,
  fstat50 = 440,
  lstat50 = 441,
}

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
c.E.WOULDBLOCK    = c.E.EAGAIN
c.E.DEADLOCK      = c.E.EDEADLK

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

c.AT_FDCWD = atflag {
  FDCWD = -100,
}

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

c.S_I = multiflags {
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

c.UMOUNT = multiflags {
  FORCE    = 0x00080000,
}

-- note equivalent of MS_ in Linux
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

MODULE_CMD = strflag {
  INIT = 0,
  FINI = 1,
  STAT = 2,
  AUTOUNLOAD = 3,
}

return c

