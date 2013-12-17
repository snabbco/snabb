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

return c

