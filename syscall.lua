local ffi = require "ffi"
local bit = require "bit"

local S = {} -- exported functions

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

local octal

function octal(s) return tonumber(s, 8) end

-- open
S.O_ACCMODE   = octal('0003')
S.O_RDONLY    = octal('00')
S.O_WRONLY    = octal('01')
S.O_RDWR      = octal('02')
S.O_CREAT     = octal('0100')
S.O_EXCL      = octal('0200')
S.O_NOCTTY    = octal('0400')
S.O_TRUNC     = octal('01000')
S.O_APPEND    = octal('02000')
S.O_NONBLOCK  = octal('04000')
S.O_NDELAY    = S.O_NONBLOCK
S.O_SYNC      = octal('04010000')
S.O_FSYNC     = S.O_SYNC
S.O_ASYNC     = octal('020000')
S.O_DIRECTORY = octal('0200000')
S.O_NOFOLLOW  = octal('0400000')
S.O_CLOEXEC   = octal('02000000')
S.O_DIRECT    = octal('040000')
S.O_NOATIME   = octal('01000000')
S.O_DSYNC     = octal('010000')
S.O_RSYNC     = S.O_SYNC

-- modes
S.S_IFMT   = octal('0170000') -- bit mask for the file type bit fields
S.S_IFSOCK = octal('0140000') -- socket
S.S_IFLNK  = octal('0120000') -- symbolic link
S.S_IFREG  = octal('0100000') -- regular file
S.S_IFBLK  = octal('0060000') -- block device
S.S_IFDIR  = octal('0040000') -- directory
S.S_IFCHR  = octal('0020000') -- character device
S.S_IFIFO  = octal('0010000') -- FIFO
S.S_ISUID  = octal('0004000') -- set UID bit
S.S_ISGID  = octal('0002000') -- set-group-ID bit
S.S_ISVTX  = octal('0001000') -- sticky bit

S.S_IRWXU = octal('00700') -- user (file owner) has read, write and execute permission
S.S_IRUSR = octal('00400') -- user has read permission
S.S_IWUSR = octal('00200') -- user has write permission
S.S_IXUSR = octal('00100') -- user has execute permission
S.S_IRWXG = octal('00070') -- group has read, write and execute permission
S.S_IRGRP = octal('00040') -- group has read permission
S.S_IWGRP = octal('00020') -- group has write permission
S.S_IXGRP = octal('00010') -- group has execute permission
S.S_IRWXO = octal('00007') -- others have read, write and execute permission
S.S_IROTH = octal('00004') -- others have read permission
S.S_IWOTH = octal('00002') -- others have write permission
S.S_IXOTH = octal('00001') -- others have execute permission

if ffi.abi('32bit') then S.O_LARGEFILE = octal('0100000') else S.O_LARGEFILE = 0 end

-- seek
S.SEEK_SET = 0       -- Seek from beginning of file.
S.SEEK_CUR = 1       -- Seek from current position.
S.SEEK_END = 2       -- Seek from end of file.

-- access
S.R_OK = 4               -- Test for read permission.
S.W_OK = 2               -- Test for write permission.
S.X_OK = 1               -- Test for execute permission.
S.F_OK = 0               -- Test for existence.

--mmap
S.PROT_READ  = 0x1             -- Page can be read.
S.PROT_WRITE = 0x2             -- Page can be written.
S.PROT_EXEC  = 0x4             -- Page can be executed.
S.PROT_NONE  = 0x0             -- Page can not be accessed.
S.PROT_GROWSDOWN = 0x01000000  -- Extend change to start of growsdown vma (mprotect only).
S.PROT_GROWSUP   = 0x02000000  -- Extend change to start of growsup vma (mprotect only).

-- Sharing types (must choose one and only one of these).
S.MAP_SHARED  = 0x01            -- Share changes.
S.MAP_PRIVATE = 0x02            -- Changes are private.
S.MAP_TYPE    = 0x0f            -- Mask for type of mapping.

S.MAP_FIXED     = 0x10             -- Interpret addr exactly.
S.MAP_FILE      = 0
S.MAP_ANONYMOUS = 0x20             -- Don't use a file.
S.MAP_ANON      = S.MAP_ANONYMOUS
S.MAP_32BIT     = 0x40             -- Only give out 32-bit addresses.

-- These are Linux-specific.
S.MAP_GROWSDOWN  = 0x00100         -- Stack-like segment.
S.MAP_DENYWRITE  = 0x00800         -- ETXTBSY
S.MAP_EXECUTABLE = 0x01000         -- Mark it as an executable.
S.MAP_LOCKED     = 0x02000         -- Lock the mapping.
S.MAP_NORESERVE  = 0x04000         -- Don't check for reservations.
S.MAP_POPULATE   = 0x08000         -- Populate (prefault) pagetables.
S.MAP_NONBLOCK   = 0x10000         -- Do not block on IO.
S.MAP_STACK      = 0x20000         -- Allocation is for a stack.
S.MAP_HUGETLB    = 0x40000         -- Create huge page mapping.

