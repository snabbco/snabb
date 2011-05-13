local S = require "syscall"

local fd, fd0, fd1, fd2, n, s, err, errno

S.gcollect(true)

-- print uname info
local u = assert(S.uname())
print(u.nodename .. " " .. u.sysname .. " " .. u.release .. " " .. u.version)
local h = assert(S.gethostname())
assert(h == u.nodename, "gethostname did not return nodename")

-- test open non existent file
fd, err, errno = S.open("/tmp/file/does/not/exist", S.O_RDONLY)
assert(err, "expected open to fail on file not found")
assert(S.symerror[errno] == 'ENOENT', "expect ENOENT from open non existent file")

-- test close invalid fd
fd, err, errno = S.close(4)
assert(err, "expected to fail on close invalid fd")
assert(S.symerror[errno] == 'EBADF', "expect EBADF from invalid numberic fd")

-- test open and close valid file
fd = assert(S.open("/dev/null", S.O_RDONLY))
assert(type(fd) == 'cdata', "should get a cdata object back from open")
assert(fd.fd == 3, "should get file descriptor 3 back from first open")

-- another open
fd2 = assert(S.open("/dev/zero", S.O_RDONLY))
assert(fd2.fd == 4, "should get file descriptor 4 back from second open")

-- normal close
assert(S.close(fd))

-- test double close fd
fd, err, errno = S.close(3)
assert(err, "expected to fail on close already closed fd")
assert(S.symerror[errno] == 'EBADF', "expect EBADF from invalid numberic fd")

assert(S.access("/dev/null", S.R_OK), "expect access to say can read /dev/null")

local size = 128
local buf = S.t.buffer(size) -- allocate buffer for read

for i = 0, size - 1 do buf[i] = 255 end -- make sure overwritten
-- test read
n = assert(S.read(fd2, buf, size))
assert(n >= 0, "should not get error reading from /dev/zero")
assert(n == size, "should not get truncated read from /dev/zero") -- technically allowed!
for i = 0, size - 1 do assert(buf[i] == 0, "should read zero bytes from /dev/zero") end
-- test writing to read only file fails
n, err, errno = fd2:write(buf, size)
assert(err, "should not be able to write to file opened read only")
assert(S.symerror[errno] == 'EBADF', "expect EBADF when writing read only file")

-- test gc of file handle
fd2 = nil
collectgarbage("collect")

-- test file has been closed after garbage collection
n, err, errno = S.read(4, buf, size)
assert(err, "should not be able to read from fd 4 after gc")
assert(S.symerror[errno] == 'EBADF', "expect EBADF from already closed fd")

-- test with gc turned off
fd = assert(S.open("/dev/zero", S.O_RDONLY))
assert(fd.fd == 3, "fd should be 3")
fd:nogc()
fd = nil
collectgarbage("collect")
n = assert(S.read(3, buf, size))
assert(S.close(3))

-- another open
fd = assert(S.open("/dev/zero", S.O_RDWR))
-- test write
n = assert(S.write(fd, buf, size))
assert(n >= 0, "should not get error writing to /dev/zero")
assert(n == size, "should not get truncated write to /dev/zero") -- technically allowed!

local offset = 1
n = assert(fd:pread(buf, size, offset))
n = assert(fd:pwrite(buf, size, offset))

fd2 = assert(fd:dup())
assert(fd2:close())

fd2 = assert(fd:dup2(17))
assert(fd2.fd == 17, "dup2 should set file id as specified")
assert(S.close(17))

fd2 = assert(fd:dup3(17, S.O_CLOEXEC))
assert(fd2.fd == 17, "dup3 should set file id as specified")
assert(S.close(17))

fd2 = assert(fd:dup(17, S.O_CLOEXEC))
assert(fd2.fd == 17, "dup2,3 should set file id as specified")
assert(S.close(17))

assert(S.close(fd))

assert(S.O_CREAT == 64, "wrong octal value for O_CREAT")

local tmpfile = "./XXXXYYYYZZZ4521"
local tmpfile2 = "./666666DDDDDFFFF"

fd = assert(S.creat(tmpfile, S.S_IRWXU))

assert(S.link(tmpfile, tmpfile2))
assert(S.unlink(tmpfile2))

assert(fd:fchmod(S.S_IRUSR + S.S_IWUSR))
assert(S.chmod(tmpfile, S.S_IRUSR + S.S_IWUSR))

assert(fd:fsync())
assert(fd:fdatasync())

n = assert(fd:lseek(offset, 'SEEK_SET'))
assert(n == offset, "seek should position at set position")
n = assert(fd:lseek(offset, 'SEEK_CUR'))
assert(n == offset + offset, "seek should position at set position")

assert(S.unlink(tmpfile))

assert(S.mkdir(tmpfile, S.S_IRWXU))
assert(S.rmdir(tmpfile))

assert(S.close(fd))

fd, err = S.open(tmpfile, S.O_RDWR)
assert(err, "expected open to fail on file not found")

fd, err, errno = S.pipe(99999) -- invalid flags
assert(fd == nil and S.symerror[errno] == 'EINVAL', "should be EINVAL with bad flags to pipe2")

