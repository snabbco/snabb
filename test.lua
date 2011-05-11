local S = require "syscall"

local fd, fd0, fd1, fd2, n, s, err, errno

-- test open non existent file
fd, err, errno = S.open("/tmp/file/does/not/exist", S.O_RDONLY)
assert(err ~= nil, "expected open to fail on file not found")
assert(S.symerror[errno] == 'ENOENT', "expect ENOENT from open non existent file")

-- test close invalid fd
fd, err, errno = S.close(4)
assert(err, "expected to fail on close invalid fd")
assert(S.symerror[errno] == 'EBADF', "expect EBADF from invalid numberic fd")

-- test open and close valid file
fd, err, errno = S.open("/dev/null", S.O_RDONLY)
assert(err == nil, "should be able to open /dev/null")
assert(errno == nil, "errno should not be set opening /dev/null")
assert(type(fd) == 'cdata', "should get a cdata object back from open")
assert(fd.fd == 3, "should get file descriptor 3 back from first open")

-- another open
fd2, err, errno = S.open("/dev/zero", S.O_RDONLY)
assert(err == nil, "should be able to open /dev/zero")
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
n, err, errno = S.read(fd2, buf, size)
assert(err == nil, "should be able to read from /dev/zero")
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
assert(not n, "should not be able to read from fd 4 after gc")
assert(S.symerror[errno] == 'EBADF', "expect EBADF from already closed fd")

-- test with gc turned off
fd, err, errno = S.open("/dev/zero", S.O_RDONLY)
assert(err == nil, err)
assert(fd.fd == 3, "fd should be 3")
fd:nogc()
fd = nil
collectgarbage("collect")
n, err, errno = S.read(3, buf, size)
assert(err == nil, "should be able to read as gc disabled")
assert(S.close(3))

-- another open
fd, err, errno = S.open("/dev/zero", S.O_RDWR)
assert(err == nil, "should be able to open /dev/zero read write")
-- test write
n, err, errno = S.write(fd, buf, size)
assert(err == nil, "should be able to write to /dev/zero")
assert(n >= 0, "should not get error writing to /dev/zero")
assert(n == size, "should not get truncated write to /dev/zero") -- technically allowed!

local offset = 1
n, err, errno = fd:pread(buf, size, offset)
assert(err == nil, "should be able to pread /dev/zero")
n, err, errno = fd:pwrite(buf, size, offset)
assert(err == nil, "should be able to pwrite /dev/zero")

fd2, err, errno = fd:dup()
assert(err == nil, "should be able to dup fd")
assert(fd2:close())

fd2, err, errno = fd:dup2(17)
assert(err == nil, "should be able to dup2 fd")
assert(fd2.fd == 17, "dup2,3 should set file id as specified")
assert(S.close(17))

fd2, err, errno = fd:dup3(17, S.O_CLOEXEC)
assert(err == nil, "should be able to dup3 fd")
assert(fd2.fd == 17, "dup2,3 should set file id as specified")
assert(S.close(17))

fd2, err, errno = fd:dup(17, S.O_CLOEXEC)
assert(err == nil, "should be able to use dup as dup3")
assert(fd2.fd == 17, "dup2,3 should set file id as specified")
assert(S.close(17))

assert(S.close(fd))

assert(S.O_CREAT == 64, "wrong octal value for O_CREAT")

local tmpfile = "./XXXXYYYYZZZ4521"
fd, err = S.creat(tmpfile, S.S_IRWXU)
assert(err == nil, err)

-- test fsync
assert(fd:fsync())

-- test fdatasync
assert(fd:fdatasync())

--n, err, errno = fd:lseek(offset, S.SEEK_SET)
n, err, errno = S.lseek(fd, offset, S.SEEK_SET)
assert(err == nil, "should be able to seek file")
assert(n == offset, "seek should position at set position")
n, err, errno = S.lseek(fd, offset, S.SEEK_CUR)
assert(err == nil, "should be able to seek file")
assert(n == offset + offset, "seek should position at set position")


assert(S.unlink(tmpfile), "should be able to unlink file")

assert(S.close(fd))

fd, err = S.open(tmpfile, S.O_RDWR)
assert(err ~= nil, "expected open to fail on file not found")

fd0, fd1, err, errno = S.pipe(99999) -- invalid flags to test error handling
assert(fd0 == nil and fd1 == nil and S.symerror[errno] == 'EINVAL', "should be EINVAL with bad flags to pipe2")
fd0, fd1, err, errno = S.pipe()
assert(err == nil and errno == nil, "should be able to open pipe")
assert(fd0.fd == 3 and fd1.fd == 4, "expect file handles 3 and 4 for pipe")
fd0, fd1 = nil, nil

assert(S.chdir("/"))
fd, err = S.open("/")
assert(err == nil, err)
assert(fd:fchdir())

assert(S.getcwd(buf, size))
assert(S.string(buf) == "/", "expect cwd to be /")
s, err = S.getcwd()
assert(err == nil, err)
assert(s == "/", "expect cwd to be /")

local rem
rem, err, errno = S.nanosleep(S.t.timespec(0, 1000000))
assert(err == nil, err)
assert(rem.tv_sec == 0 and rem.tv_nsec == 0, "expect no elapsed time after nanosleep")

local stat

stat, err, errno = S.lstat("/dev/zero")
assert(err == nil, err)
assert(stat.st_nlink == 1, "expect link count on /dev/zero to be 1")

stat, err, errno = S.fstat(fd) -- stat "/"
assert(err == nil, err)
assert(stat.st_size == 4096, "expect / to be size 4096") -- might not be
assert(stat.st_gid == 0, "expect / to be gid 0 is " .. tonumber(stat.st_gid))
assert(stat.st_uid == 0, "expect / to be uid 0 is " .. tonumber(stat.st_uid))

stat, err, errno = S.stat("/dev/zero")
assert(err == nil, err)
assert(S.major(stat.st_rdev) == 1, "expect major number of /dev/zero to be 1")
assert(S.minor(stat.st_rdev) == 5, "expect minor number of /dev/zero to be 5")



