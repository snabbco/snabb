local ffi = require "ffi"
local bit = require "bit"

local L = {} -- our module exported functions


-- from bits/typesizes.h - underlying types, create as typedefs, mostly fix size.
--[[
#define __DEV_T_TYPE            __UQUAD_TYPE
#define __UID_T_TYPE            __U32_TYPE
#define __GID_T_TYPE            __U32_TYPE
#define __INO_T_TYPE            __ULONGWORD_TYPE
#define __INO64_T_TYPE          __UQUAD_TYPE
#define __MODE_T_TYPE           __U32_TYPE
#define __NLINK_T_TYPE          __UWORD_TYPE
#define __OFF_T_TYPE            __SLONGWORD_TYPE
#define __OFF64_T_TYPE          __SQUAD_TYPE
#define __PID_T_TYPE            __S32_TYPE
#define __RLIM_T_TYPE           __ULONGWORD_TYPE
#define __RLIM64_T_TYPE         __UQUAD_TYPE
#define __BLKCNT_T_TYPE         __SLONGWORD_TYPE
#define __BLKCNT64_T_TYPE       __SQUAD_TYPE
#define __FSBLKCNT_T_TYPE       __ULONGWORD_TYPE
#define __FSBLKCNT64_T_TYPE     __UQUAD_TYPE
#define __FSFILCNT_T_TYPE       __ULONGWORD_TYPE
#define __FSFILCNT64_T_TYPE     __UQUAD_TYPE
#define __ID_T_TYPE             __U32_TYPE
#define __CLOCK_T_TYPE          __SLONGWORD_TYPE
#define __TIME_T_TYPE           __SLONGWORD_TYPE
#define __USECONDS_T_TYPE       __U32_TYPE
#define __SUSECONDS_T_TYPE      __SLONGWORD_TYPE
#define __DADDR_T_TYPE          __S32_TYPE
#define __SWBLK_T_TYPE          __SLONGWORD_TYPE
#define __KEY_T_TYPE            __S32_TYPE
#define __CLOCKID_T_TYPE        __S32_TYPE
#define __TIMER_T_TYPE          void *
#define __BLKSIZE_T_TYPE        __SLONGWORD_TYPE
#define __FSID_T_TYPE           struct { int __val[2]; }
#define __SSIZE_T_TYPE          __SWORD_TYPE

/* Number of descriptors that can fit in an `fd_set'.  */
#define __FD_SETSIZE            1024
]]

--[[
/* The machine-dependent file <bits/typesizes.h> defines __*_T_TYPE
   macros for each of the OS types we define below.  The definitions
   of those macros must use the following macros for underlying types.
   We define __S<SIZE>_TYPE and __U<SIZE>_TYPE for the signed and unsigned
   variants of each of the following integer types on this machine.

        16              -- "natural" 16-bit type (always short)
        32              -- "natural" 32-bit type (always int)
        64              -- "natural" 64-bit type (long or long long)
        LONG32          -- 32-bit type, traditionally long
        QUAD            -- 64-bit type, always long long
        WORD            -- natural type of __WORDSIZE bits (int or long)
        LONGWORD        -- type of __WORDSIZE bits, traditionally long

   We distinguish WORD/LONGWORD, 32/LONG32, and 64/QUAD so that the
   conventional uses of `long' or `long long' type modifiers match the
   types we define, even when a less-adorned type would be the same size.
   This matters for (somewhat) portably writing printf/scanf formats for
   these types, where using the appropriate l or ll format modifiers can
   make the typedefs and the formats match up across all GNU platforms.  If
   we used `long' when it's 64 bits where `long long' is expected, then the
   compiler would warn about the formats not matching the argument types,
   and the programmer changing them to shut up the compiler would break the
   program's portability.

   Here we assume what is presently the case in all the GCC configurations
   we support: long long is always 64 bits, long is always word/address size,
   and int is always 32 bits.  */

#define __S16_TYPE              short int
#define __U16_TYPE              unsigned short int
#define __S32_TYPE              int
#define __U32_TYPE              unsigned int
#define __SLONGWORD_TYPE        long int
#define __ULONGWORD_TYPE        unsigned long int
#if __WORDSIZE == 32
# define __SQUAD_TYPE           __quad_t
# define __UQUAD_TYPE           __u_quad_t
# define __SWORD_TYPE           int
# define __UWORD_TYPE           unsigned int
# define __SLONG32_TYPE         long int
# define __ULONG32_TYPE         unsigned long int
# define __S64_TYPE             __quad_t
# define __U64_TYPE             __u_quad_t
/* We want __extension__ before typedef's that use nonstandard base types
   such as `long long' in C89 mode.  */
# define __STD_TYPE             __extension__ typedef
#elif __WORDSIZE == 64
# define __SQUAD_TYPE           long int
# define __UQUAD_TYPE           unsigned long int
# define __SWORD_TYPE           long int
# define __UWORD_TYPE           unsigned long int
# define __SLONG32_TYPE         int
# define __ULONG32_TYPE         unsigned int
# define __S64_TYPE             long int
# define __U64_TYPE             unsigned long int
]]

