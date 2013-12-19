-- tables of constants for NetBSD

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local h = require "syscall.helpers"

local bit = require "syscall.bit"

local octal, multiflags, charflags, swapflags, strflag, atflag, modeflags
  = h.octal, h.multiflags, h.charflags, h.swapflags, h.strflag, h.atflag, h.modeflags

local c = {}

--c.errornames = require "syscall.freebsd.errors"

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
  CANCELLED     = 85,
  ILSEQ         = 86,
  NOATTR        = 87,
  DOOFUS        = 88,
  BADMSG        = 89,
  MULTIHOP      = 90,
  NOLINK        = 91,
  PROTO         = 92,
  NOTCAPABLE    = 93,
  CAPMODE       = 94,
  NOTRECOVERABLE= 95,
  OWNERDEAD     = 96,
}

-- alternate names
c.E.WOULDBLOCK    = c.E.AGAIN

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
-- #define pseudo_AF_XTP   19
  COIP        = 20,
  CNT         = 21,
-- #define pseudo_AF_RTIP  22
  IPX         = 23,
  SIP         = 24,
-- pseudo_AF_PIP   25
  ISDN        = 26,
-- pseudo_AF_KEY   27
  AF_INET6    = 28,
  NATM        = 29,
  ATM         = 30,
-- pseudo_AF_HDRCMPLT 31
  NETGRAPH    = 32,
  SLOW        = 33,
  SCLUSTER    = 34,
  ARP         = 35,
  BLUETOOTH   = 36,
  IEEE80211   = 37,
  INET_SDP    = 40,
  INET6_SDP   = 42,
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
  DIRECT      = 0x00010000,
  DIRECTORY   = 0x00020000,
  EXEC        = 0x00040000,
  TTY_INIT    = 0x00080000,
  CLOEXEC     = 0x00100000,
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
  DATA = 3,
  HOLE = 4,
}

c.SOCK = multiflags {
  STREAM    = 1,
  DGRAM     = 2,
  RAW       = 3,
  RDM       = 4,
  SEQPACKET = 5,
  CLOEXEC   = 0x10000000,
  NONBLOCK  = 0x20000000,
}

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

return c

