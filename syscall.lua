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

function octal(s)
  local p = 1
  local o = 0
  local z = string.byte("0")
  for i = #s, 1, -1 do
    o = o + (string.byte(s, i) - z) * p
    p = p * 8
  end
  return o
end

-- 
L.O_ACCMODE = octal('0003')
L.O_RDONLY = octal('00')
L.O_WRONLY = octal('01')
L.O_RDWR = octal('02')
L.O_CREAT = octal('0100')
L.O_EXCL = octal('0200')
L.O_NOCTTY = octal('0400')
L.O_TRUNC = octal('01000')
L.O_APPEND = octal('02000')
L.O_NONBLOCK = octal('04000')
L.O_NDELAY = L.O_NONBLOCK
L.O_SYNC = octal('04010000')
L.O_FSYNC = L.O_SYNC
L.O_ASYNC = octal('020000')
L.O_DIRECTORY = octal('0200000')
L.O_NOFOLLOW = octal('0400000')
L.O_CLOEXEC = octal('02000000')
L.O_DIRECT = octal('040000')
L.O_NOATIME = octal('01000000')
L.O_DSYNC = octal('010000')
L.O_RSYNC = L.O_SYNC

-- modes
L.S_IRWXU = octal('00700') -- user (file owner) has read, write and execute permission
L.S_IRUSR = octal('00400') -- user has read permission
L.S_IWUSR = octal('00200') -- user has write permission
L.S_IXUSR = octal('00100') -- user has execute permission
L.S_IRWXG = octal('00070') -- group has read, write and execute permission
L.S_IRGRP = octal('00040') -- group has read permission
L.S_IWGRP = octal('00020') -- group has write permission
L.S_IXGRP = octal('00010') -- group has execute permission
L.S_IRWXO = octal('00007') -- others have read, write and execute permission
L.S_IROTH = octal('00004') -- others have read permission
L.S_IWOTH = octal('00002') -- others have write permission
L.S_IXOTH = octal('00001') -- others have execute permission

if ffi.abi('32bit') then L.O_LARGEFILE = octal('0100000') else L.O_LARGEFILE = 0 end

-- seek
L.SEEK_SET = 0       -- Seek from beginning of file.
L.SEEK_CUR = 1       -- Seek from current position.
L.SEEK_END = 2       -- Seek from end of file.

-- access
L.R_OK = 4               -- Test for read permission.
L.W_OK = 2               -- Test for write permission.
L.X_OK = 1               -- Test for execute permission.
L.F_OK = 0               -- Test for existence.

L.symerror = {
'EPERM',  'ENOENT', 'ESRCH',   'EINTR',
'EIO',    'ENXIO',  'E2BIG',   'ENOEXEC',
'EBADF',  'ECHILD', 'EAGAIN',  'ENOMEM',
'EACCES', 'EFAULT', 'ENOTBLK', 'EBUSY',
'EEXIST', 'EXDEV',  'ENODEV',  'ENOTDIR',
'EISDIR', 'EINVAL', 'ENFILE',  'EMFILE',
'ENOTTY', 'ETXTBSY','EFBIG',   'ENOSPC',
'ESPIPE', 'EROFS',  'EMLINK',  'EPIPE',
'EDOM',   'ERANGE'
}

rsymerror = {}
for i, v in ipairs(L.symerror) do rsymerror[v] = i end -- reverse mapping

local ecache = {}

-- caching version of strerror to save interning
function L.strerror(errno)
  local s = ecache[errno]
  if s == nil then
    s = ffi.string(ffi.C.strerror(errno))
    ecache[errno] = s
  end
  return s, errno
end

-- standard error return
function errorret()
  return nil, L.strerror(ffi.errno())
end

-- for int returns -- fix to make sure tests against -1LL on 64 bit arch
function retint(ret)
  if ret == -1 then
    return errorret()
  end
  return ret
end

-- used for no return value, return true for use of assert
function retbool(ret)
  if ret == -1 then
    return errorret()
  end
  return true
end


-- typedefs for word size independent types
ffi.cdef[[
typedef uint32_t mode_t;

]]

-- typedefs based on word length, using int/uint or long as these are both word sized
ffi.cdef[[
typedef unsigned int size_t;
typedef int ssize_t;
typedef long off_t;
]]

-- functions only used internally
ffi.cdef[[
char *strerror(int errnum);
]]

-- exported functions
ffi.cdef[[
int close(int fd);
int open(const char *pathname, int flags, mode_t mode);
int chdir(const char *path);


ssize_t read(int fd, void *buf, size_t count);
ssize_t write(int fd, const void *buf, size_t count);
ssize_t pread(int fd, void *buf, size_t count, off_t offset);
ssize_t pwrite(int fd, const void *buf, size_t count, off_t offset);
off_t lseek(int fd, off_t offset, int whence);

int fchdir(int fd);
int fsync(int fd);
int fdatasync(int fd);

int unlink(const char *pathname);
int access(const char *pathname, int mode);

]]


--[[ -- not defined yet
 int creat(const char *pathname, mode_t mode); -- defined using open instead
]]


local fd_t -- type for a file descriptor

--get fd from standard string, integer, or cdata
function getfd(d)
  if type(d) == 'number' then return d end
  if ffi.istype(fd_t, d) then return d.fd end
  if type(d) == 'string' then
    if d == 'stdin' or d == 'STDIN_FILENO' then return 0 end
    if d == 'stdout' or d == 'STDOUT_FILENO' then return 1 end
    if d == 'stderr' or d == 'STDERR_FILENO' then return 2 end
  end
end

function L.open(pathname, flags, mode)
  local ret = ffi.C.open(pathname, flags, mode or 0)
  if ret == -1 then
    return errorret()
  end
  return ffi.gc(ffi.new(fd_t, ret), L.close)
end

function L.close(d)
  local ret = ffi.C.close(getfd(d))

  if ret == -1 then
    return errorret()
  end

  if ffi.istype(fd_t, d) then
    ffi.gc(d, nil) -- remove gc finalizer as now closed; should we also remove if get EBADF?
  end

  return true
end

function L.creat(pathname, mode) return L.open(pathname, bit.bor(L.O_CREAT, L.O_WRONLY, L.O_TRUNC), mode) end
function L.unlink(pathname) return retbool(ffi.C.unlink(pathname)) end
function L.access(pathname, mode) return retbool(ffi.C.access(pathname, mode)) end
function L.chdir(path) return retbool(ffi.C.chdir(path)) end

function L.read(d, buf, count) return retint(ffi.C.read(getfd(d), buf, count)) end
function L.write(d, buf, count) return retint(ffi.C.write(getfd(d), buf, count)) end
function L.pread(d, buf, count, offset) return retint(ffi.C.pread(getfd(d), buf, count, offset)) end
function L.pwrite(d, buf, count, offset) return retint(ffi.C.pwrite(getfd(d), buf, count, offset)) end
function L.lseek(d, offset, whence) return retint(ffi.C.lseek(getfd(d), offset, whence)) end

function L.fchdir(d) return retbool(ffi.C.fchdir(getfd(d))) end
function L.fsync(d) return retbool(ffi.C.fsync(getfd(d))) end
function L.fdatasync(d) return retbool(ffi.C.fdatasync(getfd(d))) end

-- methods on an fd
-- add __gc method here, and remove gc function

local fdmethods = {'close', 'read', 'write', 'pread', 'pwrite', 'lseek', 'fchdir', 'fsync', 'fdatasync'}
local fmeth = {}
for i, v in ipairs(fdmethods) do fmeth[v] = L[v] end

fd_t = ffi.metatype("struct {int fd;}", {__index = fmeth})

return L


