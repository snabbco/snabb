-- tables of constants

-- so far almost all the single flag options have been converted to seperate tables with metamethods but still TODO
-- are the multi flag ones

-- TODO add test that we do not reallocate
-- TODO move to new table k rather than in S

local ffi = require "ffi"
local bit = require "bit"

local arch = require("include/constants-" .. ffi.arch) -- architecture specific code

local oldsm = setmetatable
local function setmetatable(t, mt)
  assert(mt, "BUG: nil metatable")
  return oldsm(t, mt)
end

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
local function flag(t, str)
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

local stringflag = {__index = flag, __call = function(t, a) return t[a] end}

-- take a bunch of flags in a string and return a number
function flags(t, str) -- allows multiple comma sep flags that are ORed
  if not str then return 0 end
  if type(str) ~= "string" then return str end
  if #str == 0 then return 0 end
  local val = rawget(t, str)
  if val then return val end
  local f = 0
  local a = split(",", str)
  for i, v in ipairs(a) do
    local s = trim(v):upper()
    local val = rawget(t, s)
    if not val then return nil end
    f = bit.bor(f, val)
  end
  t[str] = f
  return f
end

local multiflags = {__index = flags, __call = function(t, a) return t[a] end}

-- single char flags, eg used for access which allows "rwx"
local function chflags(t, s)
  if not s then return 0 end
  if type(s) ~= "string" then return s end
  s = trim(s:upper())
  local flag = 0
  for i = 1, #s do
    local c = s:sub(i, i)
    flag = bit.bor(flag, t[c])
  end
  return flag
end

local charflags = {__index = chflags, __call = function(t, a) return t[a] end}

local k = {}

k.SYS = arch.SYS

k.STD = setmetatable({
  IN_FILENO = 0,
  OUT_FILENO = 1,
  ERR_FILENO = 2,
  IN = 0,
  OUT = 1,
  ERR = 2,
}, stringflag)

-- sizes
k.PATH_MAX = 4096

-- open, fcntl TODO must set LARGEFILE if needed (note pipe2 only uses nonblock and cloexec)
k.O = {
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
  NOATIME   = octal('01000000'),
  CLOEXEC   = octal('02000000'),
  SYNC      = octal('04010000'),
}

k.O.FSYNC     = k.O.SYNC
k.O.RSYNC     = k.O.SYNC
k.O.NDELAY    = k.O.NONBLOCK

-- any use of a string will add largefile. If you use flags directly you need to add it yourself.
-- if there is a problem use a different table eg OPIPE
if ffi.abi("32bit") then
  k.O.LARGEFILE = octal('0100000')
  setmetatable(k.O, {
    __index = function(t, str)
      return bit.bor(flags(t, str), k.O.LARGEFILE)
    end,
    __call = multiflags.__call,
  })
else
  k.O.LARGEFILE = 0
  setmetatable(k.O, multiflags)
end

-- these are arch dependent!
if arch.oflags then arch.oflags(S)
else -- generic values from asm-generic
  k.O.DIRECT    = octal('040000')
  k.O.DIRECTORY = octal('0200000')
  k.O.NOFOLLOW  = octal('0400000')
end

k.OPIPE = setmetatable({
  NONBLOCK  = octal('04000'),
  CLOEXEC   = octal('02000000'),
}, multiflags)

-- modes and file types. note renamed second set from S_ to MODE_ plus note split
k.S = setmetatable({
  IFMT   = octal('0170000'),
  IFSOCK = octal('0140000'),
  IFLNK  = octal('0120000'),
  IFREG  = octal('0100000'),
  IFBLK  = octal('0060000'),
  IFDIR  = octal('0040000'),
  IFCHR  = octal('0020000'),
  IFIFO  = octal('0010000'),
  ISUID  = octal('0004000'),
  ISGID  = octal('0002000'),
  ISVTX  = octal('0001000'),
  IRWXU  = octal('00700'),
  IRUSR  = octal('00400'),
  IWUSR  = octal('00200'),
  IXUSR  = octal('00100'),
  IRWXG  = octal('00070'),
  IRGRP  = octal('00040'),
  IWGRP  = octal('00020'),
  IXGRP  = octal('00010'),
  IRWXO  = octal('00007'),
  IROTH  = octal('00004'),
  IWOTH  = octal('00002'),
  IXOTH  = octal('00001'),
}, multiflags)

k.MODE = setmetatable({
  IRWXU = octal('00700'),
  IRUSR = octal('00400'),
  IWUSR = octal('00200'),
  IXUSR = octal('00100'),
  IRWXG = octal('00070'),
  IRGRP = octal('00040'),
  IWGRP = octal('00020'),
  IXGRP = octal('00010'),
  IRWXO = octal('00007'),
  IROTH = octal('00004'),
  IWOTH = octal('00002'),
  IXOTH = octal('00001'),
}, multiflags)

-- access
k.OK = setmetatable({
  R = 4,
  W = 2,
  X = 1,
  F = 0,
}, charflags)

