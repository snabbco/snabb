-- tables of constants for OSX

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local h = require "syscall.helpers"

local octal, multiflags, charflags, swapflags, strflag, atflag, modeflags
  = h.octal, h.multiflags, h.charflags, h.swapflags, h.strflag, h.atflag, h.modeflags

local c = {}

c.errornames = require "syscall.osx.errors"

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
  BADEXEC	= 85,
  BADARCH	= 86,
  SHLIBVERS	= 87,
  BADMACHO	= 88,
  CANCELED	= 89,
  IDRM		= 90,
  NOMSG		= 91,
  ILSEQ		= 92,
  NOATTR	= 93,
  BADMSG	= 94,
  MULTIHOP	= 95,
  NODATA	= 96,
  NOLINK        = 97,
  NOSR          = 98,
  NOSTR         = 99,
  PROTO         = 100,
  TIME          = 101,
  OPNOTSUPP	= 102,
  NOPOLICY      = 103,
  NOTRECOVERABLE= 104,
  OWNERDEAD     = 105,
  QFULL        	= 106,
}

-- alternate names
c.EALIAS = {
  WOULDBLOCK    = c.E.AGAIN,
  DEADLOCK      = c.E.EDEADLK,
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
  ROUTE       = 17,
  LINK        = 18,
  COIP        = 20,
  CNT         = 21,
  IPX         = 23,
  SIP         = 24,
  NDRV        = 27,
  ISDN        = 28,
  INET6       = 30,
  NATM        = 31,
  SYSTEM      = 32,
  NETBIOS     = 33,
  PPP         = 34,
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
  SYNC        = 0x0080,
  NOFOLLOW    = 0x0100,
  CREAT       = 0x0200,
  TRUNC       = 0x0400,
  EXCL        = 0x0800,
  EVTONLY     = 0x8000,
  NOCTTY      = 0x20000,
  DIRECTORY   = 0x100000,
  DSYNC       = 0x400000,
  CLOEXEC     = 0x1000000,
}

-- sigaction, note renamed SIGACT from SIG_
c.SIGACT = strflag {
  ERR = -1,
  DFL =  0,
  IGN =  1,
  HOLD = 5,
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
}

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
  USERTRAMP = 0x0100,
  ["64REGSET"] = 0x0200,
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

c.SOCK = strflag {
  STREAM    = 1,
  DGRAM     = 2,
  RAW       = 3,
  RDM       = 4,
  SEQPACKET = 5,
}

c.SOL = strflag {
  LOCAL     = 0,
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
  ST             = 7,
  EGP            = 8,
  PIGP           = 9,
  RCCMON         = 10,
  NVPII          = 11,
  PUP            = 12,
  ARGUS          = 13,
  EMCON          = 14,
  XNET           = 15,
  CHAOS          = 16,
  UDP            = 17,
  MUX            = 18,
  MEAS           = 19,
  HMP            = 20,
  PRM            = 21,
  IDP            = 22,
  TRUNK1         = 23,
  TRUNK2         = 24,
  LEAF1          = 25,
  LEAF2          = 26,
  RDP            = 27,
  IRTP           = 28,
  TP             = 29,
  BLT            = 30,
  NSP            = 31,
  INP            = 32,
  SEP            = 33,
  ["3PC"]        = 34,
  IDPR           = 35,
  XTP            = 36,
  DDP            = 37,
  CMTP           = 38,
  TPXX           = 39,
  IL             = 40,
  IPV6           = 41,
  SDRP           = 42,
  ROUTING        = 43,
  FRAGMENT       = 44,
  IDRP           = 45,
  RSVP           = 46,
  GRE            = 47,
  MHRP           = 48,
  BHA            = 49,
  ESP            = 50,
  AH             = 51,
  INLSP          = 52,
  SWIPE          = 53,
  NHRP           = 54,
  ICMPV6         = 58,
  NONE           = 59,
  DSTOPTS        = 60,
  AHIP           = 61,
  CFTP           = 62,
  HELLO          = 63,
  SATEXPAK       = 64,
  KRYPTOLAN      = 65,
  RVD            = 66,
  IPPC           = 67,
  ADFS           = 68,
  SATMON         = 69,
  VISA           = 70,
  IPCV           = 71,
  CPNX           = 72,
  CPHB           = 73,
  WSN            = 74,
  PVP            = 75,
  BRSATMON       = 76,
  ND             = 77,
  WBMON          = 78,
  WBEXPAK        = 79,
  EON            = 80,
  VMTP           = 81,
  SVMTP          = 82,
  VINES          = 83,
  TTP            = 84,
  IGP            = 85,
  DGP            = 86,
  TCF            = 87,
  IGRP           = 88,
  OSPFIGP        = 89,
  SRPC           = 90,
  LARP           = 91,
  MTP            = 92,
  AX25           = 93,
  IPEIP          = 94,
  MICP           = 95,
  SCCSP          = 96,
  ETHERIP        = 97,
  ENCAP          = 98,
  APES           = 99,
  GMTP           = 100,
  PIM            = 103,
  IPCOMP         = 108,
  PGM            = 113,
  SCTP           = 132,
  DIVERT         = 254,
  RAW            = 255,
}

