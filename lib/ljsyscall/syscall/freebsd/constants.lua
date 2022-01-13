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

local octal, multiflags, charflags, swapflags, strflag, atflag, modeflags
  = h.octal, h.multiflags, h.charflags, h.swapflags, h.strflag, h.atflag, h.modeflags

local version = require "syscall.freebsd.version".version

local ffi = require "ffi"

local function charp(n) return ffi.cast("char *", n) end

local c = {}

c.errornames = require "syscall.freebsd.errors"

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
  IDRM          = 82,
  NOMSG         = 83,
  OVERFLOW      = 84,
  CANCELED      = 85,
  ILSEQ         = 86,
  NOATTR        = 87,
  DOOFUS        = 88,
  BADMSG        = 89,
  MULTIHOP      = 90,
  NOLINK        = 91,
  PROTO         = 92,
  NOTCAPABLE    = 93,
  CAPMODE       = 94,
}

if version >= 10 then
  c.E.NOTRECOVERABLE= 95
  c.E.OWNERDEAD     = 96
end

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
  NETBIOS     = 6,
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
-- #define pseudo_AF_XTP   19
  COIP        = 20,
  CNT         = 21,
-- #define pseudo_AF_RTIP  22
  IPX         = 23,
  SIP         = 24,
-- pseudo_AF_PIP   25
  ISDN        = 26,
-- pseudo_AF_KEY   27
  INET6       = 28,
  NATM        = 29,
  ATM         = 30,
-- pseudo_AF_HDRCMPLT 31
  NETGRAPH    = 32,
  SLOW        = 33,
  SCLUSTER    = 34,
  ARP         = 35,
  BLUETOOTH   = 36,
  IEEE80211   = 37,
}

c.AF.UNIX = c.AF.LOCAL
c.AF.OSI = c.AF.ISO
c.AF.E164 = c.AF.ISDN

if version >= 10 then
  c.AF.INET_SDP  = 40
  c.AF.INET6_SDP = 42
end

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
  DIRECT      = 0x00010000,
  DIRECTORY   = 0x00020000,
  EXEC        = 0x00040000,
  TTY_INIT    = 0x00080000,
  CLOEXEC     = 0x00100000,
}

-- for pipe2, selected flags from c.O
c.OPIPE = multiflags {
  NONBLOCK  = 0x0004,
  CLOEXEC   = 0x00100000,
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
  KEVENT    = 3,
  THREAD_ID = 4,
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

if version >=10 then c.SIG.LIBRT = 33 end


c.SIG.LWP = c.SIG.THR

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
  DATA = 3,
  HOLE = 4,
}

c.SOCK = multiflags {
  STREAM    = 1,
  DGRAM     = 2,
  RAW       = 3,
  RDM       = 4,
  SEQPACKET = 5,
}

if version >= 10 then
  c.SOCK.CLOEXEC  = 0x10000000
  c.SOCK.NONBLOCK = 0x20000000
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
  INIGNEOF   = 0x2000,
  ERR        = 0x0008,
  HUP        = 0x0010,
  NVAL       = 0x0020,
}

c.POLL.WRNORM = c.POLL.OUT
c.POLL.STANDARD = c.POLL["IN,PRI,OUT,RDNORM,RDBAND,WRBAND,ERR,HUP,NVAL"]

c.AT_FDCWD = atflag {
  FDCWD = -100,
}

c.AT = multiflags {
  EACCESS          = 0x100,
  SYMLINK_NOFOLLOW = 0x200,
  SYMLINK_FOLLOW   = 0x400,
  REMOVEDIR        = 0x800,
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
  RENAME     = 0x0020,
  NORESERVE  = 0x0040,
  RESERVED0080 = 0x0080,
  RESERVED0100 = 0x0100,
  HASSEMAPHORE = 0x0200,
  STACK      = 0x0400,
  NOSYNC     = 0x0800,
  ANON       = 0x1000,
  NOCORE     = 0x00020000,
-- TODO add aligned maps in
}