-- Flags to `msync'.
S.MS_ASYNC       = 1               -- Sync memory asynchronously.
S.MS_SYNC        = 4               -- Synchronous memory sync.
S.MS_INVALIDATE  = 2               -- Invalidate the caches.

-- Flags for `mlockall'.
S.MCL_CURRENT    = 1               -- Lock all currently mapped pages.
S.MCL_FUTURE     = 2               -- Lock all additions to address space.

-- Flags for `mremap'.
S.MREMAP_MAYMOVE = 1
S.MREMAP_FIXED   = 2

-- Advice to `madvise'.
S.MADV_NORMAL      = 0     -- No further special treatment.
S.MADV_RANDOM      = 1     -- Expect random page references.
S.MADV_SEQUENTIAL  = 2     -- Expect sequential page references.
S.MADV_WILLNEED    = 3     -- Will need these pages.
S.MADV_DONTNEED    = 4     -- Don't need these pages.
S.MADV_REMOVE      = 9     -- Remove these pages and resources.
S.MADV_DONTFORK    = 10    -- Do not inherit across fork.
S.MADV_DOFORK      = 11    -- Do inherit across fork.
S.MADV_MERGEABLE   = 12    -- KSM may merge identical pages.
S.MADV_UNMERGEABLE = 13    -- KSM may not merge identical pages.
S.MADV_HUGEPAGE    = 14    -- Worth backing with hugepages.
S.MADV_NOHUGEPAGE  = 15    -- Not worth backing with hugepages.
S.MADV_HWPOISON    = 100   -- Poison a page for testing.

-- The POSIX people had to invent similar names for the same things.
S.POSIX_MADV_NORMAL      = 0 -- No further special treatment.
S.POSIX_MADV_RANDOM      = 1 -- Expect random page references.
S.POSIX_MADV_SEQUENTIAL  = 2 -- Expect sequential page references.
S.POSIX_MADV_WILLNEED    = 3 -- Will need these pages.
S.POSIX_MADV_DONTNEED    = 4 -- Don't need these pages.

S.symerror = {
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

function S.strerror(errno)
  return ffi.string(ffi.C.strerror(errno)), errno
end

local errorret, retint, retbool, retptr, retfd, getfd

-- standard error return
function errorret()
  return nil, S.strerror(ffi.errno())
end

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

-- used for pointer returns, null is failure
-- not used
function retptr(ret)
  if ret == nil then
     return errorret()
  end
  return ret
end

-- define types
ffi.cdef[[
// typedefs for word size independent types
typedef uint32_t mode_t;
typedef uint32_t uid_t;
typedef uint32_t gid_t;

typedef uint64_t dev_t;

// typedefs which are word length
typedef unsigned long size_t;
typedef long ssize_t;
typedef long off_t;
typedef long time_t;
typedef unsigned long ino_t;
typedef unsigned long nlink_t;
typedef long blksize_t;
typedef long blkcnt_t;

// structs
struct timespec {
  time_t tv_sec;        /* seconds */
  long   tv_nsec;       /* nanoseconds */
};
]]

-- stat structure is architecture dependent in Linux
-- this is the way glibc versions stat via __xstat, may need to change for other libc, eg if define stat as a non inline function
local STAT_VER_LINUX

if ffi.abi("32bit") then
STAT_VER_LINUX = 3
ffi.cdef[[
struct stat {
  dev_t st_dev;                       /* Device.  */
  unsigned short int __pad1;
  ino_t __st_ino;                     /* 32bit file serial number.    */
  mode_t st_mode;                     /* File mode.  */
  nlink_t st_nlink;                   /* Link count.  */
  uid_t st_uid;                       /* User ID of the file's owner. */
  gid_t st_gid;                       /* Group ID of the file's group.*/
  dev_t st_rdev;                      /* Device number, if device.  */
  unsigned short int __pad2;
  off_t st_size;                      /* Size of file, in bytes.  */
  blksize_t st_blksize;               /* Optimal block size for I/O.  */
  blkcnt_t st_blocks;                 /* Number 512-byte blocks allocated. */
  struct timespec st_atim;            /* Time of last access.  */
  struct timespec st_mtim;            /* Time of last modification.  */
  struct timespec st_ctim;            /* Time of last status change.  */   unsigned long int __unused4;
  unsigned long int __unused5;
};
]]
else -- 64 bit arch
STAT_VER_LINUX = 1
ffi.cdef[[
struct stat {
  dev_t st_dev;             /* Device.  */
  ino_t st_ino;             /* File serial number.  */
  nlink_t st_nlink;         /* Link count.  */
  mode_t st_mode;           /* File mode.  */
  uid_t st_uid;             /* User ID of the file's owner. */
  gid_t st_gid;             /* Group ID of the file's group.*/
  int __pad0;
  dev_t st_rdev;            /* Device number, if device.  */
  off_t st_size;            /* Size of file, in bytes.  */
  blksize_t st_blksize;     /* Optimal block size for I/O.  */
  blkcnt_t st_blocks;       /* Number 512-byte blocks allocated. */
  struct timespec st_atim;  /* Time of last access.  */
  struct timespec st_mtim;  /* Time of last modification.  */
  struct timespec st_ctim;  /* Time of last status change.  */
  long int __unused[3];
};
]]
end

ffi.cdef[[
// functions only used internally
char *strerror(int errnum);

// exported functions
int close(int fd);
int open(const char *pathname, int flags, mode_t mode);
int chdir(const char *path);
int unlink(const char *pathname);
int acct(const char *filename);

ssize_t read(int fd, void *buf, size_t count);
ssize_t write(int fd, const void *buf, size_t count);
ssize_t pread(int fd, void *buf, size_t count, off_t offset);
ssize_t pwrite(int fd, const void *buf, size_t count, off_t offset);
off_t lseek(int fd, off_t offset, int whence);
int dup(int oldfd);
int dup3(int oldfd, int newfd, int flags);
int fchdir(int fd);
int fsync(int fd);
int fdatasync(int fd);

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);
int munmap(void *addr, size_t length);

int pipe2(int pipefd[2], int flags);

int unlink(const char *pathname);
int access(const char *pathname, int mode);
char *getcwd(char *buf, size_t size);

int nanosleep(const struct timespec *req, struct timespec *rem);

// stat glibc internal functions
int __fxstat(int ver, int fd, struct stat *buf);
int __xstat(int ver, const char *path, struct stat *buf);
int __lxstat(int ver, const char *path, struct stat *buf);
int gnu_dev_major(dev_t dev);
int gnu_dev_minor(dev_t dev);



// functions from libc that could be exported as a convenience
void *calloc(size_t nmemb, size_t size);
void *malloc(size_t size);
void free(void *ptr);
void *realloc(void *ptr, size_t size);


]]