-- fcntl
k.F = setmetatable({
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
  k.F.GETLK64   = k.F.GETLK
  k.F.SETLK64   = k.F.SETLK
  k.F.SETLKW64  = k.F.SETLKW
else
  k.F.GETLK     = k.F.GETLK64
  k.F.SETLK     = k.F.SETLK64
  k.F.SETLKW    = k.F.SETLKW64
end

k.FD = setmetatable({
  CLOEXEC = 1,
}, multiflags)

-- note changed from F_ to FCNTL_LOCK
k.FCNTL_LOCK = setmetatable({
  RDLCK = 0,
  WRLCK = 1,
  UNLCK = 2,
}, stringflag)

-- lockf, changed from F_ to LOCKF_
k.LOCKF = setmetatable({
  ULOCK = 0,
  LOCK  = 1,
  TLOCK = 2,
  TEST  = 3,
}, stringflag)

--mmap
k.PROT = setmetatable({
  NONE  = 0x0,
  READ  = 0x1,
  WRITE = 0x2,
  EXEC  = 0x4,
  GROWSDOWN = 0x01000000,
  GROWSUP   = 0x02000000,
}, multiflags)

-- Sharing types
k.MAP = setmetatable({
  FILE       = 0,
  SHARED     = 0x01,
  PRIVATE    = 0x02,
  TYPE       = 0x0f,
  FIXED      = 0x10,
  ANONYMOUS  = 0x20,
--32BIT      = 0x40,
  GROWSDOWN  = 0x00100,
  DENYWRITE  = 0x00800,
  EXECUTABLE = 0x01000,
  LOCKED     = 0x02000,
  NORESERVE  = 0x04000,
  POPULATE   = 0x08000,
  NONBLOCK   = 0x10000,
  STACK      = 0x20000,
  HUGETLB    = 0x40000,
}, multiflags)

k.MAP["32BIT"]   = 0x40 -- starts with number
k.MAP.ANON       = k.MAP.ANONYMOUS

-- flags for `mlockall'.
k.MCL = setmetatable({
  CURRENT    = 1,
  FUTURE     = 2,
}, multiflags)

-- flags for `mremap'.
k.MREMAP = setmetatable({
  MAYMOVE = 1,
  FIXED   = 2,
}, multiflags)

-- madvise advice parameter
k.MADV = setmetatable({
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
k.POSIX_FADV = setmetatable({
  NORMAL       = 0,
  RANDOM       = 1,
  SEQUENTIAL   = 2,
  WILLNEED     = 3,
  DONTNEED     = 4,
  NOREUSE      = 5,
}, stringflag)

-- fallocate
k.FALLOC_FL = setmetatable({
  KEEP_SIZE  = 0x01,
  PUNCH_HOLE = 0x02,
}, stringflag)

-- getpriority, setpriority flags
k.PRIO = setmetatable({
  PROCESS = 0,
  PGRP = 1,
  USER = 2,
}, stringflag)

-- lseek
k.SEEK = setmetatable({
  SET = 0,
  CUR = 1,
  END = 2,
}, stringflag)

-- exit
k.EXIT = setmetatable({
  SUCCESS = 0,
  FAILURE = 1,
}, stringflag)

-- sigaction, note renamed SIGACT from SIG
k.SIGACT = setmetatable({
  ERR = -1,
  DFL =  0,
  IGN =  1,
  HOLD = 2,
}, stringflag)

k.SIG = setmetatable({
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
for k, v in pairs(k.SIG) do signals[v] = k end

k.SIG.IOT = 6
k.SIG.UNUSED     = 31
k.SIG.CLD        = k.SIG.CHLD
k.SIG.POLL       = k.SIG.IO

k.NSIG          = 65 -- TODO not sure we need

-- sigprocmask note renaming of SIG to SIGPM
k.SIGPM = setmetatable({
  BLOCK     = 0,
  UNBLOCK   = 1,
  SETMASK   = 2,
}, stringflag)

-- signalfd
k.SFD = setmetatable({
  CLOEXEC  = octal('02000000'),
  NONBLOCK = octal('04000'),
}, multiflags)

-- sockets note mix of single and multiple flags TODO code to handle temporarily using multi which is kind of ok
k.SOCK = setmetatable({
  STREAM    = 1,
  DGRAM     = 2,
  RAW       = 3,
  RDM       = 4,
  SEQPACKET = 5,
  DCCP      = 6,
  PACKET    = 10,

  CLOEXEC  = octal('02000000'),
  NONBLOCK = octal('04000'),
}, multiflags)

-- misc socket constants
k.SCM = setmetatable({
  RIGHTS = 0x01,
  CREDENTIALS = 0x02,
}, stringflag)

-- setsockopt
k.SOL = setmetatable({
  SOCKET     = 1,
  RAW        = 255,
  DECNET     = 261,
  X25        = 262,
  PACKET     = 263,
  ATM        = 264,
  AAL        = 265,
  IRDA       = 266,
}, stringflag)

k.SO = setmetatable({
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
  k.SO.PASSCRED    = 16
  k.SO.PEERCRED    = 17
  k.SO.RCVLOWAT    = 18
  k.SO.SNDLOWAT    = 19
  k.SO.RCVTIMEO    = 20
  k.SO.SNDTIMEO    = 21
end

-- Maximum queue length specifiable by listen.
k.SOMAXCONN = 128

-- shutdown
k.SHUT = setmetatable({
  RD   = 0,
  WR   = 1,
  RDWR = 2,
}, stringflag)

-- waitpid 3rd arg
k.W = setmetatable({
  NOHANG       = 1,
  UNTRACED     = 2,
  EXITED       = 4,
  CONTINUED    = 8,
  NOWAIT       = 0x01000000,
  NOTHREAD     = 0x20000000, -- __WNOTHREAD
  ALL          = 0x40000000, -- __WALL
  CLONE        = 0x80000000, -- __WCLONE
}, multiflags)

k.W.STOPPED      = k.W.UNTRACED

-- waitid
k.P = setmetatable({
  ALL  = 0,
  PID  = 1,
  PGID = 2,
}, stringflag)

-- struct siginfo, eg waitid
k.SI = setmetatable({
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

-- note renamed ILL to SIGILL etc as POLL clashes

k.SIGILL = setmetatable({
  ILLOPC = 1,
  ILLOPN = 2,
  ILLADR = 3,
  ILLTRP = 4,
  PRVOPC = 5,
  PRVREG = 6,
  COPROC = 7,
  BADSTK = 8,
}, stringflag)

k.SIGFPE = setmetatable({
  INTDIV = 1,
  INTOVF = 2,
  FLTDIV = 3,
  FLTOVF = 4,
  FLTUND = 5,
  FLTRES = 6,
  FLTINV = 7,
  FLTSUB = 8,
}, stringflag)

k.SIGSEGV = setmetatable({
  MAPERR = 1,
  ACCERR = 2,
}, stringflag)

k.SIGBUS = setmetatable({
  ADRALN = 1,
  ADRERR = 2,
  OBJERR = 3,
}, stringflag)

k.SIGTRAP = setmetatable({
  BRKPT = 1,
  TRACE = 2,
}, stringflag)

k.SIGCLD = setmetatable({
  EXITED    = 1,
  KILLED    = 2,
  DUMPED    = 3,
  TRAPPED   = 4,
  STOPPED   = 5,
  CONTINUED = 6,
}, stringflag)

k.SIGPOLL = setmetatable({
  IN  = 1,
  OUT = 2,
  MSG = 3,
  ERR = 4,
  PRI = 5,
  HUP = 6,
}, stringflag)

-- sigaction
k.SA = setmetatable({
  NOCLDSTOP = 0x00000001,
  NOCLDWAIT = 0x00000002,
  SIGINFO   = 0x00000004,
  ONSTACK   = 0x08000000,
  RESTART   = 0x10000000,
  NODEFER   = 0x40000000,
  RESETHAND = 0x80000000,
  RESTORER  = 0x04000000,
}, multiflags)

k.SA.NOMASK    = k.SA.NODEFER
k.SA.ONESHOT   = k.SA.RESETHAND

-- timers
k.ITIMER = setmetatable({
  REAL    = 0,
  VIRTUAL = 1,
  PROF    = 2,
}, stringflag)

-- clocks
k.CLOCK = setmetatable({
  REALTIME           = 0,
  MONOTONIC          = 1,
  PROCESS_CPUTIME_ID = 2,
  THREAD_CPUTIME_ID  = 3,
  MONOTONIC_RAW      = 4,
  REALTIME_COARSE    = 5,
  MONOTONIC_COARSE   = 6,
}, stringflag)

k.TIMER = setmetatable({
  ABSTIME = 1,
}, stringflag)

-- adjtimex
k.ADJ = setmetatable({
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
}, multiflags)

k.STA = setmetatable({
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
}, multiflags)

-- return values for adjtimex
k.TIME = setmetatable({
  OK         = 0,
  INS        = 1,
  DEL        = 2,
  OOP        = 3,
  WAIT       = 4,
  ERROR      = 5,
}, stringflag)

k.TIME.BAD        = k.TIME.ERROR

-- xattr
k.XATTR = setmetatable({
  CREATE  = 1,
  REPLACE = 2,
}, stringflag)

-- utime
k.UTIME = setmetatable({
  NOW  = bit.lshift(1, 30) - 1,
  OMIT = bit.lshift(1, 30) - 2,
}, stringflag)

-- ...at commands note these are valid in different combinations so different tables provided
k.AT_FDCWD = setmetatable({
  FDCWD = -100,
}, stringflag)

k.AT_REMOVEDIR = setmetatable({
  REMOVEDIR = 0x200,
}, multiflags)

k.AT_SYMLINK_FOLLOW = setmetatable({
  SYMLINK_FOLLOW = 0x400,
}, multiflags)

k.AT_SYMLINK_NOFOLLOW = setmetatable({
  SYMLINK_NOFOLLOW = 0x100,
}, multiflags)

k.AT_ACCESSAT = setmetatable({
  SYMLINK_NOFOLLOW = 0x100,
  AT_EACCESS       = 0x200,
}, multiflags)

k.AT_FSTATAT = setmetatable({
  SYMLINK_NOFOLLOW = 0x100,
  NO_AUTOMOUNT     = 0x800,
}, multiflags)

-- send, recv etc
k.MSG = setmetatable({
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
}, multiflags)

k.MSG.TRYHARD         = k.MSG.DONTROUTE

-- rlimit
k.RLIMIT = setmetatable({
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

k.RLIMIT.OFILE = k.RLIMIT.NOFILE

-- timerfd
k.TFD = setmetatable({
  CLOEXEC = octal("02000000"),
  NONBLOCK = octal("04000"),
}, multiflags)

k.TFD_TIMER = setmetatable({
  ABSTIME = 1,
}, stringflag)

-- poll
k.POLL = setmetatable({
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
}, multiflags)

-- epoll renamed from EPOLL_ to EPOLLCREATE
k.EPOLLCREATE = setmetatable({
  CLOEXEC = octal("02000000"),
  NONBLOCK = octal("04000"),
}, multiflags)

k.EPOLL = setmetatable({
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
}, multiflags)

k.EPOLL_CTL = setmetatable({
  ADD = 1,
  DEL = 2,
  MOD = 3,
}, stringflag)

-- splice etc
k.SPLICE_F = setmetatable({
  MOVE         = 1,
  NONBLOCK     = 2,
  MORE         = 4,
  GIFT         = 8,
}, multiflags)

-- aio - see /usr/include/linux/aio_abi.h
k.IOCB_CMD = setmetatable({
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

k.IOCB_FLAG_RESFD = 1

-- file types in directory
k.DT = setmetatable({
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
k.SYNC_FILE_RANGE = setmetatable({
  WAIT_BEFORE = 1,
  WRITE       = 2,
  WAIT_AFTER  = 4,
}, multiflags)

-- netlink
k.NETLINK = setmetatable({
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

-- see man netlink(7) for details. NLM_F_ is generic, actually use NLMSG_GET, NLMSG_NEW. TODO cleanup usage.
k.NLM_F = setmetatable({
  REQUEST = 1,
  MULTI   = 2,
  ACK     = 4,
  ECHO    = 8,
}, multiflags)

k.NLMSG_GETLINK = setmetatable({
  REQUEST = 1,
  MULTI   = 2,
  ACK     = 4,
  ECHO    = 8,
  ROOT    = 0x100,
  MATCH   = 0x200,
  ATOMIC  = 0x400,
}, multiflags)

k.NLMSG_GETLINK.DUMP = bit.bor(k.NLMSG_GETLINK.ROOT, k.NLMSG_GETLINK.MATCH)

k.NLMSG_NEWLINK = setmetatable({
  REQUEST = 1,
  MULTI   = 2,
  ACK     = 4,
  ECHO    = 8,
  REPLACE = 0x100,
  EXCL    = 0x200,
  CREATE  = 0x400,
  APPEND  = 0x800,
}, multiflags)

-- generic types. These are part of same sequence as RTM
k.NLMSG = setmetatable({
  NOOP     = 0x1,
  ERROR    = 0x2,
  DONE     = 0x3,
  OVERRUN  = 0x4,
}, stringflag)

-- routing
k.RTM = setmetatable({
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
k.IFLA = setmetatable({
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

k.IFLA_INET = setmetatable({
  UNSPEC = 0,
  CONF   = 1,
}, stringflag)

k.IFLA_INET6 = setmetatable({
  UNSPEC = 0,
  FLAGS  = 1,
  CONF   = 2,
  STATS  = 3,
  MCAST  = 4,
  CACHEINFO  = 5,
  ICMP6STATS = 6,
}, stringflag)

k.IFLA_INFO = setmetatable({
  UNSPEC = 0,
  KIND   = 1,
  DATA   = 2,
  XSTATS = 3,
}, stringflag)

k.IFLA_VLAN = setmetatable({
  UNSPEC = 0,
  ID     = 1,
  FLAGS  = 2,
  EGRESS_QOS  = 3,
  INGRESS_QOS = 4,
}, stringflag)

k.IFLA_VLAN_QOS = setmetatable({
  UNSPEC  = 0,
  MAPPING = 1,
}, stringflag)

k.IFLA_MACVLAN = setmetatable({
  UNSPEC = 0,
  MODE   = 1,
}, stringflag)

k.MACVLAN_MODE_PRIVATE = 1
k.MACVLAN_MODE_VEPA    = 2
k.MACVLAN_MODE_BRIDGE  = 4
k.MACVLAN_MODE_PASSTHRU = 8

k.IFLA_VF_INFO_UNSPEC = 0
k.IFLA_VF_INFO        = 1 -- TODO may have to rename IFLA_VF_INFO_INFO?

k.IFLA_VF = setmetatable({
  UNSPEC   = 0,
  MAC      = 1,
  VLAN     = 2,
  TX_RATE  = 3,
  SPOOFCHK = 4,
}, stringflag)

k.IFLA_VF_PORT_UNSPEC = 0
k.IFLA_VF_PORT        = 1 -- TODO may have to rename IFLA_VF_PORT_PORT?

k.IFLA_PORT = setmetatable({
  UNSPEC    = 0,
  VF        = 1,
  PROFILE   = 2,
  VSI_TYPE  = 3,
  INSTANCE_UUID = 4,
  HOST_UUID = 5,
  REQUEST   = 6,
  RESPONSE  = 7,
}, stringflag)

k.VETH_INFO = setmetatable({
  UNSPEC = 0,
  PEER   = 1,
}, stringflag)

k.PORT_PROFILE_MAX      =  40
k.PORT_UUID_MAX         =  16
k.PORT_SELF_VF          =  -1

k.PORT_REQUEST_PREASSOCIATE    = 0
k.PORT_REQUEST_PREASSOCIATE_RR = 1
k.PORT_REQUEST_ASSOCIATE       = 2
k.PORT_REQUEST_DISASSOCIATE    = 3

k.PORT_VDP_RESPONSE_SUCCESS = 0
k.PORT_VDP_RESPONSE_INVALID_FORMAT = 1
k.PORT_VDP_RESPONSE_INSUFFICIENT_RESOURCES = 2
k.PORT_VDP_RESPONSE_UNUSED_VTID = 3
k.PORT_VDP_RESPONSE_VTID_VIOLATION = 4
k.PORT_VDP_RESPONSE_VTID_VERSION_VIOALTION = 5
k.PORT_VDP_RESPONSE_OUT_OF_SYNC = 6
k.PORT_PROFILE_RESPONSE_SUCCESS = 0x100
k.PORT_PROFILE_RESPONSE_INPROGRESS = 0x101
k.PORT_PROFILE_RESPONSE_INVALID = 0x102
k.PORT_PROFILE_RESPONSE_BADSTATE = 0x103
k.PORT_PROFILE_RESPONSE_INSUFFICIENT_RESOURCES = 0x104
k.PORT_PROFILE_RESPONSE_ERROR = 0x105

-- from if_addr.h interface address types and flags
k.IFA = setmetatable({
  UNSPEC    = 0,
  ADDRESS   = 1,
  LOCAL     = 2,
  LABEL     = 3,
  BROADCAST = 4,
  ANYCAST   = 5,
  CACHEINFO = 6,
  MULTICAST = 7,
}, stringflag)

k.IFA_F = setmetatable({
  SECONDARY   = 0x01,
  NODAD       = 0x02,
  OPTIMISTIC  = 0x04,
  DADFAILED   = 0x08,
  HOMEADDRESS = 0x10,
  DEPRECATED  = 0x20,
  TENTATIVE   = 0x40,
  PERMANENT   = 0x80,
}, multiflags)

k.IFA_F.TEMPORARY   = k.IFA_F.SECONDARY

-- routing
k.RTN = setmetatable({
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

k.RTPROT = setmetatable({
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

k.RT_SCOPE = setmetatable({
  UNIVERSE = 0,
  SITE = 200,
  LINK = 253,
  HOST = 254,
  NOWHERE = 255,
}, stringflag)

k.RTM_F = setmetatable({
  NOTIFY          = 0x100,
  CLONED          = 0x200,
  EQUALIZE        = 0x400,
  PREFIX          = 0x800,
}, multiflags)

k.RT_TABLE = setmetatable({
  UNSPEC  = 0,
  COMPAT  = 252,
  DEFAULT = 253,
  MAIN    = 254,
  LOCAL   = 255,
  MAX     = 0xFFFFFFFF,
}, stringflag)

k.RTA = setmetatable({
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
k.RTF_UP          = 0x0001
k.RTF_GATEWAY     = 0x0002
k.RTF_HOST        = 0x0004
k.RTF_REINSTATE   = 0x0008
k.RTF_DYNAMIC     = 0x0010
k.RTF_MODIFIED    = 0x0020
k.RTF_MTU         = 0x0040
k.RTF_MSS         = k.RTF_MTU
k.RTF_WINDOW      = 0x0080
k.RTF_IRTT        = 0x0100
k.RTF_REJECT      = 0x0200

-- ipv6 route flags
k.RTF_DEFAULT     = 0x00010000
k.RTF_ALLONLINK   = 0x00020000
k.RTF_ADDRCONF    = 0x00040000
k.RTF_PREFIX_RT   = 0x00080000
k.RTF_ANYCAST     = 0x00100000
k.RTF_NONEXTHOP   = 0x00200000
k.RTF_EXPIRES     = 0x00400000
k.RTF_ROUTEINFO   = 0x00800000
k.RTF_CACHE       = 0x01000000
k.RTF_FLOW        = 0x02000000
k.RTF_POLICY      = 0x04000000
--#define RTF_PREF(pref)  ((pref) << 27)
--#define RTF_PREF_MASK   0x18000000
k.RTF_LOCAL       = 0x80000000

-- interface flags
k.IFF = setmetatable({
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
}, multiflags)

k.IFF.ALL        = 0xffffffff
k.IFF.NONE       = bit.bnot(0x7ffff) -- this is a bit of a fudge as zero should work, but does not for historical reasons see net/core/rtnetlink.c

k.IFF.VOLATILE = k.IFF.LOOPBACK + k.IFF.POINTOPOINT + k.IFF.BROADCAST + k.IFF.ECHO +
                 k.IFF.MASTER + k.IFF.SLAVE + k.IFF.RUNNING + k.IFF.LOWER_UP + k.IFF.DORMANT

-- not sure if we need these TODO another table as duplicated values
k.IFF_SLAVE_NEEDARP = 0x40
k.IFF_ISATAP        = 0x80
k.IFF_MASTER_ARPMON = 0x100
k.IFF_WAN_HDLC      = 0x200
k.IFF_XMIT_DST_RELEASE = 0x400
k.IFF_DONT_BRIDGE   = 0x800
k.IFF_DISABLE_NETPOLL    = 0x1000
k.IFF_MACVLAN_PORT       = 0x2000
k.IFF_BRIDGE_PORT = 0x4000
k.IFF_OVS_DATAPATH       = 0x8000
k.IFF_TX_SKB_SHARING     = 0x10000
k.IFF_UNICAST_FLT = 0x20000

-- netlink multicast groups
-- legacy names, which are masks.
k.RTMGRP = setmetatable({
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
}, multiflags)

-- rtnetlink multicast groups (bit numbers not masks)
k.RTNLGRP_NONE = 0
k.RTNLGRP_LINK = 1
k.RTNLGRP_NOTIFY = 2
k.RTNLGRP_NEIGH = 3
k.RTNLGRP_TC = 4
k.RTNLGRP_IPV4_IFADDR = 5
k.RTNLGRP_IPV4_MROUTE = 6
k.RTNLGRP_IPV4_ROUTE = 7
k.RTNLGRP_IPV4_RULE = 8
k.RTNLGRP_IPV6_IFADDR = 9
k.RTNLGRP_IPV6_MROUTE = 10
k.RTNLGRP_IPV6_ROUTE = 11
k.RTNLGRP_IPV6_IFINFO = 12
--k.RTNLGRP_DECNET_IFADDR = 13
k.RTNLGRP_NOP2 = 14
--k.RTNLGRP_DECNET_ROUTE = 15
--k.RTNLGRP_DECNET_RULE = 16
k.RTNLGRP_NOP4 = 17
k.RTNLGRP_IPV6_PREFIX = 18
k.RTNLGRP_IPV6_RULE = 19
k.RTNLGRP_ND_USEROPT = 20
k.RTNLGRP_PHONET_IFADDR = 21
k.RTNLGRP_PHONET_ROUTE = 22
k.RTNLGRP_DCB = 23

-- address families
k.AF = setmetatable({
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

k.AF.UNIX       = k.AF.LOCAL
k.AF.FILE       = k.AF.LOCAL
k.AF.ROUTE      = k.AF.NETLINK

-- arp types, which are also interface types for ifi_type
k.ARPHRD = setmetatable({
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

k.ARPHRD.HDLC     = k.ARPHRD.CISCO

-- IP
k.IPPROTO = setmetatable({
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
k.EFD = setmetatable({
  SEMAPHORE = 1,
  CLOEXEC = octal("02000000"),
  NONBLOCK = octal("04000"),
}, multiflags)

-- mount
k.MS = setmetatable({
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
}, multiflags)

-- fake flags
k.MS.RO = k.MS.RDONLY -- allow use of "ro" as flag as that is what /proc/mounts uses
k.MS.RW = 0           -- allow use of "rw" as flag as appears in /proc/mounts

-- flags to `msync'. - note was MS_ renamed to MSYNC_
k.MSYNC = setmetatable({
  ASYNC       = 1,
  INVALIDATE  = 2,
  SYNC        = 4,
}, multiflags)

-- TODO are these still used?
k.MNT_FORCE = 1
k.MNT_DETACH = 2
k.MNT_EXPIRE = 4
k.UMOUNT_NOFOLLOW = 8

-- one table for umount as it uses MNT_ and UMOUNT_ options
k.UMOUNT = setmetatable({
  FORCE    = 1,
  DETACH   = 2,
  EXPIRE   = 4,
  NOFOLLOW = 8,
}, multiflags)

-- reboot
k.LINUX_REBOOT_CMD = setmetatable({
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
k.CLONE = setmetatable({
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
}, multiflags)

-- inotify
-- flags note rename from IN_ to IN_INIT
k.IN_INIT = setmetatable({
  CLOEXEC = octal("02000000"),
  NONBLOCK = octal("04000"),
}, multiflags)

-- events
k.IN = setmetatable({
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
}, multiflags)

k.IN.CLOSE         = k.IN.CLOSE_WRITE + k.IN.CLOSE_NOWRITE
k.IN.MOVE          = k.IN.MOVED_FROM + k.IN.MOVED_TO

k.IN.ALL_EVENTS    = k.IN.ACCESS + k.IN.MODIFY + k.IN.ATTRIB + k.IN.CLOSE_WRITE
                       + k.IN.CLOSE_NOWRITE + k.IN.OPEN + k.IN.MOVED_FROM
                       + k.IN.MOVED_TO + k.IN.CREATE + k.IN.DELETE
                       + k.IN.DELETE_SELF + k.IN.MOVE_SELF

--prctl
k.PR = setmetatable({
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
k.PR_UNALIGN = setmetatable({
  NOPRINT   = 1,
  SIGBUS    = 2,
}, stringflag)

-- for PR fpemu
k.PR_FPEMU = setmetatable({
  NOPRINT     = 1,
  SIGFPE      = 2,
}, stringflag)

-- for PR fpexc
k.PR_FP_EXC = setmetatable({
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
k.PR_TIMING = setmetatable({
  STATISTICAL= 0,
  TIMESTAMP  = 1,
}, stringflag)

-- PR set endian
k.PR_ENDIAN = setmetatable({
  BIG         = 0,
  LITTLE      = 1,
  PPC_LITTLE  = 2,
}, stringflag)

-- PR TSC
k.PR_TSC = setmetatable({
  ENABLE         = 1,
  SIGSEGV        = 2,
}, stringflag)

k.PR_MCE_KILL = setmetatable({
  CLEAR     = 0,
  SET       = 1,
}, stringflag)

-- note rename, this is extra option see prctl code
k.PR_MCE_KILL_OPT = setmetatable({
  LATE         = 0,
  EARLY        = 1,
  DEFAULT      = 2,
}, stringflag)

-- capabilities
k.CAP = setmetatable({
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
k.SECCOMP_MODE = setmetatable({
  DISABLED = 0,
  STRICT   = 1,
  FILTER   = 2,
}, stringflag)

k.SECCOMP_RET_KILL      = 0x00000000
k.SECCOMP_RET_TRAP      = 0x00030000
k.SECCOMP_RET_ERRNO     = 0x00050000
k.SECCOMP_RET_TRACE     = 0x7ff00000
k.SECCOMP_RET_ALLOW     = 0x7fff0000

k.SECCOMP_RET_ACTION    = 0xffff0000 -- note unsigned 
k.SECCOMP_RET_DATA      = 0x0000ffff

-- termios
k.NCCS = 32

-- termios - c_cc characters
k.VINTR    = 0
k.VQUIT    = 1
k.VERASE   = 2
k.VKILL    = 3
k.VEOF     = 4
k.VTIME    = 5
k.VMIN     = 6
k.VSWTC    = 7
k.VSTART   = 8
k.VSTOP    = 9
k.VSUSP    = 10
k.VEOL     = 11
k.VREPRINT = 12
k.VDISCARD = 13
k.VWERASE  = 14
k.VLNEXT   = 15
k.VEOL2    = 16

-- termios - c_iflag bits
k.IGNBRK  = octal('0000001')
k.BRKINT  = octal('0000002')
k.IGNPAR  = octal('0000004')
k.PARMRK  = octal('0000010')
k.INPCK   = octal('0000020')
k.ISTRIP  = octal('0000040')
k.INLCR   = octal('0000100')
k.IGNCR   = octal('0000200')
k.ICRNL   = octal('0000400')
k.IUCLC   = octal('0001000')
k.IXON    = octal('0002000')
k.IXANY   = octal('0004000')
k.IXOFF   = octal('0010000')
k.IMAXBEL = octal('0020000')
k.IUTF8   = octal('0040000')

-- termios - c_oflag bits
k.OPOST  = octal('0000001')
k.OLCUC  = octal('0000002')
k.ONLCR  = octal('0000004')
k.OCRNL  = octal('0000010')
k.ONOCR  = octal('0000020')
k.ONLRET = octal('0000040')
k.OFILL  = octal('0000100')
k.OFDEL  = octal('0000200')
k.NLDLY  = octal('0000400')
k.NL0    = octal('0000000')
k.NL1    = octal('0000400')
k.CRDLY  = octal('0003000')
k.CR0    = octal('0000000')
k.CR1    = octal('0001000')
k.CR2    = octal('0002000')
k.CR3    = octal('0003000')
k.TABDLY = octal('0014000')
k.TAB0   = octal('0000000')
k.TAB1   = octal('0004000')
k.TAB2   = octal('0010000')
k.TAB3   = octal('0014000')
k.BSDLY  = octal('0020000')
k.BS0    = octal('0000000')
k.BS1    = octal('0020000')
k.FFDLY  = octal('0100000')
k.FF0    = octal('0000000')
k.FF1    = octal('0100000')
k.VTDLY  = octal('0040000')
k.VT0    = octal('0000000')
k.VT1    = octal('0040000')
k.XTABS  = octal('0014000')

-- TODO rework this with functions in a metatable
local bits_speed_map = { }
local speed_bits_map = { }
local function defspeed(speed, bits)
  bits = octal(bits)
  bits_speed_map[bits] = speed
  speed_bits_map[speed] = bits
  k['B'..speed] = bits
end
function k.bits_to_speed(bits)
  local speed = bits_speed_map[bits]
  if not speed then error("unknown speedbits: " .. bits) end
  return speed
end
function k.speed_to_bits(speed)
  local bits = speed_bits_map[speed]
  if not bits then error("unknown speed: " .. speed) end
  return bits
end

-- termios - c_cflag bit meaning
k.CBAUD      = octal('0010017')
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
k.EXTA       = k.B19200
k.EXTB       = k.B38400
k.CSIZE      = octal('0000060')
k.CS5        = octal('0000000')
k.CS6        = octal('0000020')
k.CS7        = octal('0000040')
k.CS8        = octal('0000060')
k.CSTOPB     = octal('0000100')
k.CREAD      = octal('0000200')
k.PARENB     = octal('0000400')
k.PARODD     = octal('0001000')
k.HUPCL      = octal('0002000')
k.CLOCAL     = octal('0004000')
k.CBAUDEX    = octal('0010000')
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
k.__MAX_BAUD = k.B4000000
k.CIBAUD     = octal('002003600000') -- input baud rate (not used)
k.CMSPAR     = octal('010000000000') -- mark or space (stick) parity
k.CRTSCTS    = octal('020000000000') -- flow control

-- termios - c_lflag bits
k.ISIG    = octal('0000001')
k.ICANON  = octal('0000002')
k.XCASE   = octal('0000004')
k.ECHO    = octal('0000010')
k.ECHOE   = octal('0000020')
k.ECHOK   = octal('0000040')
k.ECHONL  = octal('0000100')
k.NOFLSH  = octal('0000200')
k.TOSTOP  = octal('0000400')
k.ECHOCTL = octal('0001000')
k.ECHOPRT = octal('0002000')
k.ECHOKE  = octal('0004000')
k.FLUSHO  = octal('0010000')
k.PENDIN  = octal('0040000')
k.IEXTEN  = octal('0100000')

-- termios - tcflow() and TCXONC use these. renamed from TC to TCFLOW
k.TCFLOW = setmetatable({
  OOFF = 0,
  OON  = 1,
  IOFF = 2,
  ION  = 3,
}, stringflag)

-- termios - tcflush() and TCFLSH use these. renamed from TC to TCFLUSH
k.TCFLUSH = setmetatable({
  IFLUSH  = 0,
  OFLUSH  = 1,
  IOFLUSH = 2,
}, stringflag)

-- termios - tcsetattr uses these
k.TCSA = setmetatable({
  NOW   = 0,
  DRAIN = 1,
  FLUSH = 2,
}, stringflag)

-- TIOCM ioctls
k.TIOCM_LE  = 0x001
k.TIOCM_DTR = 0x002
k.TIOCM_RTS = 0x004
k.TIOCM_ST  = 0x008
k.TIOCM_SR  = 0x010
k.TIOCM_CTS = 0x020
k.TIOCM_CAR = 0x040
k.TIOCM_RNG = 0x080
k.TIOCM_DSR = 0x100
k.TIOCM_CD  = k.TIOCM_CAR
k.TIOCM_RI  = k.TIOCM_RNG

-- ioctls, filling in as needed
k.SIOCGIFINDEX   = 0x8933

k.SIOCBRADDBR    = 0x89a0
k.SIOCBRDELBR    = 0x89a1
k.SIOCBRADDIF    = 0x89a2
k.SIOCBRDELIF    = 0x89a3

k.TIOCMGET       = 0x5415
k.TIOCMBIS       = 0x5416
k.TIOCMBIC       = 0x5417
k.TIOCMSET       = 0x5418
k.TIOCGPTN	 = 0x80045430LL
k.TIOCSPTLCK	 = 0x40045431LL

-- sysfs values
k.SYSFS_BRIDGE_ATTR        = "bridge"
k.SYSFS_BRIDGE_FDB         = "brforward"
k.SYSFS_BRIDGE_PORT_SUBDIR = "brif"
k.SYSFS_BRIDGE_PORT_ATTR   = "brport"
k.SYSFS_BRIDGE_PORT_LINK   = "bridge"

-- sizes -- should we export?
local HOST_NAME_MAX = 64
local IFNAMSIZ      = 16
local IFHWADDRLEN   = 6

-- errors
k.E = {
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
k.E.EWOULDBLOCK    = k.E.EAGAIN
k.E.EDEADLOCK      = k.E.EDEADLK
k.E.ENOATTR        = k.E.ENODATA

return k

