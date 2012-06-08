local S = require "syscall"
local bit = require "bit"

local oldassert = assert
function assert(c, s)
  return oldassert(c, tostring(s)) -- annoyingly, assert does not call tostring!
end

local luaunit = require "luaunit"

local assert_equal = assert_equals

local teststring = "this is a test string"
local size = 512
local buf = S.t.buffer(size)
local tmpfile = "XXXXYYYYZZZ4521" .. S.getpid()
local tmpfile2 = "./666666DDDDDFFFF" .. S.getpid()

local setup = function()
  S.unlink(tmpfile)
  S.unlink(tmpfile2)
end

test_basic = {
  test_octal = function()
    assert_equal(S.O_CREAT, 64, "wrong octal value for O_CREAT")
  end,
  test_signals = function()
    assert_equal(S.SIGSYS, 31) -- test numbers correct
  end
}

test_open_close = {
  setup = setup,
  test_open_nofile = function()
    local fd, err = S.open("/tmp/file/does/not/exist", "rdonly")
    assert(err, "expected open to fail on file not found")
    assert(err.ENOENT, "expect ENOENT from open non existent file")
    assert(tostring(err) == "No such file or directory", "should get string error message")
  end,
  test_close_invalid_fd = function()
    local ok, err = S.close(127)
    assert(err, "expected to fail on close invalid fd")
    assert_equal(err.errno, S.E.EBADF, "expect EBADF from invalid numberic fd")
  end,
  test_open_valid = function()
    local fd = assert(S.open("/dev/null", "rdonly"))
    assert(fd.fileno >= 3, "should get file descriptor of at least 3 back from first open")
    local fd2 = assert(S.open("/dev/zero", "RDONLY"))
    assert(fd2.fileno >= 4, "should get file descriptor of at least 4 back from second open")
    assert(fd:close())
    assert(fd2:close())
  end,
  test_sync = function()
    S.sync() -- cannot fail...
  end,
  test_fd_cleared_on_close = function()
    local fd = assert(S.open("/dev/null", "rdonly"))
    assert(fd:close())
    local fd2 = assert(S.open("/dev/zero")) -- reuses same fd
    local ok, err = fd:close() -- this should not fd again
    assert(fd2:close()) -- this should succeed
  end,
  test_double_close = function()
    local fd = assert(S.open("/dev/null", "rdonly"))
    local fileno = fd.fileno
    assert(fd:close())
    local fd, err = S.close(fileno)
    assert(err, "expected to fail on close already closed fd")
    assert(err.badf, "expect EBADF from invalid numberic fd")
  end,
  test_access = function()
    assert(S.access("/dev/null", "r"), "expect access to say can read /dev/null")
    assert(S.access("/dev/null", S.R_OK), "expect access to say can read /dev/null")
  end,
  test_fd_gc = function()
    local fd = assert(S.open("/dev/null", "rdonly"))
    local fileno = fd.fileno
    fd = nil
    collectgarbage("collect")
    local _, err = S.read(fileno, buf, size)
    assert(err, "should not be able to read from fd after gc")
    assert(err.EBADF, "expect EBADF from already closed fd")
  end,
  test_fd_nogc = function()
    local fd = assert(S.open("/dev/zero", "RDONLY"))
    local fileno = fd.fileno
    fd:nogc()
    fd = nil
    collectgarbage("collect")
    local n = assert(S.read(fileno, buf, size))
    assert(S.close(fileno))
  end
}