--[[ -- not defined yet
 int creat(const char *pathname, mode_t mode); -- defined using open instead
]]


local fd_t -- type for a file descriptor
local fd2_t = ffi.typeof("int[2]")
local timespec_t = ffi.typeof("struct timespec")
local stat_t

--get fd from standard string, integer, or cdata
function getfd(fd)
  if type(fd) == 'number' then return fd end
  if ffi.istype(fd_t, fd) then return fd.fd end
  if type(fd) == 'string' then
    if fd == 'stdin' or fd == 'STDIN_FILENO' then return 0 end
    if fd == 'stdout' or fd == 'STDOUT_FILENO' then return 1 end
    if fd == 'stderr' or fd == 'STDERR_FILENO' then return 2 end
  end
end

function retfd(ret)
  if ret == -1 then
    return errorret()
  end
  return fd_t(ret)
end

function S.open(pathname, flags, mode)
  return retfd(ffi.C.open(pathname, flags or 0, mode or 0))
end

function S.dup(oldfd, newfd, flags)
  if newfd == nil then return retfd(ffi.C.dup(getfd(oldfd))) end
  return retfd(ffi.C.dup3(getfd(oldfd), getfd(newfd), flags or 0))
end
S.dup2 = S.dup -- flags optional, so do not need new function
S.dup3 = S.dup -- conditional on newfd set

function S.pipe(flags)
  local fd2 = fd2_t()
  local ret = ffi.C.pipe2(fd2, flags or 0)

  if ret == -1 then
    return nil, errorret() -- extra nil as we return two fds normally
  end

  return fd_t(fd2[0]), fd_t(fd2[1])
end
S.pipe2 = S.pipe

function S.close(fd)
  local ret = ffi.C.close(getfd(fd))

  if ret == -1 then
    return errorret()
  end

  if ffi.istype(fd_t, fd) then
    ffi.gc(fd, nil) -- remove gc finalizer as now closed; should we also remove if get EBADF?
  end

  return true
end

function S.creat(pathname, mode) return S.open(pathname, S.O_CREAT + S.O_WRONLY + S.O_TRUNC, mode) end
function S.unlink(pathname) return retbool(ffi.C.unlink(pathname)) end
function S.access(pathname, mode) return retbool(ffi.C.access(pathname, mode)) end
function S.chdir(path) return retbool(ffi.C.chdir(path)) end
function S.unlink(pathname) return retbool(ffi.C.unlink(pathname)) end
function S.acct(filename) return retbool(ffi.C.acct(filename)) end