if abi.abi64 and version >= 10 then c.MAP["32BIT"] = 0x00080000 end

c.MCL = strflag {
  CURRENT    = 0x01,
  FUTURE     = 0x02,
}

-- flags to `msync'. - note was MS_ renamed to MSYNC_
c.MSYNC = multiflags {
  SYNC       = 0x0000,
  ASYNC      = 0x0001,
  INVALIDATE = 0x0002,
}

c.MADV = strflag {
  NORMAL      = 0,
  RANDOM      = 1,
  SEQUENTIAL  = 2,
  WILLNEED    = 3,
  DONTNEED    = 4,
  FREE        = 5,
  NOSYNC      = 6,
  AUTOSYNC    = 7,
  NOCORE      = 8,
  CORE        = 9,
  PROTECT     = 10,
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
  MOBILE         = 55,
  TLSP           = 56,
  SKIP           = 57,
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
  IPCOMP         = 108,
  SCTP           = 132,
  MH             = 135,
  PIM            = 103,
  CARP           = 112,
  PGM            = 113,
  MPLS           = 137,
  PFSYNC         = 240,
  RAW            = 255,
}

c.SCM = multiflags {
  RIGHTS     = 0x01,
  TIMESTAMP  = 0x02,
  CREDS      = 0x03,
  BINTIME    = 0x04,
}

c.F = strflag {
  DUPFD       = 0,
  GETFD       = 1,
  SETFD       = 2,
  GETFL       = 3,
  SETFL       = 4,
  GETOWN      = 5,
  SETOWN      = 6,
  OGETLK      = 7,
  OSETLK      = 8,
  OSETLKW     = 9,
  DUP2FD      = 10,
  GETLK       = 11,
  SETLK       = 12,
  SETLKW      = 13,
  SETLK_REMOTE= 14,
  READAHEAD   = 15,
  RDAHEAD     = 16,
  DUPFD_CLOEXEC= 17,
  DUP2FD_CLOEXEC= 18,
}

c.FD = multiflags {
  CLOEXEC = 1,
}

-- note changed from F_ to FCNTL_LOCK
c.FCNTL_LOCK = strflag {
  RDLCK = 1,
  UNLCK = 2,
  WRLCK = 3,
  UNLCKSYS = 4,
  CANCEL = 5,
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
  CONTINUED   = 4,
  NOWAIT      = 8,
  EXITED      = 16,
  TRAPPED     = 32,
  LINUXCLONE  = 0x80000000,
}

c.W.STOPPED = c.W.UNTRACED

-- waitpid and wait4 pid
c.WAIT = strflag {
  ANY      = -1,
  MYPGRP   = 0,
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
  NOTIFICATION    = 0x2000,
  NBIO            = 0x4000,
  COMPAT          = 0x8000,
  NOSIGNAL        = 0x20000,
}

if version >= 10 then c.MSG.CMSG_CLOEXEC = 0x40000 end

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
  ALLOC_SIZE_MIN    = 10,
  FILESIZEBITS      = 12,
  REC_INCR_XFER_SIZE= 14,
  REC_MAX_XFER_SIZE = 15,
  REC_MIN_XFER_SIZE = 16,
  REC_XFER_ALIGN    = 17,
  SYMLINK_MAX       = 18,
  MIN_HOLE_SIZE     = 21,
  ASYNC_IO          = 53,
  PRIO_IO           = 54,
  SYNC_IO           = 55,
  ACL_EXTENDED      = 59,
  ACL_PATH_MAX      = 60,
  CAP_PRESENT       = 61,
  INF_PRESENT       = 62,
  MAC_PRESENT       = 63,
  ACL_NFS4          = 64,
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
  TIMESTAMP    = 0x0400,
  NOSIGPIPE    = 0x0800,
  ACCEPTFILTER = 0x1000,
  BINTIME      = 0x2000,
  NO_OFFLOAD   = 0x4000,
  NO_DDP       = 0x8000,
  SNDBUF       = 0x1001,
  RCVBUF       = 0x1002,
  SNDLOWAT     = 0x1003,
  RCVLOWAT     = 0x1004,
  SNDTIMEO     = 0x1005,
  RCVTIMEO     = 0x1006,
  ERROR        = 0x1007,
  TYPE         = 0x1008,
  LABEL        = 0x1009,
  PEERLABEL    = 0x1010,
  LISTENQLIMIT = 0x1011,
  LISTENQLEN   = 0x1012,
  LISTENINCQLEN= 0x1013,
  SETFIB       = 0x1014,
  USER_COOKIE  = 0x1015,
  PROTOCOL     = 0x1016,
}

c.SO.PROTOTYPE = c.SO.PROTOCOL

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
  ONESBCAST          = 23,
  BINDANY            = 24,
  FW_TABLE_ADD       = 40,
  FW_TABLE_DEL       = 41,
  FW_TABLE_FLUSH     = 42,
  FW_TABLE_GETSIZE   = 43,
  FW_TABLE_LIST      = 44,
  FW3                = 48,
  DUMMYNET3          = 49,
  FW_ADD             = 50,
  FW_DEL             = 51,
  FW_FLUSH           = 52,
  FW_ZERO            = 53,
  FW_GET             = 54,
  FW_RESETLOG        = 55,
  FW_NAT_CFG         = 56,
  FW_NAT_DEL         = 57,
  FW_NAT_GET_CONFIG  = 58,
  FW_NAT_GET_LOG     = 59,
  DUMMYNET_CONFIGURE = 60,
  DUMMYNET_DEL       = 61,
  DUMMYNET_FLUSH     = 62,
  DUMMYNET_GET       = 64,
  RECVTTL            = 65,
  MINTTL             = 66,
  DONTFRAG           = 67,
  RECVTOS            = 68,
  ADD_SOURCE_MEMBERSHIP  = 70,
  DROP_SOURCE_MEMBERSHIP = 71,
  BLOCK_SOURCE       = 72,
  UNBLOCK_SOURCE     = 73,
}

c.IP.SENDSRCADDR = c.IP.RECVDSTADDR

-- Baud rates just the identity function  other than EXTA, EXTB
c.B = strflag {
  EXTA = 19200,
  EXTB = 38400,
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

-- for chflags and stat. note these have no prefix
c.CHFLAGS = multiflags {
  UF_NODUMP      = 0x00000001,
  UF_IMMUTABLE   = 0x00000002,
  UF_APPEND      = 0x00000004,
  UF_OPAQUE      = 0x00000008,
  UF_NOUNLINK    = 0x00000010,

  SF_ARCHIVED    = 0x00010000,
  SF_IMMUTABLE   = 0x00020000,
  SF_APPEND      = 0x00040000,
  SF_NOUNLINK    = 0x00100000,
  SF_SNAPSHOT    = 0x00200000,
}

c.CHFLAGS.IMMUTABLE = c.CHFLAGS.UF_IMMUTABLE + c.CHFLAGS.SF_IMMUTABLE
c.CHFLAGS.APPEND = c.CHFLAGS.UF_APPEND + c.CHFLAGS.SF_APPEND
c.CHFLAGS.OPAQUE = c.CHFLAGS.UF_OPAQUE
c.CHFLAGS.NOUNLINK = c.CHFLAGS.UF_NOUNLINK + c.CHFLAGS.SF_NOUNLINK

if version >=10 then
  c.CHFLAGS.UF_SYSTEM   = 0x00000080
  c.CHFLAGS.UF_SPARSE   = 0x00000100
  c.CHFLAGS.UF_OFFLINE  = 0x00000200
  c.CHFLAGS.UF_REPARSE  = 0x00000400
  c.CHFLAGS.UF_ARCHIVE  = 0x00000800
  c.CHFLAGS.UF_READONLY = 0x00001000
  c.CHFLAGS.UF_HIDDEN   = 0x00008000
end

c.TCP = strflag {
  NODELAY    = 1,
  MAXSEG     = 2,
  NOPUSH     = 4,
  NOOPT      = 8,
  MD5SIG     = 16,
  INFO       = 32,
  CONGESTION = 64,
  KEEPINIT   = 128,
  KEEPIDLE   = 256,
  KEEPINTVL  = 512,
  KEEPCNT    = 1024,
}

c.RB = multiflags {
  AUTOBOOT    = 0,
  ASKNAME     = 0x001,
  SINGLE      = 0x002,
  NOSYNC      = 0x004,
  HALT        = 0x008,
  INITNAME    = 0x010,
  DFLTROOT    = 0x020,
  KDB         = 0x040,
  RDONLY      = 0x080,
  DUMP        = 0x100,
  MINIROOT    = 0x200,
  VERBOSE     = 0x800,
  SERIAL      = 0x1000,
  CDROM       = 0x2000,
  POWEROFF    = 0x4000,
  GDB         = 0x8000,
  MUTE        = 0x10000,
  SELFTEST    = 0x20000,
  RESERVED1   = 0x40000,
  RESERVED2   = 0x80000,
  PAUSE       = 0x100000,
  MULTIPLE    = 0x20000000,
  BOOTINFO    = 0x80000000,
}

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
  FLAG1    = 0x2000,
  EOF      = 0x8000,
  ERROR    = 0x4000,
}

if version >= 10 then c.EV.DROP = 0x1000 end

c.EVFILT = strflag {
  READ     = -1,
  WRITE    = -2,
  AIO      = -3,
  VNODE    = -4,
  PROC     = -5,
  SIGNAL   = -6,
  TIMER    = -7,
  FS       = -9,
  LIO      = -10,
  USER     = -11,
  SYSCOUNT = 11,
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
  PCTRLMASK = 0xf0000000,
  PDATAMASK = 0x000fffff,
  TRACK     = 0x00000001,
  TRACKERR  = 0x00000002,
  CHILD     = 0x00000004,
}

c.SHM = strflag {
  ANON = charp(1),
}

c.PD = multiflags {
  DAEMON = 0x00000001,
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
  SOCKOPT_RESERVED1 = 3,
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

c.CLOCK = strflag {
  REALTIME           = 0,
  VIRTUAL            = 1,
  PROF               = 2,
  MONOTONIC          = 4,
  UPTIME             = 5,
  UPTIME_PRECISE     = 7,
  UPTIME_FAST        = 8,
  REALTIME_PRECISE   = 9,
  REALTIME_FAST      = 10,
  MONOTONIC_PRECISE  = 11,
  MONOTONIC_FAST     = 12,
  SECOND             = 13,
  THREAD_CPUTIME_ID  = 14,
  PROCESS_CPUTIME_ID = 15,
}

c.EXTATTR_NAMESPACE = strflag {
  EMPTY        = 0x00000000,
  USER         = 0x00000001,
  SYSTEM       = 0x00000002,
}

-- TODO mount flag is an int, so ULL is odd, but these are flags too...
-- TODO many flags missing, plus FreeBSD has a lot more mount complexities
c.MNT = strflag {
  RDONLY      = 0x0000000000000001ULL,
  SYNCHRONOUS = 0x0000000000000002ULL,
  NOEXEC      = 0x0000000000000004ULL,
  NOSUID      = 0x0000000000000008ULL,
  NFS4ACLS    = 0x0000000000000010ULL,
  UNION       = 0x0000000000000020ULL,
  ASYNC       = 0x0000000000000040ULL,
  SUIDDIR     = 0x0000000000100000ULL,
  SOFTDEP     = 0x0000000000200000ULL,
  NOSYMFOLLOW = 0x0000000000400000ULL,
  GJOURNAL    = 0x0000000002000000ULL,
  MULTILABEL  = 0x0000000004000000ULL,
  ACLS        = 0x0000000008000000ULL,
  NOATIME     = 0x0000000010000000ULL,
  NOCLUSTERR  = 0x0000000040000000ULL,
  NOCLUSTERW  = 0x0000000080000000ULL,
  SUJ         = 0x0000000100000000ULL,

  FORCE       = 0x0000000000080000ULL,
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
  P1003_1B   = 9,
  MAXID      = 10,
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
  UPDATEINTERVAL    = 23,
  OSRELDATE         = 24,
  NTP_PLL           = 25,
  BOOTFILE          = 26,
  MAXFILESPERPROC   = 27,
  MAXPROCPERUID     = 28,
  DUMPDEV           = 29,
  IPC               = 30,
  DUMMY             = 31,
  PS_STRINGS        = 32,
  USRSTACK          = 33,
  LOGSIGEXIT        = 34,
  IOV_MAX           = 35,
  HOSTUUID          = 36,
  ARND              = 37,
  MAXID             = 38,
}

if version >= 10 then -- not supporting on freebsd 9 as different ABI, recommend upgrade to use

local function CAPRIGHT(idx, b) return bit.bor64(bit.lshift64(1, 57 + idx), b) end

c.CAP = multiflags {}

-- index 0
c.CAP.READ        = CAPRIGHT(0, 0x0000000000000001ULL)
c.CAP.WRITE       = CAPRIGHT(0, 0x0000000000000002ULL)
c.CAP.SEEK_TELL   = CAPRIGHT(0, 0x0000000000000004ULL)
c.CAP.SEEK        = bit.bor64(c.CAP.SEEK_TELL, 0x0000000000000008ULL)
c.CAP.PREAD       = bit.bor64(c.CAP.SEEK, c.CAP.READ)
c.CAP.PWRITE      = bit.bor64(c.CAP.SEEK, c.CAP.WRITE)
c.CAP.MMAP        = CAPRIGHT(0, 0x0000000000000010ULL)
c.CAP.MMAP_R      = bit.bor64(c.CAP.MMAP, c.CAP.SEEK, c.CAP.READ)
c.CAP.MMAP_W      = bit.bor64(c.CAP.MMAP, c.CAP.SEEK, c.CAP.WRITE)
c.CAP.MMAP_X      = bit.bor64(c.CAP.MMAP, c.CAP.SEEK, 0x0000000000000020ULL)
c.CAP.MMAP_RW     = bit.bor64(c.CAP.MMAP_R, c.CAP.MMAP_W)
c.CAP.MMAP_RX     = bit.bor64(c.CAP.MMAP_R, c.CAP.MMAP_X)
c.CAP.MMAP_WX     = bit.bor64(c.CAP.MMAP_W, c.CAP.MMAP_X)
c.CAP.MMAP_RWX    = bit.bor64(c.CAP.MMAP_R, c.CAP.MMAP_W, c.CAP.MMAP_X)
c.CAP.CREATE      = CAPRIGHT(0, 0x0000000000000040ULL)
c.CAP.FEXECVE     = CAPRIGHT(0, 0x0000000000000080ULL)
c.CAP.FSYNC       = CAPRIGHT(0, 0x0000000000000100ULL)
c.CAP.FTRUNCATE   = CAPRIGHT(0, 0x0000000000000200ULL)
c.CAP.LOOKUP      = CAPRIGHT(0, 0x0000000000000400ULL)
c.CAP.FCHDIR      = CAPRIGHT(0, 0x0000000000000800ULL)
c.CAP.FCHFLAGS    = CAPRIGHT(0, 0x0000000000001000ULL)
c.CAP.CHFLAGSAT   = bit.bor64(c.CAP.FCHFLAGS, c.CAP.LOOKUP)
c.CAP.FCHMOD      = CAPRIGHT(0, 0x0000000000002000ULL)
c.CAP.FCHMODAT    = bit.bor64(c.CAP.FCHMOD, c.CAP.LOOKUP)
c.CAP.FCHOWN      = CAPRIGHT(0, 0x0000000000004000ULL)
c.CAP.FCHOWNAT    = bit.bor64(c.CAP.FCHOWN, c.CAP.LOOKUP)
c.CAP.FCNTL       = CAPRIGHT(0, 0x0000000000008000ULL)
c.CAP.FLOCK       = CAPRIGHT(0, 0x0000000000010000ULL)
c.CAP.FPATHCONF   = CAPRIGHT(0, 0x0000000000020000ULL)
c.CAP.FSCK        = CAPRIGHT(0, 0x0000000000040000ULL)
c.CAP.FSTAT       = CAPRIGHT(0, 0x0000000000080000ULL)
c.CAP.FSTATAT     = bit.bor64(c.CAP.FSTAT, c.CAP.LOOKUP)
c.CAP.FSTATFS     = CAPRIGHT(0, 0x0000000000100000ULL)
c.CAP.FUTIMES     = CAPRIGHT(0, 0x0000000000200000ULL)
c.CAP.FUTIMESAT   = bit.bor64(c.CAP.FUTIMES, c.CAP.LOOKUP)
c.CAP.LINKAT      = bit.bor64(c.CAP.LOOKUP, 0x0000000000400000ULL)
c.CAP.MKDIRAT     = bit.bor64(c.CAP.LOOKUP, 0x0000000000800000ULL)
c.CAP.MKFIFOAT    = bit.bor64(c.CAP.LOOKUP, 0x0000000001000000ULL)
c.CAP.MKNODAT     = bit.bor64(c.CAP.LOOKUP, 0x0000000002000000ULL)
c.CAP.RENAMEAT    = bit.bor64(c.CAP.LOOKUP, 0x0000000004000000ULL)
c.CAP.SYMLINKAT   = bit.bor64(c.CAP.LOOKUP, 0x0000000008000000ULL)
c.CAP.UNLINKAT    = bit.bor64(c.CAP.LOOKUP, 0x0000000010000000ULL)
c.CAP.ACCEPT      = CAPRIGHT(0, 0x0000000020000000ULL)
c.CAP.BIND        = CAPRIGHT(0, 0x0000000040000000ULL)
c.CAP.CONNECT     = CAPRIGHT(0, 0x0000000080000000ULL)
c.CAP.GETPEERNAME = CAPRIGHT(0, 0x0000000100000000ULL)
c.CAP.GETSOCKNAME = CAPRIGHT(0, 0x0000000200000000ULL)
c.CAP.GETSOCKOPT  = CAPRIGHT(0, 0x0000000400000000ULL)
c.CAP.LISTEN      = CAPRIGHT(0, 0x0000000800000000ULL)
c.CAP.PEELOFF     = CAPRIGHT(0, 0x0000001000000000ULL)
c.CAP.RECV        = c.CAP.READ
c.CAP.SEND        = c.CAP.WRITE
c.CAP.SETSOCKOPT  = CAPRIGHT(0, 0x0000002000000000ULL)
c.CAP.SHUTDOWN    = CAPRIGHT(0, 0x0000004000000000ULL)
c.CAP.BINDAT      = bit.bor64(c.CAP.LOOKUP, 0x0000008000000000ULL)
c.CAP.CONNECTAT   = bit.bor64(c.CAP.LOOKUP, 0x0000010000000000ULL)
c.CAP.SOCK_CLIENT = bit.bor64(c.CAP.CONNECT, c.CAP.GETPEERNAME, c.CAP.GETSOCKNAME, c.CAP.GETSOCKOPT,
                              c.CAP.PEELOFF, c.CAP.RECV, c.CAP.SEND, c.CAP.SETSOCKOPT, c.CAP.SHUTDOWN)
c.CAP.SOCK_SERVER = bit.bor64(c.CAP.ACCEPT, c.CAP.BIND, c.CAP.GETPEERNAME, c.CAP.GETSOCKNAME,
                              c.CAP.GETSOCKOPT, c.CAP.LISTEN, c.CAP.PEELOFF, c.CAP.RECV, c.CAP.SEND,
                              c.CAP.SETSOCKOPT, c.CAP.SHUTDOWN)
c.CAP.ALL0        = CAPRIGHT(0, 0x0000007FFFFFFFFFULL)
c.CAP.UNUSED0_40  = CAPRIGHT(0, 0x0000008000000000ULL)
c.CAP_UNUSED0_57  = CAPRIGHT(0, 0x0100000000000000ULL)

-- index 1
c.CAP.MAC_GET        = CAPRIGHT(1, 0x0000000000000001ULL)
c.CAP.MAC_SET        = CAPRIGHT(1, 0x0000000000000002ULL)
c.CAP.SEM_GETVALUE   = CAPRIGHT(1, 0x0000000000000004ULL)
c.CAP.SEM_POST       = CAPRIGHT(1, 0x0000000000000008ULL)
c.CAP.SEM_WAIT       = CAPRIGHT(1, 0x0000000000000010ULL)
c.CAP.EVENT          = CAPRIGHT(1, 0x0000000000000020ULL)
c.CAP.KQUEUE_EVENT   = CAPRIGHT(1, 0x0000000000000040ULL)
c.CAP.IOCTL          = CAPRIGHT(1, 0x0000000000000080ULL)
c.CAP.TTYHOOK        = CAPRIGHT(1, 0x0000000000000100ULL)
c.CAP.PDGETPID       = CAPRIGHT(1, 0x0000000000000200ULL)
c.CAP.PDWAIT         = CAPRIGHT(1, 0x0000000000000400ULL)
c.CAP.PDKILL         = CAPRIGHT(1, 0x0000000000000800ULL)
c.CAP.EXTATTR_DELETE = CAPRIGHT(1, 0x0000000000001000ULL)
c.CAP.EXTATTR_GET    = CAPRIGHT(1, 0x0000000000002000ULL)
c.CAP.EXTATTR_LIST   = CAPRIGHT(1, 0x0000000000004000ULL)
c.CAP.EXTATTR_SET    = CAPRIGHT(1, 0x0000000000008000ULL)

c.CAP_ACL_CHECK      = CAPRIGHT(1, 0x0000000000010000ULL)
c.CAP_ACL_DELETE     = CAPRIGHT(1, 0x0000000000020000ULL)
c.CAP_ACL_GET        = CAPRIGHT(1, 0x0000000000040000ULL)
c.CAP_ACL_SET        = CAPRIGHT(1, 0x0000000000080000ULL)
c.CAP_KQUEUE_CHANGE  = CAPRIGHT(1, 0x0000000000100000ULL)
c.CAP_KQUEUE         = bit.bor64(c.CAP.KQUEUE_EVENT, c.CAP.KQUEUE_CHANGE)
c.CAP_ALL1           = CAPRIGHT(1, 0x00000000001FFFFFULL)
c.CAP_UNUSED1_22     = CAPRIGHT(1, 0x0000000000200000ULL)
c.CAP_UNUSED1_57     = CAPRIGHT(1, 0x0100000000000000ULL)

c.CAP_FCNTL = multiflags {
  GETFL  = bit.lshift(1, c.F.GETFL),
  SETFL  = bit.lshift(1, c.F.SETFL),
  GETOWN = bit.lshift(1, c.F.GETOWN),
  SETOWN = bit.lshift(1, c.F.SETOWN),
}

c.CAP_FCNTL.ALL = bit.bor(c.CAP_FCNTL.GETFL, c.CAP_FCNTL.SETFL, c.CAP_FCNTL.GETOWN, c.CAP_FCNTL.SETOWN)

c.CAP_IOCTLS = multiflags {
  ALL = h.longmax,
}

c.CAP_RIGHTS_VERSION = 0 -- we do not understand others

end -- freebsd >= 10

if version >= 11 then
-- for utimensat
c.UTIME = strflag {
  NOW  = -1,
  OMIT = -2,
}
end

return c