fd = assert(S.pipe())
assert(fd[1].fd == 3 and fd[2].fd == 4, "expect file handles 3 and 4 for pipe")
assert(fd[1]:close())
assert(fd[2]:close())

assert(S.chdir("/"))
fd = assert(S.open("/"))
assert(fd:fchdir())

assert(S.getcwd(buf, size))
assert(S.string(buf) == "/", "expect cwd to be /")
s= assert(S.getcwd())
assert(s == "/", "expect cwd to be /")

local rem
rem = assert(S.nanosleep(S.t.timespec(0, 1000000)))
assert(rem.tv_sec == 0 and rem.tv_nsec == 0, "expect no elapsed time after nanosleep")

local stat

stat = assert(S.lstat("/dev/zero"))
assert(stat.st_nlink == 1, "expect link count on /dev/zero to be 1")

stat = assert(fd:fstat(fd)) -- stat "/"
assert(stat.st_size == 4096, "expect / to be size 4096") -- might not be
assert(stat.st_gid == 0, "expect / to be gid 0 is " .. tonumber(stat.st_gid))
assert(stat.st_uid == 0, "expect / to be uid 0 is " .. tonumber(stat.st_uid))
assert(S.S_ISDIR(stat.st_mode), "expect / to be a directory")

stat = assert(S.stat("/dev/zero"))
assert(S.major(stat.st_rdev) == 1, "expect major number of /dev/zero to be 1")
assert(S.minor(stat.st_rdev) == 5, "expect minor number of /dev/zero to be 5")
assert(S.S_ISCHR(stat.st_mode), "expect /dev/zero to be a character device")

stat = assert(S.lstat("/etc/passwd"))
assert(S.S_ISREG(stat.st_mode), "expect /etc/passwd to be a regular file")

-- mmap and related functions
local mem, mem2
size = 4096
mem = assert(S.mmap(nil, size, S.PROT_READ, S.MAP_PRIVATE + S.MAP_ANONYMOUS, -1, 0))
assert(S.munmap(mem, size))
mem = assert(S.mmap(nil, size, S.PROT_READ, S.MAP_PRIVATE + S.MAP_ANONYMOUS, -1, 0))
assert(S.msync(mem, size, S.MS_SYNC))
assert(S.madvise(mem, size, "MADV_RANDOM"))
mem = nil -- gc memory, should be munmapped
collectgarbage("collect")

local size2 = size * 2
mem = assert(S.mmap(nil, size, S.PROT_READ, S.MAP_PRIVATE + S.MAP_ANONYMOUS, -1, 0))
S.nogc(mem)
mem2 = assert(S.mremap(mem, size, size2, S.MREMAP_MAYMOVE))
mem = nil
assert(S.munmap(mem2, size2))

local mask
mask = S.umask(S.S_IWGRP + S.S_IWOTH)
mask = S.umask(S.S_IWGRP + S.S_IWOTH)
assert(mask == S.S_IWGRP + S.S_IWOTH, "umask not set correctly")

-- sockets
local a, sa
a = S.inet_aton("error")
assert(not a, "should get invalid IP address")

local s, fl
s = assert(S.socket("AF_INET", "SOCK_STREAM", 0))
fl = assert(s:fcntl("F_GETFL"))
assert(s:fcntl("F_SETFL", bit.bor(fl, S.O_NONBLOCK)))

local loop = "127.0.0.1"
sa = S.sockaddr_in(1234, "error")
assert(not sa, "expect nil socket address from invalid ip string")
sa = assert(S.sockaddr_in(1234, loop), "bad sockaddr")
assert(S.inet_ntoa(sa.sin_addr) == loop, "expect address converted back to string to still be same")

assert(s:bind(sa))
assert(s:listen())
assert(s:close())

-- fork and related methods
local pid, pid0, status
pid0 = S.getpid()
assert(pid0 > 1, "expecting my pid to be larger than 1")
assert(S.getppid() > 1, "expecting my parent pid to be larger than 1")

pid = assert(S.fork())
if (pid == 0) then -- child
  assert(S.getppid() == pid0, "parent pid should be previous pid")
  S.exit()
else -- parent
  pid0, status, err = S.wait() -- non idiomatic return.
  assert(err == nil)
  assert(pid == pid0, "expect fork to return same pid as wait")
end
pid = assert(S.fork())
if (pid == 0) then -- child
  S.exit()
else -- parent
  pid0, status, err = S.waitpid(-1) -- non idiomatic return.
  assert(err == nil)
  assert(pid == pid0, "expect fork to return same pid as wait")
end

if S.geteuid() ~= 0 then S.exit("EXIT_SUCCESS") end -- cannot execute some tests if not root

assert(S.acct())

mem = assert(S.mmap(nil, size, S.PROT_READ, S.MAP_PRIVATE + S.MAP_ANONYMOUS, -1, 0))
assert(S.mlock(mem, size))
assert(S.munlock(mem, size))
assert(S.munmap(mem, size))

assert(S.mlockall(S.MCL_CURRENT))
assert(S.munlockall())

local hh = "testhostname"
h = assert(S.gethostname())
assert(S.sethostname(hh))
assert(hh == assert(S.gethostname()))
assert(S.sethostname(h))

S.exit("EXIT_SUCCESS")