test_read_write = {
  setup = setup,
  test_read = function()
    local fd = assert(S.open("/dev/zero"))
    for i = 0, size - 1 do buf[i] = 255 end
    local n = assert(fd:read(buf, size))
    assert(n >= 0, "should not get error reading from /dev/zero")
    assert_equal(n, size, "should not get truncated read from /dev/zero")
    for i = 0, size - 1 do assert(buf[i] == 0, "should read zeroes from /dev/zero") end
    assert(fd:close())
  end,
  test_read_to_string = function()
    local fd = assert(S.open("/dev/zero"))
    local str = assert(fd:read(nil, 10))
    assert_equal(#str, 10, "string returned from read should be length 10")
    assert(fd:close())
  end,
  test_write_ro = function()
    local fd = assert(S.open("/dev/zero"))
    local n, err = fd:write(buf, size)
    assert(err, "should not be able to write to file opened read only")
    assert(err.EBADF, "expect EBADF when writing read only file")
    assert(fd:close())
  end,
  test_write = function()
    fd = assert(S.open("/dev/zero", "RDWR"))
    local n = assert(fd:write(buf, size))
    assert(n >= 0, "should not get error writing to /dev/zero")
    assert_equal(n, size, "should not get truncated write to /dev/zero")
    assert(fd:close())
  end,
  test_write_string = function()
    fd = assert(S.open("/dev/zero", "RDWR"))
    local n = assert(fd:write(teststring))
    assert_equal(n, #teststring, "write on a string should write out its length")
    assert(fd:close())
  end,
  test_pread_pwrite = function()
    fd = assert(S.open("/dev/zero", "RDWR"))
    local offset = 1
    local n
    n = assert(fd:pread(buf, size, offset))
    assert_equal(n, size, "should not get truncated pread on /dev/zero")
    n = assert(fd:pwrite(buf, size, offset))
    assert_equal(n, size, "should not get truncated pwrite on /dev/zero")
    assert(fd:close())
  end,
  test_readfile_writefile = function()
    assert(S.writefile(tmpfile, teststring, "IRWXU"))
    local ss = assert(S.readfile(tmpfile))
    assert_equal(ss, teststring, "readfile should get back what writefile wrote")
    assert(S.unlink(tmpfile))
  end
}

test_file_operations = {
  setup = setup,
  test_dup = function()
    local fd = assert(S.open("/dev/zero"))
    local fd2 = assert(fd:dup())
    assert(fd2:close())
    assert(fd:close())
  end,
  test_dup_to_number = function()
    local fd = assert(S.open("/dev/zero"))
    local fd2 = assert(fd:dup(17))
    assert_equal(fd2.fileno, 17, "dup2 should set file id as specified")
    assert(fd2:close())
    assert(fd:close())
  end,
  test_link = function()
    local fd = assert(S.creat(tmpfile, "IRWXU"))
    assert(S.link(tmpfile, tmpfile2))
    assert(S.unlink(tmpfile2))
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_symlink = function()
    local fd = assert(S.creat(tmpfile, "IRWXU"))
    assert(S.symlink(tmpfile, tmpfile2))
    local s = assert(S.readlink(tmpfile2))
    assert_equal(s, tmpfile, "should be able to read symlink")
    assert(S.unlink(tmpfile2))
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_fchmod = function()
    local fd = assert(S.creat(tmpfile, "IRWXU"))
    assert(fd:fchmod("IRUSR, IWUSR"))
    local st = fd:stat()
    assert_equal(st.mode, S.mode("IFREG, IRUSR, IWUSR"))
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_chmod = function()
    local fd = assert(S.creat(tmpfile, "IRWXU"))
    assert(S.chmod(tmpfile, "IRUSR, IWUSR"))
    assert(S.access(tmpfile, "rw"))
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_sync = function()
    local fd = assert(S.creat(tmpfile, "IRWXU"))
    assert(fd:fsync())
    assert(fd:fdatasync())
    assert(fd:sync()) -- synonym
    assert(fd:datasync()) -- synonym
    assert(fd:sync_file_range(0, 4096, "wait_before, write, wait_after"))
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_seek = function()
    local fd = assert(S.creat(tmpfile, "IRWXU"))
    local offset = 1
    local n
    n = assert(fd:lseek(offset, "set"))
    assert_equal(n, offset, "seek should position at set position")
    n = assert(fd:lseek(offset, "cur"))
    assert_equal(n, offset + offset, "seek should position at set position")
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_mkdir_rmdir = function()
    assert(S.mkdir(tmpfile, "IRWXU"))
    assert(S.rmdir(tmpfile))
  end,
  test_chdir = function()
    local cwd = assert(S.getcwd())
    assert(S.chdir("/"))
    local fd = assert(S.open("/"))
    assert(fd:fchdir())
    local nd = assert(S.getcwd())
    assert(nd == "/", "expect cwd to be /")
    assert(S.chdir(cwd)) -- return to original directory
  end,
  test_stat = function()
    local stat = assert(S.stat("/dev/zero"))
    assert(stat.nlink == 1, "expect link count on /dev/zero to be 1")
    assert(stat.major == 1 , "expect major number of /dev/zero to be 1")
    assert(stat.minor == 5, "expect minor number of /dev/zero to be 5")
    assert(stat.ischr, "expect /dev/zero to be a character device")
    assert(stat.rdev == S.makedev(1, 5), "expect raw device to be makedev(1, 5)")
  end,
  test_stat_directory = function()
    local fd = assert(S.open("/"))
    local stat = assert(fd:stat())
    assert(stat.size == 4096, "expect / to be size 4096") -- might not be
    assert(stat.gid == 0, "expect / to be gid 0 is " .. tonumber(stat.st_gid))
    assert(stat.uid == 0, "expect / to be uid 0 is " .. tonumber(stat.st_uid))
    assert(stat.isdir, "expect / to be a directory")
    assert(fd:close())
  end,
  test_lstat = function()
    assert(S.symlink("/etc/passwd", tmpfile))
    local stat = assert(S.stat(tmpfile))
    assert(stat.isreg, "expect /etc/passwd to be a regular file")
    local stat = assert(S.lstat(tmpfile))
    assert(stat.islnk, "expect lstat to stat the symlink")
    assert(S.unlink(tmpfile))
  end,
  test_truncate = function()
    assert(S.writefile(tmpfile, teststring, "IRWXU"))
    local stat = assert(S.stat(tmpfile))
    assert_equal(stat.size, #teststring, "expect to get size of written string")
    assert(S.truncate(tmpfile, 1))
    stat = assert(S.stat(tmpfile))
    assert_equal(stat.size, 1, "expect get truncated size")
    local fd = assert(S.open(tmpfile, "RDWR"))
    assert(fd:truncate(1024))
    stat = assert(fd:stat())
    assert_equal(stat.size, 1024, "expect get truncated size")
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_fadvise_etc = function() -- could split
    local fd = assert(S.open(tmpfile, "creat, rdwr", "IRWXU"))
    assert(S.unlink(tmpfile))
    assert(fd:posix_fadvise("random"))
    local ok, err = fd:fallocate("keep_size", 0, 4096)
    assert(ok or err.EOPNOTSUPP, "expect fallocate to succeed if supported")
    ok, err = fd:posix_fallocate(0, 8192)
    assert(ok or err.EOPNOTSUPP, "expect posix_fallocate to succeed if supported")
    assert(fd:readahead(0, 4096))
    assert(fd:close())
  end,
  test_getdents_dirfile = function()
    local d = assert(S.dirfile("/dev")) -- tests getdents from higher level interface
    assert(d.zero, "expect to find /dev/zero")
    assert(d["."], "expect to find .")
    assert(d[".."], "expect to find ..")
    assert(d.zero.chr, "/dev/zero is a character device")
    assert(d["."].dir, ". is a directory")
    assert(not d["."].chr, ". is not a character device")
    assert(not d["."].sock, ". is not a socket")
    assert(not d["."].lnk, ". is not a synlink")
    assert(d[".."].dir, ".. is a directory")
  end,
  test_getdents_error = function()
    local fd = assert(S.open("/etc/passwd", "RDONLY"))
    local d, err = fd:getdents()
    assert(err.notdir, "/etc/passwd should give a not directory error")
    assert(fd:close())
  end,
  test_inotify = function()
    assert(S.mkdir(tmpfile, "IRWXU")) -- do in directory so ok to run in parallel
    local fd = assert(S.inotify_init("cloexec, nonblock"))
    local wd = assert(fd:inotify_add_watch(tmpfile, "create, delete"))
    assert(S.chdir(tmpfile))
    local n, err = fd:inotify_read()
    assert(err.again, "no inotify events yet")
    assert(S.writefile(tmpfile, "test", "IRWXU"))
    assert(S.unlink(tmpfile))
    n = assert(fd:inotify_read())
    assert_equal(#n, 2, "expect 2 events now")
    assert(n[1].create, "file created")
    assert_equal(n[1].name, tmpfile, "created file should have same name")
    assert(n[2].delete, "file deleted")
    assert_equal(n[2].name, tmpfile, "created file should have same name")
    assert(fd:inotify_rm_watch(wd))
    assert(fd:close())
    assert(S.chdir(".."))
    assert(S.rmdir(tmpfile))
  end
}

test_sockets_pipes = {
  test_pipe = function()
    local fd = assert(S.pipe())
    assert(fd[1]:close())
    assert(fd[2]:close())
  end
}

test_timers_signals = {
  test_nanosleep = function()
    local rem = assert(S.nanosleep(0.001))
    assert_equal(rem.sec, 0, "expect no elapsed time after nanosleep")
    assert_equal(rem.nsec, 0, "expect no elapsed time after nanosleep")
    assert_equal(rem.time, 0, "expect no elapsed time after nanosleep")
  end,
  test_alarm = function()
    assert(S.signal("alrm", "ign"))
    assert(S.sigaction("alrm", "ign")) -- should do same as above
    assert(S.alarm(10))
    assert(S.alarm(0)) -- cancel again
    assert(S.signal("alrm", "dfl"))
  end,
  test_itimer = function()
    local t = S.getitimer("real")
    assert(t.interval.sec == 0, "expect timer not set")
    local exp = S.SIGALRM
    assert(S.sigaction("alrm", function(s) assert(s == exp, "expected alarm"); exp = 0 end))
    assert(exp == S.SIGALRM, "sigaction handler should not have run")
    assert(S.setitimer("real", 0, 0.0001))
    local rem, err = S.nanosleep(1) -- nanosleep does not interact with signals, should be interrupted
    assert(err.EINTR, "expect nanosleep to be interrupted by timer expiry")
    assert(exp == 0, "sigaction handler should have run")
  end,
  test_kill_ignored = function()
    assert(S.signal("pipe", "ign"))
    assert(S.kill(S.getpid(), "pipe")) -- should be ignored
    assert(S.signal("pipe", "dfl"))
  end,
  test_sigprocmask = function()
    local m = assert(S.sigprocmask())
    assert(m.isemptyset, "expect initial sigprocmask to be empty")
    assert(not m.winch, "expect set empty")
    m = m:add(S.SIGWINCH)
    assert(m.winch, "expect to have added SIGWINCH")
    m = m:del("SIGWINCH, pipe")
    assert(not m.winch, "expect set empty again")
    assert(m.isemptyset, "expect initial sigprocmask to be empty")
    m = m:add("winch")
    m = assert(S.sigprocmask("block", m))
    assert(m.isemptyset, "expect old sigprocmask to be empty")
    assert(S.kill(S.getpid(), "winch")) -- should be blocked but pending
    local p = assert(S.sigpending())
    assert(p.winch, "expect pending winch")

    -- signalfd. TODO Should be in another test
    local ss = "winch, pipe, usr1, usr2"
    local fd = assert(S.signalfd(ss, "nonblock"))
    assert(S.sigprocmask("block", ss))
    assert(S.kill(S.getpid(), "usr1"))
    local ss = assert(fd:signalfd_read())
    assert(#ss == 2, "expect to read two signals") -- previous pending winch, plus USR1
    assert((ss[1].winch and ss[2].usr1) or (ss[2].winch and ss[1].usr1), "expect a winch and a usr1 signal") -- unordered
    assert(ss[1].user, "signal sent by user")
    assert(ss[2].user, "signal sent by user")
    assert(ss[1].pid == S.getpid(), "signal sent by my pid")
    assert(ss[2].pid == S.getpid(), "signal sent by my pid")
    assert(fd:close())
  end
}

test_mmap = {
  test_mmap_fail = function()
    local size = 4096
    local mem, err = S.mmap(S.t.pointer(1), size, "read", "fixed, anonymous", -1, 0)
    assert(err, "expect non aligned fixed map to fail")
    assert(err.EINVAL, "expect non aligned map to return EINVAL")
  end,
  test_mmap = function()
    local size = 4096
    local mem = assert(S.mmap(nil, size, "read", "private, anonymous", -1, 0))
    assert(S.munmap(mem, size))
  end,
  test_msync = function()
    local size = 4096
    local mem = assert(S.mmap(nil, size, "read", "private, anonymous", -1, 0))
    assert(S.msync(mem, size, "sync"))
    assert(S.munmap(mem, size))
  end,
  test_madvise = function()
    local size = 4096
    local mem = assert(S.mmap(nil, size, "read", "private, anonymous", -1, 0))
    assert(S.madvise(mem, size, "random"))
    assert(S.munmap(mem, size))
  end,
  test_mremap = function()
    local size = 4096
    local size2 = size * 2
    local mem = assert(S.mmap(nil, size, "read", "private, anonymous", -1, 0))
    mem = assert(S.mremap(mem, size, size2, "maymove"))
    assert(S.munmap(mem, size2))
  end,
  test_mlock = function()
    local size = 4096
    local mem = assert(S.mmap(nil, size, "read", "private, anonymous", -1, 0))
    assert(S.mlock(mem, size))
    assert(S.munlock(mem, size))
    assert(S.munmap(mem, size))
    local ok, err = S.mlockall("current")
    assert(ok or err.nomem, "expect mlockall to succeed, or fail due to rlimit")
    assert(S.munlockall())
    assert(S.munmap(mem, size))
  end
}

test_misc = {
  test_umask = function()
    local mask
    mask = S.umask("IWGRP, IWOTH")
    mask = S.umask("IWGRP, IWOTH")
    assert_equal(mask, S.S_IWGRP + S.S_IWOTH, "umask not set correctly")
  end,
  test_sysinfo = function()
    local i = assert(S.sysinfo()) -- TODO test values returned for some sanity
  end,
  test_sysctl = function()
    local syslog = assert(S.klogctl(3))
    assert(#syslog > 20, "should be something in syslog")
  end,
  test_environ = function()
    local e = S.environ()
    assert(e.PATH, "expect PATH to be set in environment")
    assert(S.getenv("USER"), "expect USER to be set in environment")
    assert(S.setenv("XXXXYYYYZZZZZZZZ", "test"))
    assert(S.environ().XXXXYYYYZZZZZZZZ == "test", "expect to be able to set env vars")
    assert(S.unsetenv("XXXXYYYYZZZZZZZZ"))
    assert_nil(S.environ().XXXXYYYYZZZZZZZZ, "expect to be able to unset env vars")
  end,
  test_rlimit = function()
    local r = assert(S.getrlimit("nofile"))
    assert(S.setrlimit("nofile", 0, r.rlim_max))
    local fd, err = S.open("/dev/zero", "rdonly")
    assert(err.EMFILE, "should be over rlimit")
    assert(S.setrlimit("nofile", r.rlim_cur, r.rlim_max)) -- reset
    fd = assert(S.open("/dev/zero", "rdonly"))
    assert(fd:close())
  end,
  test_adjtimex = function()
    local t = assert(S.adjtimex())
  end,
  test_prctl = function()
    local n
    n = assert(S.prctl("capbset_read", "mknod"))
    assert(n == 0 or n == 1, "capability may or may not be set")
    n = assert(S.prctl("get_dumpable"))
    assert(n == 1, "process dumpable by default")
    assert(S.prctl("set_dumpable", 0))
    n = assert(S.prctl("get_dumpable"))
    assert(n == 0, "process not dumpable after change")
    assert(S.prctl("set_dumpable", 1))
    n = assert(S.prctl("get_keepcaps"))
    assert(n == 0, "process keepcaps defaults to 0")
    n = assert(S.prctl("get_pdeathsig"))
    assert(n == 0, "process pdeathsig defaults to 0")
    assert(S.prctl("set_pdeathsig", "winch"))
    n = assert(S.prctl("get_pdeathsig"))
    assert(n == S.SIGWINCH, "process pdeathsig should now be set to winch")
    assert(S.prctl("set_pdeathsig")) -- reset
    n = assert(S.prctl("get_name"))
    assert(S.prctl("set_name", "test"))
    n = assert(S.prctl("get_name"))
    assert(n == "test", "name should be as set")
    n = assert(S.readfile("/proc/self/comm"))
    assert(n == "test\n", "comm should be as set")
  end,
  test_uname = function()
    local u = assert(S.uname())
    assert_string(u.nodename)
    assert_string(u.sysname)
    assert_string(u.release)
    assert_string(u.version)
  end,
  test_hostname = function()
    local h = assert(S.gethostname())
    local u = assert(S.uname())
    assert(h == u.nodename, "gethostname did not return nodename")
  end
}

test_sockets = {
  test_socket_sizes = function()
    assert(S.sizeof(S.t.sockaddr) == S.sizeof(S.t.sockaddr_in)) -- inet socket addresses should be padded to same as sockaddr
    assert(S.sizeof(S.t.sockaddr_storage) == 128) -- this is the required size in Linux
    assert(S.sizeof(S.t.sockaddr_storage) >= S.sizeof(S.t.sockaddr))
    assert(S.sizeof(S.t.sockaddr_storage) >= S.sizeof(S.t.sockaddr_in))
    assert(S.sizeof(S.t.sockaddr_storage) >= S.sizeof(S.t.sockaddr_in6))
    assert(S.sizeof(S.t.sockaddr_storage) >= S.sizeof(S.t.sockaddr_un))
    assert(S.sizeof(S.t.sockaddr_storage) >= S.sizeof(S.t.sockaddr_nl))
  end,
  test_inet_aton_error = function()
    local a = S.inet_aton("error")
    assert(not a, "should get invalid IP address")
  end,
  test_sockaddr_in_error = function()
    local sa = S.sockaddr_in(1234, "error")
    assert(not sa, "expect nil socket address from invalid ip string")
  end,
  test_inet_socket = function() -- should break this test up
    local s = assert(S.socket("inet", "stream, nonblock")) -- adding flags to socket type is Linux only
    local loop = "127.0.0.1"
    local sa = assert(S.sockaddr_in(1234, loop))
    assert_equal(S.inet_ntoa(sa.sin_addr), loop, "expect address converted back to string to still be same")
    assert_equal(tostring(sa.sin_addr), loop, "expect address converted back to string to still be same")
    assert(sa.sin_family == 2, "expect family on inet socket to be AF_INET=2")
    -- find a free port
    local port
    for i = 1024, 2048 do
      port = i
      sa.sin_port = S.htons(port)
      if s:bind(sa) then break end
    end
    local ba = assert(s:getsockname())
    assert(ba.addr.sin_family == 2, "expect family on getsockname to be AF_INET=2")
    assert(s:listen()) -- will fail if we did not bind
    local c = assert(S.socket("inet", "stream")) -- client socket
    assert(c:nonblock())
    assert(c:fcntl("setfd", "cloexec"))
    local ok, err = c:connect(sa)
    assert(not ok, "connect should fail here")
    assert(err.EINPROGRESS, "have not accepted should get Operation in progress")
    local a = assert(s:accept())
    -- a is a table with the fd, but also the inbound connection details
    assert(a.addr.sin_family == 2, "expect ipv4 connection")
    assert(c:connect(sa)) -- able to connect now we have accepted
    local ba = assert(c:getpeername())
    assert(ba.addr.sin_family == 2, "expect ipv4 connection")
    assert(S.inet_ntoa(ba.addr.sin_addr) == "127.0.0.1", "expect peer on localhost")
    assert(ba.addr.sin_addr.s_addr == S.INADDR_LOOPBACK.s_addr, "expect peer on localhost")
    local n = assert(c:send(teststring))
    assert(n == #teststring, "should be able to write out short string")
    n = assert(a.fd:read(buf, size))
    assert(n == #teststring, "should read back string into buffer")
    assert(S.string(buf, n) == teststring, "we should read back the same string that was sent")
    -- test scatter gather
    local b0 = S.t.buffer(4)
    local b1 = S.t.buffer(3)
    S.copy(b0, "test", 4) -- string init adds trailing 0 byte
    S.copy(b1, "ing", 3)
    local iov = S.t.iovec(2, {{b0, 4}, {b1, 3}})
    n = assert(c:writev(iov, 2))
    assert(n == 7, "expect writev to write 7 bytes")
    b0 = S.t.buffer(3)
    b1 = S.t.buffer(4)
    local iov = S.t.iovec(2, {{b0, 3}, {b1, 4}})
    n = assert(a.fd:readv(iov, 2))
    assert_equal(n, 7, "expect readv to read 7 bytes")
    assert(S.string(b0, 3) == "tes" and S.string(b1, 4) == "ting", "expect to get back same stuff")
    -- test sendfile
    local f = assert(S.open("/etc/passwd", "RDONLY"))
    local off = 0
    n = assert(c:sendfile(f, off, 16))
    assert(n.count == 16 and n.offset == 16, "sendfile should send 16 bytes")
    assert(f:close())
    assert(c:close())
    assert(a.fd:close())
    assert(s:close())
  end,
  test_unix_socket = function()
    local sv = assert(S.socketpair("unix", "stream"))
    assert(sv[1]:sendmsg())
    assert(sv[2]:recvmsg())
    assert(sv[1]:close())
    assert(sv[2]:close())
  end,
  test_sendcred = function()
    local sv = assert(S.socketpair("unix", "stream"))
    assert(sv[2]:setsockopt("socket", "passcred", true)) -- enable receive creds
    local so = assert(sv[2]:getsockopt(S.SOL_SOCKET, S.SO_PASSCRED))
    assert(so == 1, "getsockopt should have updated value")
    assert(sv[1]:sendmsg()) -- sends single byte, which is enough to send credentials
    local r = assert(sv[2]:recvmsg())
    assert(r.pid == S.getpid(), "expect to get my pid from sending credentials")
    assert(sv[1]:sendfds("stdin"))
    local r = assert(sv[2]:recvmsg())
    assert(#r.fd == 1, "expect to get one file descriptor back")
    assert(r.fd[1]:close())
    assert(r.pid == S.getpid(), "should get my pid from sent credentals")
    assert(sv[1]:close())
    assert(sv[2]:close())
  end,
  test_sigpipe = function()
    local sv = assert(S.socketpair("unix", "stream"))
    assert(sv[1]:shutdown("rd"))
    assert(S.signal("pipe", "ign"))
    assert(sv[2]:close())
    local n, err = sv[1]:write("will get sigpipe")
    assert(err.EPIPE, "should get sigpipe")
    assert(sv[1]:close())
  end,
  test_udp_socket = function()
    local loop = "127.0.0.1"
    local s = assert(S.socket("inet", "dgram"))
    local c = assert(S.socket("inet", "dgram"))
    local sa = assert(S.sockaddr_in(0, loop))
    local ca = assert(S.sockaddr_in(0, loop))
    assert(s:bind(sa))
    assert(c:bind(sa))
    local bca = c:getsockname().addr -- find bound address
    local serverport = s:getsockname().port -- find bound port
    local n = assert(s:sendto(teststring, nil, 0, bca))
    local f = assert(c:recvfrom(buf, size)) -- do not test as can drop data
    assert(s:close())
    assert(c:close())
  end,
  test_ipv6_socket = function()
    local s, err = S.socket("AF_INET6", "dgram")
    if s then 
      local c = assert(S.socket("AF_INET6", "dgram"))
      local sa = assert(S.sockaddr_in6(0, S.in6addr_any))
      local ca = assert(S.sockaddr_in6(0, S.in6addr_any))
      assert(s:bind(sa))
      assert(c:bind(sa))
      local bca = c:getsockname().addr -- find bound address
      local serverport = s:getsockname().port -- find bound port
      local n = assert(s:sendto(teststring, nil, 0, bca))
      local f = assert(c:recvfrom(buf, size))
      assert(f.count == #teststring, "should get the whole string back")
      assert(f.port == serverport, "should be able to get server port in recvfrom")
      assert(c:close())
      assert(s:close())
    else assert(err.EAFNOSUPPORT, err) end -- fairly common to not have ipv6 in kernel
  end
}

test_netlink = {
  test_get_interfaces = function()
    local i = S.get_interfaces()
    local df = #assert(S.ls("/sys/class/net", true))
    --for k, v in ipairs(i.ifaces) do print(v.name) end
    assert(df == #i.ifaces, "expect same interfaces as /sys/class/net")
    assert(i.iface.lo, "expect a loopback interface")
    local lo = i.iface.lo
    assert(lo.flags.up, "loopback interface should be up")
    assert(lo.flags.loopback, "loopback interface should be marked as loopback")
    assert(lo.flags.running, "loopback interface should be running")
    assert(not lo.flags.broadcast, "loopback interface should not be broadcast")
    assert(not lo.flags.multicast, "loopback interface should not be multicast")
    assert(lo.loopback, "loopback interface type should be loopback") -- TODO add getflag
    local eth = i.iface.eth0 or i.iface.eth1 -- may not exist
    if eth then
      assert(eth.flags.broadcast, "ethernet interface should be broadcast")
      assert(eth.flags.multicast, "ethernet interface should be multicast")
      assert(eth.ether, "ethernet interface type should be ether")
    end
    local wlan = i.iface.wlan0
    if wlan then
      assert(wlan.ether, "wlan interface type should be ether")
    end
  end,
  test_bridge_list = function()
    local b = assert(S.bridge_list())
  end
}

test_termios = {
  test_pts_termios = function()
    local ptm = assert(S.posix_openpt("rdwr, noctty"))
    assert(ptm:grantpt())
    assert(ptm:unlockpt())
    local pts_name = assert(ptm:ptsname())
    local pts = assert(S.open(pts_name, "rdwr, noctty"))
    local termios = assert(pts:tcgetattr())
    assert(termios:cfgetospeed() ~= 115200)
    termios:cfsetspeed(115200)
    assert_equal(termios:cfgetispeed(), 115200, "expect input speed as set")
    assert_equal(termios:cfgetospeed(), 115200, "expect output speed as set")
    assert(bit.band(termios.c_lflag, S.ICANON) ~= 0)
    termios:cfmakeraw()
    assert(bit.band(termios.c_lflag, S.ICANON) == 0)
    assert(pts:tcsetattr("now", termios))
    termios = assert(pts:tcgetattr())
    assert(termios:cfgetospeed() == 115200)
    assert(bit.band(termios.c_lflag, S.ICANON) == 0)
    assert(pts:tcsendbreak(0))
    assert(pts:tcdrain())
    assert(pts:tcflush('ioflush'))
    assert(pts:tcflow('ooff'))
    assert(pts:tcflow('ioff'))
    assert(pts:tcflow('oon'))
    assert(pts:tcflow('ion'))
  end
}

test_events = {
  test_eventfd = function()
    local fd = assert(S.eventfd(0, "nonblock"))
    local n = assert(fd:eventfd_read())
    assert_equal(n, 0, "eventfd should return 0 initially")
    assert(fd:eventfd_write(3))
    assert(fd:eventfd_write(6))
    assert(fd:eventfd_write(1))
    n = assert(fd:eventfd_read())
    assert_equal(n, 10, "eventfd should return 10")
    n = assert(fd:eventfd_read())
    assert(n, 0, "eventfd should return 0 again")
    assert(fd:close())
  end
}

test_aio = {
  setup = setup,
  test_aio_setup = function()
    local ctx = assert(S.io_setup(8))
    assert(ctx:destroy())
  end,
  test_aio_ctx_gc = function()
    local ctx = assert(S.io_setup(8))
    local ctx2 = S.t.aio_context()
    S.copy(ctx2, ctx, S.sizeof(S.t.aio_context))
    ctx = nil
    collectgarbage("collect")
    local ok, err = S.io_destroy(ctx2)
    assert(not ok, "should have closed aio ctx")
  end,
  test_aio = function() -- split this up
    -- need aligned buffer for O_DIRECT
    local abuf = assert(S.mmap(nil, 4096, "read,write", "private, anonymous", -1, 0))
    S.copy(abuf, teststring)
    local fd = S.open(tmpfile, "creat, direct, rdwr", "IRWXU") -- need to use O_DIRECT for aio to work
    assert(S.unlink(tmpfile))
    assert(fd:pwrite(abuf, 4096, 0))
    S.fill(abuf, 4096)
    local efd = assert(S.eventfd())
    local ctx = assert(S.io_setup(8))
    assert(ctx:submit{{cmd = "pread", data = 42, fd = fd, buf = abuf, nbytes = 4096, offset = 0}} == 1)
    local r = assert(ctx:getevents(1, 1))
    assert(#r == 1, "expect one aio event") -- should also test what is returned
    assert(ctx:submit{{cmd = "pread", data = 42, fd = fd, buf = abuf, nbytes = 4096, offset = 0}} == 1)
    -- TODO this is erroring, not sure why, needs debugging
    --r, err = ctx:cancel({cmd = "pread", data = 42, fd = fd, buf = abuf, nbytes = 4096, offset = 0})
    --r = assert(ctx:getevents(1, 1))
    --assert(#r == 0, "expect no aio events")
    -- TODO this is not working either
    --assert(ctx:submit{{cmd = "pread", data = 42, fd = fd, buf = abuf, nbytes = 4096, offset = 0, resfd = efd}} == 1)
    --local p = assert(S.poll({fd = efd, events = "in"}, 0, 1000))
    --assert(#p == 1, "expect one event available from poll, got " .. #p)
    assert(ctx:destroy())
    assert(fd:close())
    assert(S.munmap(abuf, 4096))
  end
}

-- legacy tests not yet converted to test framework

test_legacy = {
  test_legacy = function()

local fd, fd0, fd1, fd2, fd3, n, s, c, err, ok



-- sockets

local a, sa
local loop = "127.0.0.1"


local sv = assert(S.socketpair("unix", "stream"))
c, s = sv[1], sv[2]

-- test select, poll and epoll
local sel = assert(S.select{readfds = {c, s}, timeout = S.t.timeval(0,0)})
assert(sel.count == 0, "nothing to read select now")

local ep = assert(S.epoll_create("cloexec"))
assert(ep:epoll_ctl("add", c, "in"))

local r = assert(ep:epoll_wait(nil, 1, 0))
assert(#r == 0, "no events yet")

n = assert(s:write(teststring))

sel = assert(S.select{readfds = {c, s}, timeout = {0, 0}})
assert(sel.count == 1, "one fd available for read now")

r = assert(ep:epoll_wait())
assert(#r == 1, "one event now")
assert(r[1].EPOLLIN, "read event")
assert(r[1].fileno == c.fileno, "expect to get fileno of ready file back") -- by default our epoll_ctl sets this
assert(ep:close())

n = assert(c:read()) -- clear event

local pfds = S.t.pollfds(1, {{fd = c.fileno, events = S.POLLIN, revents = 0}})
local p = assert(S.poll(pfds, 1, 0))
assert(#p == 0, "no events now")

n = assert(s:write(teststring))

local p = assert(S.poll(pfds, 1, 0))
assert(#p == 1 and p[1].fileno == c.fileno and p[1].POLLIN, "one event now")

assert(s:close())
assert(c:close())



-- fork and related methods
local pid, pid0, w
pid0 = S.getpid()
assert(pid0 > 1, "expecting my pid to be larger than 1")
assert(S.getppid() > 1, "expecting my parent pid to be larger than 1")

assert(S.getsid())
S.setsid() -- may well fail

pid = assert(S.fork())
if pid == 0 then -- child
  assert(S.getppid() == pid0, "parent pid should be previous pid")
  S.exit(23)
else -- parent
  w = assert(S.wait())
  assert(w.pid == pid, "expect fork to return same pid as wait")
  assert(w.WIFEXITED, "process should have exited normally")
  assert(w.EXITSTATUS == 23, "exit should be 23")
end

pid = assert(S.fork())
if (pid == 0) then -- child
  assert(S.getppid() == pid0, "parent pid should be previous pid")
  S.exit(23)
else -- parent
  w = assert(S.waitid("all", 0, "exited, stopped, continued"))
  assert(w.si_signo == S.SIGCHLD, "waitid to return SIGCHLD")
  assert(w.si_status == 23, "exit should be 23")
  assert(w.si_code == S.CLD_EXITED, "normal exit expected")
end

local efile = "/tmp/tmpXXYYY.sh"
pid = assert(S.fork())
if (pid == 0) then -- child
  S.unlink(efile)
  local script = [[
#!/bin/sh

[ $1 = "test" ] || (echo "shell assert $1"; exit 1)
[ $2 = "ing" ] || (echo "shell assert $2"; exit 1)
[ $PATH = "/bin:/usr/bin" ] || (echo "shell assert $PATH"; exit 1)

]]
  S.writefile(efile, script, "IRWXU")
  assert(S.execve(efile, {efile, "test", "ing"}, {"PATH=/bin:/usr/bin"})) -- note first param of args overwritten
  -- never reach here
  os.exit()
else -- parent
  w = assert(S.waitpid(-1))
  assert(w.pid == pid, "expect fork to return same pid as wait")
  assert(w.WIFEXITED, "process should have exited normally")
  assert(w.EXITSTATUS == 0, "exit should be 0")
  assert(S.unlink(efile))
end

n = assert(S.getpriority("process"))
assert (n == 0, "process should start at priority 0")
assert(S.nice(1))
assert(S.setpriority("process", 0, 1)) -- sets to 1, which it already is
if S.geteuid() ~= 0 then
  n, err = S.nice(-2)
  assert(err, "non root user should not be able to set negative priority")
  n, err = S.setpriority("process", 0, -1)
  assert(err, "non root user should not be able to set negative priority")
end

local tv = assert(S.gettimeofday())
assert(math.floor(tv.time) == tv.sec, "should be able to get float time from timeval")
local t = S.time()
local t = assert(S.clock_getres("realtime"))
local t = assert(S.clock_gettime("realtime"))

-- timerfd
fd = assert(S.timerfd_create("monotonic", "nonblock, cloexec"))

n = assert(fd:timerfd_read())
assert(n == 0, "no timer events yet")

assert(fd:block())

local o = assert(fd:timerfd_settime(nil, 0, 0.000001))

--assert(tonumber(o.it_interval) == 0 and tonumber(o.it_value) == 0, "old timer values zero") -- needs metamethods

n = assert(fd:timerfd_read())
assert(n == 1, "should have exactly one timer expiry")

assert(fd:close())

oldcmd = assert(S.readfile("/proc/self/cmdline"))
assert(S.setcmdline("test"))
n = assert(S.readfile("/proc/self/cmdline"))
--assert(n:sub(1, 5) == "test\0", "command line should be set") -- valgrind issues
ss = "test1234567890123456789012345678901234567890"
assert(S.setcmdline(ss))
n = assert(S.readfile("/proc/self/cmdline"))
--assert(n:sub(1,#ss) == ss, "long command line should be set: ")
assert(S.setcmdline(oldcmd))


-- tee, splice, vmsplice
local p = assert(S.pipe("nonblock"))
local pp = assert(S.pipe("nonblock"))
local s = assert(S.socketpair("unix", "stream, nonblock"))
local fd = assert(S.open(tmpfile, "rdwr, creat", "IRWXU"))
assert(S.unlink(tmpfile))

local str = teststring

n = assert(fd:write(str))
assert(n == #str)

n = assert(S.splice(fd, 0, p[2], nil, #str, "nonblock")) -- splice file at offset 0 into pipe
assert(n == #str)

n = assert(S.tee(p[1], pp[2], #str, "nonblock")) -- clone our pipe
assert(n == #str)

n = assert(S.splice(p[1], nil, s[1], nil, #str, "nonblock")) -- splice to socket
assert(n == #str)

n = assert(s[2]:read())
assert(#n == #str)

n = assert(S.splice(pp[1], nil, s[1], nil, #str, "nonblock")) -- splice the tee'd pipe into our socket
assert(n == #str)

n = assert(s[2]:read())
assert(#n == #str)

local buf2 = S.t.buffer(#str)
S.copy(buf2, str, #str)

n = assert(S.vmsplice(p[2], S.t.iovec(1, {{buf2, #str}}), 1, "nonblock")) -- write our memory into pipe
assert(n == #str)

n = assert(S.splice(p[1], nil, s[1], nil, #str, "nonblock")) -- splice out to socket
assert(n == #str)

n = assert(s[2]:read())
assert(#n == #str)

assert(fd:close())
assert(p[1]:close())
assert(p[2]:close())
assert(pp[1]:close())
assert(pp[2]:close())
assert(s[1]:close())
assert(s[2]:close())



-- xattr support
assert(S.writefile(tmpfile, "test", "IRWXU"))
local l, err = S.listxattr(tmpfile)
assert(l or err.ENOTSUP, "expect to get xattr or not supported on fs")
if l then
  fd = assert(S.open(tmpfile, "rdwr"))
  assert(#l == 0 or (#l == 1 and l[1] == "security.selinux"), "expect no xattr on new file")
  l = assert(S.llistxattr(tmpfile))
  assert(#l == 0 or (#l == 1 and l[1] == "security.selinux"), "expect no xattr on new file")
  l = assert(fd:flistxattr())
  assert(#l == 0 or (#l == 1 and l[1] == "security.selinux"), "expect no xattr on new file")
  local nn = #l
  ok, err = S.setxattr(tmpfile, "user.test", "42", "create")
  if ok then -- likely to get err.ENOTSUP here if fs not mounted with user_xattr
    l = assert(S.listxattr(tmpfile))
    assert(#l == nn + 1, "expect another attribute set")
    assert(S.lsetxattr(tmpfile, "user.test", "44", "replace"))
    assert(fd:fsetxattr("user.test2", "42"))
    l = assert(S.listxattr(tmpfile))
    assert(#l == nn + 2, "expect another attribute set")
    s = assert(S.getxattr(tmpfile, "user.test"))
    assert(s == "44", "expect to read set value of xattr")
    s = assert(S.lgetxattr(tmpfile, "user.test"))
    assert(s == "44", "expect to read set value of xattr")
    s = assert(fd:fgetxattr("user.test2"))
    assert(s == "42", "expect to read set value of xattr")
    s, err = fd:fgetxattr("user.test3")
    assert(err and err.nodata, "expect to get ENODATA (=ENOATTR) from non existent xattr")
    s = assert(S.removexattr(tmpfile, "user.test"))
    s = assert(S.lremovexattr(tmpfile, "user.test2"))
    l = assert(S.listxattr(tmpfile))
    assert(#l == nn, "expect no xattr now")
    s, err = fd:fremovexattr("user.test3")
    assert(err and err.nodata, "expect to get ENODATA (=ENOATTR) from remove non existent xattr")
    -- table helpers
    t = assert(S.xattr(tmpfile))
    n = 0
    for k, v in pairs(t) do n = n + 1 end
    assert(n == nn, "expect no xattr now")
    t = {}
    for k, v in pairs{test = "42", test2 = "44"} do t["user." .. k] = v end
    assert(S.xattr(tmpfile, t))
    t = assert(S.lxattr(tmpfile))
    assert(t["user.test2"] == "44" and t["user.test"] == "42", "expect to return values set")
    n = 0
    for k, v in pairs(t) do n = n + 1 end
    assert(n == nn + 2, "expect 2 xattr now")
    t = {}
    for k, v in pairs{test = "42", test2 = "44", test3="hello"} do t["user." .. k] = v end
    assert(fd:fxattr(t))
    t = assert(fd:fxattr())
    assert(t["user.test2"] == "44" and t["user.test"] == "42" and t["user.test3"] == "hello", "expect to return values set")
    n = 0
    for k, v in pairs(t) do n = n + 1 end
    assert(n == nn + 3, "expect 3 xattr now")
  end
  assert(fd:close())
end
assert(S.unlink(tmpfile))



end
}

if arg[1] then luaunit:run(arg[1]) else luaunit:run() end

-- these should be set up to allow skipping them.

if S.geteuid() ~= 0 then S.exit("success") end -- cannot execute some tests if not root

assert(S.mkdir(tmpfile))
assert(S.mount("none", tmpfile, "tmpfs", "rdonly, noatime"))

--print(S.readfile("/proc/mounts"))

assert(S.umount(tmpfile, "detach, nofollow"))
assert(S.rmdir(tmpfile))

S.acct() -- may not be configured


local hh = "testhostname"
h = assert(S.gethostname())
assert(S.sethostname(hh))
assert(hh == assert(S.gethostname()))
assert(S.sethostname(h))

-- test bridge functions
ok, err = S.bridge_add("br999")
assert(ok or err.ENOPKG, err)
if ok then
  assert(S.stat("/sys/class/net/br999"))
  --assert(S.bridge_add_interface("br999", "eth0")) -- failing on test machine as already in another bridge!

  local b = assert(S.bridge_list())
  assert(b.br999 and b.br999.bridge.root_id, "expect to find bridge in list")

  --print(b.br0.brforward[1].mac_addr, b.br0.brforward[2].mac_addr, b.br0.brforward[3].mac_addr)

  --for k, v in pairs(b.br999.bridge) do print(k, v) end

  assert(S.bridge_del("br999"))
  ok = S.stat("/sys/class/net/br999")
  assert(not ok, "bridge should be gone")
end

-- chroot
assert(S.chroot("/"))

S.exit("success")

-- note tests missing tests for setting time TODO
-- note have tested pause, reboot but not in tests

-- assert(S.sigsuspend(m)) -- needs to be tested in fork.