function S.read(fd, buf, count) return retint(ffi.C.read(getfd(fd), buf, count)) end
function S.write(fd, buf, count) return retint(ffi.C.write(getfd(fd), buf, count)) end
function S.pread(fd, buf, count, offset) return retint(ffi.C.pread(getfd(fd), buf, count, offset)) end
function S.pwrite(fd, buf, count, offset) return retint(ffi.C.pwrite(getfd(fd), buf, count, offset)) end
function S.lseek(fd, offset, whence) return retint(ffi.C.lseek(getfd(fd), offset, whence)) end

function S.fchdir(fd) return retbool(ffi.C.fchdir(getfd(fd))) end
function S.fsync(fd) return retbool(ffi.C.fsync(getfd(fd))) end
function S.fdatasync(fd) return retbool(ffi.C.fdatasync(getfd(fd))) end

function S.stat(path)
  local buf = stat_t()
  local ret = ffi.C.__xstat(STAT_VER_LINUX, path, buf)
  if ret == -1 then return errorret() end
  return buf
end
function S.lstat(path)
  local buf = stat_t()
  local ret = ffi.C.__lxstat(STAT_VER_LINUX, path, buf)
  if ret == -1 then return errorret() end
  return buf
end
function S.fstat(fd)
  local buf = stat_t()
  local ret = ffi.C.__fxstat(STAT_VER_LINUX, getfd(fd), buf)
  if ret == -1 then return errorret() end
  return buf
end

function S.getcwd(buf, size)
  local ret = ffi.C.getcwd(buf, size or 0)
  if buf == nil then -- Linux will allocate buffer here, return Lua string and free
    if ret == nil then return errorret() end
    local s = ffi.string(ret) -- guaranteed to be zero terminated if no error
    ffi.C.free(ret)
    return s
  end
  -- user allocated buffer
  if ret == nil then return errorret() end
  return true -- no point returning the pointer as it is just the passed buffer
end

function S.nanosleep(req)
  local rem = timespec_t()
  local ret = ffi.C.nanosleep(req, rem)
  if ret == -1 then return errorret() end
  return rem
end

--local MAP_FAILED = ffi.new("void *", -1)
--local MAP_FAILED = ffi.new("void *")
--local MAP_FAILED = ffi.cast("void *", ffi.new("void *") - 1LL)
--ffi.fill(MAP_FAILED, ffi.sizeof("void *"), 0xff)
local MAP_FAILED = nil -- wrong!

function S.mmap(addr, length, prot, flags, fd, offset)
  local ret = ffi.C.mmap(addr, length, prot, flags, getfd(fd), offset)
  if ret == MAP_FAILED then return errorret() end
  return ffi.gc(ret, function(addr) ffi.C.munmap(addr, length) end) -- add munmap to gc
end
function S.munmap(addr, length)
  return retbool(ffi.C.munmap(ffi.gc(addr, nil), length))
end

-- 'macros' and helper functions etc

-- note that major and minor are inline in glibc, gnu provides these real symbols, else you might have to parse yourself
function S.major(dev) return ffi.C.gnu_dev_major(dev) end
function S.minor(dev) return ffi.C.gnu_dev_minor(dev) end

function S.S_ISREG(m)  return bit.band(m, S.S_IFREG)  ~= 0 end
function S.S_ISDIR(m)  return bit.band(m, S.S_IFDIR)  ~= 0 end
function S.S_ISCHR(m)  return bit.band(m, S.S_IFCHR)  ~= 0 end
function S.S_ISBLK(m)  return bit.band(m, S.S_IFBLK)  ~= 0 end
function S.S_ISFIFO(m) return bit.band(m, S.S_IFFIFO) ~= 0 end
function S.S_ISLNK(m)  return bit.band(m, S.S_IFLNK)  ~= 0 end
function S.S_ISSOCK(m) return bit.band(m, S.S_IFSOCK) ~= 0 end

-- not system functions
function S.nogc(d) ffi.gc(d, nil) end

-- types

-- methods on an fd
local fdmethods = {'nogc', 'close', 'dup', 'dup2', 'dup3', 'read', 'write', 'pread', 'pwrite', 'lseek', 'fchdir', 'fsync', 'fdatasync', 'fstat'}
local fmeth = {}
for i, v in ipairs(fdmethods) do fmeth[v] = S[v] end

fd_t = ffi.metatype("struct {int fd;}", {__index = fmeth, __gc = S.close})
stat_t = ffi.typeof("struct stat")

-- add char buffer type
local buffer_t = ffi.typeof("char[?]")
S.string = ffi.string -- convenience for converting buffers

-- we could just return as S.timespec_t etc, not sure which is nicer?
S.t = {fd = fd_t, timespec = timespec_t, buffer = buffer_t, stat = stat_t}

return S