-- for our purposes, we will therefore make the long ones depend on arch, rest are fixed

L.O_ACCMODE = 0x0003
L.O_RDONLY = 0x00
L.O_WRONLY = 0x01
L.O_RDWR = 0x02
L.O_CREAT = 0x0100
L.O_EXCL = 0x0200
L.O_NOCTTY = 0x0400
L.O_TRUNC = 0x01000
L.O_APPEND = 0x02000
L.O_NONBLOCK = 0x04000
L.O_NDELAY = L.O_NONBLOCK
L.O_SYNC = 0x04010000
L.O_FSYNC = L.O_SYNC
L.O_ASYNC = 0x020000
L.O_DIRECTORY = 0x0200000
L.O_NOFOLLOW = 0x0400000
L.O_CLOEXEC = 0x02000000
L.O_DIRECT = 0x040000
L.O_NOATIME = 0x01000000
L.O_DSYNC = 0x010000
L.O_RSYNC = L.O_SYNC

if ffi.abi('32bit') then L.O_LARGEFILE = 0x0100000 else L.O_LARGEFILE = 0x0 end

L.symerror = {
'EPERM',
'ENOENT',
'ESRCH',
'EINTR',
'EIO',
'ENXIO',
'E2BIG',
'ENOEXEC',
'EBADF',
'ECHILD',
'EAGAIN',
'ENOMEM',
'EACCES',
'EFAULT',
'ENOTBLK',
'EBUSY',
'EEXIST',
'EXDEV',
'ENODEV',
'ENOTDIR',
'EISDIR',
'EINVAL',
'ENFILE',
'EMFILE',
'ENOTTY',
'ETXTBSY',
'EFBIG',
'ENOSPC',
'ESPIPE',
'EROFS',
'EMLINK',
'EPIPE',
'EDOM',
'ERANGE'
}

rsymerror = {}
for i, v in ipairs(L.symerror) do rsymerror[v] = i end -- reverse mapping

local ecache = {}

function L.strerror(errno)
  local s = ecache[errno]
  if s == nil then
    s = ffi.string(ffi.C.strerror(errno))
    ecache[errno] = s
  end
  return s, errno
end

--not used
function strerror2(name)
  return L.strerror(rsymerror[name])
end

-- typedefs for word size independent types
ffi.cdef[[
typedef uint32_t mode_t;



]]

if ffi.abi('32bit') then
ffi.cdef[[
typedef uint32_t size_t;
typedef int32_t ssize_t
]]
else ffi.cdef[[
typedef uint64_t size_t;
typedef int64_t ssize_t;
]]
end

-- functions only used internally
ffi.cdef[[
char *strerror(int errnum);
]]

-- exported functions
ffi.cdef[[
int close(int fd);
int open(const char *pathname, int flags, mode_t mode);
ssize_t read(int fd, void *buf, size_t count);


int creat(const char *pathname, mode_t mode);
]]



-- handle errors. do we need to be careful with non int return values eg pointers?? probably yes!

function errorret()
  return nil, L.strerror(ffi.errno())
end

-- for int returns
function intret(ret)
  if ret == -1 then
    return errorret()
  end
  return ret
end

-- used for no return value in Lua
-- not used!
function bret(ret)
  if ret == -1 then
    return errorret()
  end
  return true
end



--get fd from standard string, integer, or cdata
function getfd(d)
  if type(d) == 'number' then return d end
  if type(d) == 'cdata' then return d[0] end -- use ffi type test when have special type
  if type(d) == 'string' then
    if d == 'stdin' or d == 'STDIN_FILENO' then return 0 end
    if d == 'stdout' or d == 'STDOUT_FILENO' then return 1 end
    if d == 'stderr' or d == 'STDERR_FILENO' then return 2 end
  end
end

function L.close(d)
  local fd = getfd(d)

  if d == nil then return nil, "Invalid file descriptor" end

  local ret = ffi.C.close(fd)

  if ret == -1 then
    return errorret()
  end

  if type(d) == 'cdata' then
    ffi.gc(d, nil) -- remove gc finalizer as now closed; should we also remove if get EBADF?
  end

  return true
end

function L.open(pathname, flags, mode)
  local errno, s = nil, nil
  local ret = ffi.C.open(pathname, flags, mode or 0)
  if ret == -1 then
    return errorret()
  end
  local fd = ffi.gc(ffi.new("int[1]"), L.close)
  fd[0] = ret
  return fd
end

function L.read(d, buf, len)
  local fd = getfd(d)

  if d == nil then return nil, "Invalid file descriptor" end

  -- if no buffer provided, we could allocate one and return a Lua string instead
  
  ret = ffi.C.read(fd, buf, len)

  return intret(ret)
end



return L


