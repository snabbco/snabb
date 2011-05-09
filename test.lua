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
assert(fd[0] == 3, "should get file descriptor 3 back from first open")

-- another open
fd2, err, errno = L.open("/dev/zero", L.O_RDONLY)
assert(err == nil, "should be able to open /dev/zero")
assert(fd2[0] == 4, "should get file descriptor 4 back from second open")

-- normal close
ok, err, errno = L.close(fd)
assert(ok, "should not get error closing valid fd")
assert(err == nil, "should be able to close valid fd")
assert(errno == nil, "errno should not be set closing valid fd")

-- test double close fd
fd, err, errno = L.close(3)
assert(err, "expected to fail on close already closed fd")
assert(L.symerror[errno] == 'EBADF', "expect EBADF from invalid numberic fd")

size = 128
buf = ffi.new("char[?]", size) -- allocate buffer for read
for i = 0, size - 1 do buf[i] = 255 end -- make sure overwritten
n, err, errno = L.read(fd2, buf, size)
assert(err == nil, "should be able to read from /dev/zero")
assert(n >= 0, "should not get error reading from /dev/zero")
assert(n == size, "should not get truncated read from /dev/zero") -- technically allowed!
for i = 0, size - 1 do assert(buf[i] == 0, "should read zero bytes from /dev/zero") end

-- test gc of file handle
fd2 = nil
collectgarbage("collect")

-- test file has been closed after garbage collection
n, err, errno = L.read(4, buf, size)
assert(not n, "should not be able to read from fd 4 after gc")
assert(L.symerror[errno] == 'EBADF', "expect EBADF from already closed fd")



