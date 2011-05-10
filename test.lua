local L = require "syscall"
local ffi = require "ffi"

-- test open non existent file
fd, err, errno = L.open("/tmp/file/does/not/exist", L.O_RDONLY)
assert(err ~= nil, "expected open to fail on file not found")
assert(L.symerror[errno] == 'ENOENT', "expect ENOENT from open non existent file")

-- test close invalid fd
fd, err, errno = L.close(4)
assert(err, "expected to fail on close invalid fd")
assert(L.symerror[errno] == 'EBADF', "expect EBADF from invalid numberic fd")

-- test open and close valid file
fd, err, errno = L.open("/dev/null", L.O_RDONLY)
assert(err == nil, "should be able to open /dev/null")
assert(errno == nil, "errno should not be set opening /dev/null")
assert(type(fd) == 'cdata', "should get a cdata object back from open")
assert(fd.fd == 3, "should get file descriptor 3 back from first open")

-- another open
fd2, err, errno = L.open("/dev/zero", L.O_RDONLY)
assert(err == nil, "should be able to open /dev/zero")
assert(fd2.fd == 4, "should get file descriptor 4 back from second open")

-- normal close
assert(L.close(fd))

-- test double close fd
fd, err, errno = L.close(3)
assert(err, "expected to fail on close already closed fd")
assert(L.symerror[errno] == 'EBADF', "expect EBADF from invalid numberic fd")

size = 128
buf = ffi.new("char[?]", size) -- allocate buffer for read
for i = 0, size - 1 do buf[i] = 255 end -- make sure overwritten
-- test read
n, err, errno = L.read(fd2, buf, size)
assert(err == nil, "should be able to read from /dev/zero")
assert(n >= 0, "should not get error reading from /dev/zero")
assert(n == size, "should not get truncated read from /dev/zero") -- technically allowed!
for i = 0, size - 1 do assert(buf[i] == 0, "should read zero bytes from /dev/zero") end
-- test writing to read only file fails
n, err, errno = L.write(fd2, buf, size)
assert(err, "should not be able to write to file opened read only")
assert(L.symerror[errno] == 'EBADF', "expect EBADF when writing read only file")

-- test gc of file handle
fd2 = nil
collectgarbage("collect")

-- test file has been closed after garbage collection
n, err, errno = L.read(4, buf, size)
assert(not n, "should not be able to read from fd 4 after gc")
assert(L.symerror[errno] == 'EBADF', "expect EBADF from already closed fd")

-- another open
fd, err, errno = L.open("/dev/zero", L.O_RDWR)
assert(err == nil, "should be able to open /dev/zero read write")
-- test write
n, err, errno = L.write(fd, buf, size)
assert(err == nil, "should be able to write to /dev/zero")
assert(n >= 0, "should not get error writing to /dev/zero")
assert(n == size, "should not get truncated write to /dev/zero") -- technically allowed!
assert(L.close(fd))

assert(L.O_CREAT == 64, "wrong octal value for O_CREAT")

tmpfile = "./XXXXYYYYZZZ4521"
fd, err, errno = L.creat(tmpfile, L.S_IRWXU)
assert(err == nil, err)

-- test fsync
assert(L.fsync(fd))

-- test fdatasync
assert(L.fdatasync(fd))

-- test method of fd
assert(fd:close())

fd, err, errno = L.open(tmpfile, L.O_RDWR)
assert(err == nil, "file should have been created")
assert(L.close(fd))

assert(L.unlink(tmpfile))
fd, err, errno = L.open(tmpfile, L.O_RDWR)
assert(err ~= nil, "expected open to fail on file not found")



