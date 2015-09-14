-- ppc specific constants

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local h = require "syscall.helpers"

local octal = h.octal

local arch = {}

arch.EDEADLOCK = 58 -- only error that differs from generic

arch.SO = { -- 16-21 differ for ppc
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
  RCVLOWAT    = 16,
  SNDLOWAT    = 17,
  RCVTIMEO    = 18,
  SNDTIMEO    = 19,
  PASSCRED    = 20,
  PEERCRED    = 21,
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
}

arch.OFLAG = {
  OPOST  = octal('00000001'),
  ONLCR  = octal('00000002'),
  OLCUC  = octal('00000004'),
  OCRNL  = octal('00000010'),
  ONOCR  = octal('00000020'),
  ONLRET = octal('00000040'),
  OFILL  = octal('00000100'),
  OFDEL  = octal('00000200'),
  NLDLY  = octal('00001400'),
  NL0    = octal('00000000'),
  NL1    = octal('00000400'),
  NL2    = octal('00001000'),
  NL3    = octal('00001400'),
  CRDLY  = octal('00030000'),
  CR0    = octal('00000000'),
  CR1    = octal('00010000'),
  CR2    = octal('00020000'),
  CR3    = octal('00030000'),
  TABDLY = octal('00006000'),
  TAB0   = octal('00000000'),
  TAB1   = octal('00002000'),
  TAB2   = octal('00004000'),
  TAB3   = octal('00006000'),
  BSDLY  = octal('00100000'),
  BS0    = octal('00000000'),
  BS1    = octal('00100000'),
  FFDLY  = octal('00040000'),
  FF0    = octal('00000000'),
  FF1    = octal('00040000'),
  VTDLY  = octal('00200000'),
  VT0    = octal('00000000'),
  VT1    = octal('00200000'),
  XTABS  = octal('00006000'),
}

arch.LFLAG = {
  ISIG    = 0x00000080,
  ICANON  = 0x00000100,
  XCASE   = 0x00004000,
  ECHO    = 0x00000008,
  ECHOE   = 0x00000002,
  ECHOK   = 0x00000004,
  ECHONL  = 0x00000010,
  NOFLSH  = 0x80000000,
  TOSTOP  = 0x00400000,
  ECHOCTL = 0x00000040,
  ECHOPRT = 0x00000020,
  ECHOKE  = 0x00000001,
  FLUSHO  = 0x00800000,
  PENDIN  = 0x20000000,
  IEXTEN  = 0x00000400,
  EXTPROC = 0x10000000,
}

-- TODO these will be in a table
arch.CBAUD      = octal('0000377')
arch.CBAUDEX    = octal('0000000')
arch.CIBAUD     = octal('077600000')

arch.CFLAG = {
  CSIZE      = octal('00001400'),
  CS5        = octal('00000000'),
  CS6        = octal('00000400'),
  CS7        = octal('00001000'),
  CS8        = octal('00001400'),
  CSTOPB     = octal('00002000'),
  CREAD      = octal('00004000'),
  PARENB     = octal('00010000'),
  PARODD     = octal('00020000'),
  HUPCL      = octal('00040000'),
  CLOCAL     = octal('00100000'),
}

arch.IFLAG = {
  IGNBRK  = octal('0000001'),
  BRKINT  = octal('0000002'),
  IGNPAR  = octal('0000004'),
  PARMRK  = octal('0000010'),
  INPCK   = octal('0000020'),
  ISTRIP  = octal('0000040'),
  INLCR   = octal('0000100'),
  IGNCR   = octal('0000200'),
  ICRNL   = octal('0000400'),
  IXON    = octal('0001000'),
  IXOFF   = octal('0002000'),
  IXANY   = octal('0004000'),
  IUCLC   = octal('0010000'),
  IMAXBEL = octal('0020000'),
  IUTF8   = octal('0040000'),
}

arch.CC = {
  VINTR           = 0,
  VQUIT           = 1,
  VERASE          = 2,
  VKILL           = 3,
  VEOF            = 4,
  VMIN            = 5,
  VEOL            = 6,
  VTIME           = 7,
  VEOL2           = 8,
  VSWTC           = 9,
  VWERASE         = 10,
  VREPRINT        = 11,
  VSUSP           = 12,
  VSTART          = 13,
  VSTOP           = 14,
  VLNEXT          = 15,
  VDISCARD        = 16,
}

arch.B = {
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
  ['57600'] = octal('00020'),
  ['115200'] = octal('00021'),
  ['230400'] = octal('00022'),
  ['460800'] = octal('00023'),
  ['500000'] = octal('00024'),
  ['576000'] = octal('00025'),
  ['921600'] = octal('00026'),
  ['1000000'] = octal('00027'),
  ['1152000'] = octal('00030'),
  ['1500000'] = octal('00031'),
  ['2000000'] = octal('00032'),
  ['2500000'] = octal('00033'),
  ['3000000'] = octal('00034'),
  ['3500000'] = octal('00035'),
  ['4000000'] = octal('00036'),
}

arch.O = {
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
  DIRECTORY = octal('040000'),
  NOFOLLOW  = octal('0100000'),
  LARGEFILE = octal('0200000'),
  DIRECT    = octal('0400000'),
  NOATIME   = octal('01000000'),
  CLOEXEC   = octal('02000000'),
  SYNC      = octal('04010000'),
}

arch.MAP = {
  FILE       = 0,
  SHARED     = 0x01,
  PRIVATE    = 0x02,
  TYPE       = 0x0f,
  FIXED      = 0x10,
  ANONYMOUS  = 0x20,
  NORESERVE  = 0x40,
  LOCKED     = 0x80,
  GROWSDOWN  = 0x00100,
  DENYWRITE  = 0x00800,
  EXECUTABLE = 0x01000,
  POPULATE   = 0x08000,
  NONBLOCK   = 0x10000,
  STACK      = 0x20000,
  HUGETLB    = 0x40000,
}

arch.MCL = {
  CURRENT    = 0x2000,
  FUTURE     = 0x4000,
}

arch.PROT = {
  SAO       = 0x10, -- Strong Access Ordering
}

return arch