c.MSG = multiflags {
  OOB             = 0x1,
  PEEK            = 0x2,
  DONTROUTE       = 0x4,
  EOR             = 0x8,
  TRUNC           = 0x10,
  CTRUNC          = 0x20,
  WAITALL         = 0x40,
  DONTWAIT        = 0x80,
  EOF             = 0x100,
  WAITSTREAM      = 0x200,
  FLUSH           = 0x400,
  HOLD            = 0x800,
  SEND            = 0x1000,
  HAVEMORE        = 0x2000,
  RCVMORE         = 0x4000,
  NEEDSA          = 0x10000,
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
  FLUSH_DATA  = 40,
  CHKCLEAN    = 41,
  PREALLOCATE = 42,
  SETSIZE     = 43,
  RDADVISE    = 44,
  RDAHEAD     = 45,
  READBOOTSTRAP= 46,
  WRITEBOOTSTRAP= 47,
  NOCACHE     = 48,
  LOG2PHYS    = 49,
  GETPATH     = 50,
  FULLFSYNC   = 51,
  PATHPKG_CHECK= 52,
  FREEZE_FS   = 53,
  THAW_FS     = 54,
  GLOBAL_NOCACHE= 55,
  ADDSIGS     = 59,
  MARKDEPENDENCY= 60,
  ADDFILESIGS = 61,
  NODIRECT    = 62,
  GETPROTECTIONCLASS = 63,
  SETPROTECTIONCLASS = 64,
  LOG2PHYS_EXT= 65,
  GETLKPID             = 66,
  DUPFD_CLOEXEC        = 67,
  SETBACKINGSTORE      = 70,
  GETPATH_MTMINFO      = 71,
  SETNOSIGPIPE         = 73,
  GETNOSIGPIPE         = 74,
  TRANSCODEKEY         = 75,
  SINGLE_WRITER        = 76,
  GETPROTECTIONLEVEL   = 77,
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
  NOHANG      = 0x00000001,
  UNTRACED    = 0x00000002,
  EXITED      = 0x00000004,
  STOPPED     = 0x00000008,
  CONTINUED   = 0x00000010,
  NOWAIT      = 0x00000020,
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

c.SOMAXCONN = 128

c.SHUT = strflag {
  RD   = 0,
  WR   = 1,
  RDWR = 2,
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

-- poll
c.POLL = multiflags {
  IN          = 0x001,
  PRI         = 0x002,
  OUT         = 0x004,
  WRNORM      = 0x004,
  ERR         = 0x008,
  HUP         = 0x010,
  NVAL        = 0x020,
  RDNORM      = 0x040,
  RDBAND      = 0x080,
  WRBAND      = 0x100,
  EXTEND      = 0x200,
  ATTRIB      = 0x400,
  NLINK       = 0x800,
  WRITE       = 0x1000,
}

--mmap
c.PROT = multiflags {
  NONE  = 0x0,
  READ  = 0x1,
  WRITE = 0x2,
  EXEC  = 0x4,
}

-- Sharing types
c.MAP = multiflags {
  FILE           = 0x0000,
  SHARED         = 0x0001,
  PRIVATE        = 0x0002,
  FIXED          = 0x0010,
  RENAME         = 0x0020,
  NORESERVE      = 0x0040,
  NOEXTEND       = 0x0100,
  HASSEMAPHORE   = 0x0200,
  NOCACHE        = 0x0400,
  JIT            = 0x0800,
  ANON           = 0x1000,
}

c.MCL = strflag {
  CURRENT    = 0x01,
  FUTURE     = 0x02,
}

-- flags to `msync'. - note was MS_ renamed to MSYNC_
c.MSYNC = multiflags {
  ASYNC       = 0x0001,
  INVALIDATE  = 0x0002,
  SYNC        = 0x0010,
}

c.MADV = strflag {
  NORMAL      = 0,
  RANDOM      = 1,
  SEQUENTIAL  = 2,
  WILLNEED    = 3,
  DONTNEED    = 4,
  FREE        = 5,
  ZERO_WIRED_PAGES = 6,
  FREE_REUSABLE    = 7,
  FREE_REUSE       = 8,
  CAN_REUSE        = 9,
}

-- Baud rates just the identity function
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
  CCTS_OFLOW     = 0x00010000,
  CRTS_IFLOW     = 0x00020000,
  CDTR_IFLOW     = 0x00040000,
  CDSR_OFLOW     = 0x00080000,
  CCAR_OFLOW     = 0x00100000,
}

c.CFLAG.CRTSCTS	= c.CFLAG.CCTS_OFLOW + c.CFLAG.CRTS_IFLOW

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

-- waitpid and wait4 pid
c.WAIT = strflag {
  ANY      = -1,
  MYPGRP   = 0,
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
  NAME_CHARS_MAX    = 10,
  CASE_SENSITIVE    = 11,
  CASE_PRESERVING   = 12,
  EXTENDED_SECURITY_NP = 13,
  AUTH_OPAQUE_NP    = 14,
  ["2_SYMLINKS"]    = 15,
  ALLOC_SIZE_MIN    = 16,
  ASYNC_IO          = 17,
  FILESIZEBITS      = 18,
  PRIO_IO           = 19,
  REC_INCR_XFER_SIZE= 20,
  REC_MAX_XFER_SIZE = 21,
  REC_MIN_XFER_SIZE = 22,
  REC_XFER_ALIGN    = 23,
  SYMLINK_MAX       = 24,
  SYNC_IO           = 25,
  XATTR_SIZE_BITS   = 26,
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
  TIMESTAMP    = 0x0400,
  TIMESTAMP_MONOTONIC = 0x0800,
  DONTTRUNC    = 0x2000,
  WANTMORE     = 0x4000,
  WANTOOBFLAG  = 0x8000,
  SNDBUF       = 0x1001,
  RCVBUF       = 0x1002,
  SNDLOWAT     = 0x1003,
  RCVLOWAT     = 0x1004,
  SNDTIMEO     = 0x1005,
  RCVTIMEO     = 0x1006,
  ERROR        = 0x1007,
  TYPE         = 0x1008,
  LABEL        = 0x1010,
  PEERLABEL    = 0x1011,
  NREAD        = 0x1020,
  NKE          = 0x1021,
  NOSIGPIPE    = 0x1022,
  NOADDRERR    = 0x1023,
  NWRITE       = 0x1024,
  LINGER_SEC   = 0x1080,
  RESTRICTIONS = 0x1081,
  RANDOMPORT   = 0x1082,
  NP_EXTENSIONS= 0x1083,
}

c.SO.PROTOTYPE = c.SO.PROTOCOL

c.TCP = strflag {
  NODELAY            = 0x01,
  MAXSEG             = 0x02,
  NOPUSH             = 0x04,
  NOOPT              = 0x08,
  KEEPALIVE          = 0x10,
  CONNECTIONTIMEOUT  = 0x20,
--PERSIST_TIMEOUT    = 0x40, -- header defines not namespaced as TCP, bug?
  RXT_CONNDROPTIME   = 0x80,
  RXT_FINDROP 	     = 0x100,
}

-- for chflags and stat. note these have no prefix
c.CHFLAGS = multiflags {
  UF_NODUMP      = 0x00000001,
  UF_IMMUTABLE   = 0x00000002,
  UF_APPEND      = 0x00000004,
  UF_OPAQUE      = 0x00000008,
  UF_HIDDEN      = 0x00008000,

  SF_ARCHIVED    = 0x00010000,
  SF_IMMUTABLE   = 0x00020000,
  SF_APPEND      = 0x00040000,
}

c.CHFLAGS.IMMUTABLE = c.CHFLAGS.UF_IMMUTABLE + c.CHFLAGS.SF_IMMUTABLE
c.CHFLAGS.APPEND = c.CHFLAGS.UF_APPEND + c.CHFLAGS.SF_APPEND
c.CHFLAGS.OPAQUE = c.CHFLAGS.UF_OPAQUE

-- kqueue
c.EV = multiflags {
  ADD      = 0x0001,
  DELETE   = 0x0002,
  ENABLE   = 0x0004,
  DISABLE  = 0x0008,
  ONESHOT  = 0x0010,
  CLEAR    = 0x0020,
  RECEIPT  = 0x0040,
  DISPATCH = 0x0080,
  SYSFLAGS = 0xF000,
  FLAG0    = 0x1000,
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
  MACHPORT = -8,
  FS       = -9,
  USER     = -10,
  VM       = -12,
  SYSCOUNT = 13,
}

c.NOTE = multiflags {
-- user
  FFNOP      = 0x00000000,
  FFAND      = 0x40000000,
  FFOR       = 0x80000000,
  FFCOPY     = 0xc0000000,
  FFCTRLMASK = 0xc0000000,
  FFLAGSMASK = 0x00ffffff,
  TRIGGER    = 0x01000000,
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
  REAP      = 0x10000000,
  SIGNAL    = 0x08000000,
  EXITSTATUS= 0x04000000,
  RESOURCEEND=0x02000000,
-- app states
--[[
  APPACTIVE         = 0x00800000,
  APPBACKGROUND     = 0x00400000,
  APPNONUI          = 0x00200000,
  APPINACTIVE       = 0x00100000,
  APPALLSTATES      = 0x00f00000,
--]]
}

c.ITIMER = strflag {
  REAL    = 0,
  VIRTUAL = 1,
  PROF    = 2,
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
  MULTICAST_VIF      = 14,
  RSVP_ON            = 15,
  RSVP_OFF           = 16,
  RSVP_VIF_ON        = 17,
  RSVP_VIF_OFF       = 18,
  PORTRANGE          = 19,
  RECVIF             = 20,
  IPSEC_POLICY       = 21,
  FAITH              = 22,
  STRIPHDR           = 23,
  RECVTTL            = 24,
  BOUND_IF           = 25,
  PKTINFO            = 26,
  FW_ADD             = 40,
  FW_DEL             = 41,
  FW_FLUSH           = 42,
  FW_ZERO            = 43,
  FW_GET             = 44,
  FW_RESETLOG        = 45,
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
  ["2292PKTINFO"]   = 19,
  ["2292HOPLIMIT"]  = 20,
  ["2292NEXTHOP"]   = 21,
  ["2292HOPOPTS"]   = 22,
  ["2292DSTOPTS"]   = 23,
  ["2292RTHDR"]     = 24,
  ["2292PKTOPTIONS"]= 25,
  CHECKSUM          = 26,
  V6ONLY            = 27,
  IPSEC_POLICY      = 28,
  FAITH             = 29,
  RECVTCLASS        = 35,
  TCLASS            = 36,
}

c.XATTR = multiflags {
  NOFOLLOW   = 0x0001,
  CREATE     = 0x0002,
  REPLACE    = 0x0004,
  NOSECURITY = 0x0008,
  NODEFAULT  = 0x0010,
}

-- TODO many missing, see also freebsd
c.MNT = strflag {
  RDONLY      = 0x00000001,
  SYNCHRONOUS = 0x00000002,
  NOEXEC      = 0x00000004,
  NOSUID      = 0x00000008,
  NODEV       = 0x00000010,
  UNION       = 0x00000020,
  ASYNC       = 0x00000040,
  CPROTECT    = 0x00000080,

  FORCE       = 0x00080000,
}

c.CTL = strflag {
  UNSPEC     = 0,
  KERN       = 1,
  VM         = 2,
  VFS        = 3,
  NET        = 4,
  DEBUG      = 5,
  HW         = 6,
  MACHDEP    = 7,
  USER       = 8,
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
  BOOTTIME          = 21,
  NISDOMAINNAME     = 22,
  MAXPARTITIONS     = 23,
  KDEBUG            = 24,
  UPDATEINTERVAL    = 25,
  OSRELDATE         = 26,
  NTP_PLL           = 27,
  BOOTFILE          = 28,
  MAXFILESPERPROC   = 29,
  MAXPROCPERUID     = 30,
  DUMPDEV           = 31,
  IPC               = 32,
  DUMMY             = 33,
  PS_STRINGS        = 34,
  USRSTACK32        = 35,
  LOGSIGEXIT        = 36,
  SYMFILE           = 37,
  PROCARGS          = 38,
  NETBOOT           = 40,
  PANICINFO         = 41,
  SYSV              = 42,
  AFFINITY          = 43,
  TRANSLATE         = 44,
  EXEC              = 45,
  AIOMAX            = 46,
  AIOPROCMAX        = 47,
  AIOTHREADS        = 48,
  COREFILE          = 50,
  COREDUMP          = 51,
  SUGID_COREDUMP    = 52,
  PROCDELAYTERM     = 53,
  SHREG_PRIVATIZABLE= 54,
  LOW_PRI_WINDOW    = 56,
  LOW_PRI_DELAY     = 57,
  POSIX             = 58,
  USRSTACK64        = 59,
  NX_PROTECTION     = 60,
  TFP               = 61,
  PROCNAME          = 62,
  THALTSTACK        = 63,
  SPECULATIVE_READS = 64,
  OSVERSION         = 65,
  SAFEBOOT          = 66,
  LCTX              = 67,
  RAGEVNODE         = 68,
  TTY               = 69,
  CHECKOPENEVT      = 70,
  THREADNAME        = 71,
}

-- actually SYSTEM_CLOCK etc, renamed
c.CLOCKTYPE = {
  SYSTEM   = 0,
  CALENDAR = 1,
}

c.CLOCKTYPE.REALTIME = c.CLOCKTYPE.SYSTEM

-- AT constants only in recent versions, should check when added
c.AT_FDCWD = atflag {
  FDCWD = -2,
}

c.AT = multiflags {
  EACCESS          = 0x0010,
  SYMLINK_NOFOLLOW = 0x0020,
  SYMLINK_FOLLOW   = 0x0040,
  REMOVEDIR        = 0x0080,
}

return c

