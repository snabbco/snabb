-- test suite for ljsyscall.

local strict = require "strict"
local S = require "syscall"
local nl = require "syscall.nl"
local bit = require "bit"
local ffi = require "ffi"

setmetatable(S, {__index = function(i, k) error("bad index access on S: " .. k) end})

local oldassert = assert
local function assert(cond, s)
  collectgarbage("collect") -- force gc, to test for bugs
  return oldassert(cond, tostring(s)) -- annoyingly, assert does not call tostring!
end

local function fork_assert(cond, s) -- if we have forked we need to fail in main thread not fork
  if not cond then
    print(tostring(s))
    print(debug.traceback())
    S.exit("failure")
  end
  return cond, s
end

USE_EXPECTED_ACTUAL_IN_ASSERT_EQUALS = true -- strict wants this to be set
local luaunit = require "luaunit"

local function assert_equal(...)
  collectgarbage("collect") -- force gc, to test for bugs
  return assert_equals(...)
end

local sysfile = debug.getinfo(S.open).source
local cov = {active = {}, cov = {}}

local function coverage(event, line)
  local s = debug.getinfo(2, "nLlS")
  if s.source ~= sysfile then return end
  if event == "line" then
    cov.cov[line] = true
  elseif event == "call" then
    if s.activelines then for k, _ in pairs(s.activelines) do cov.active[k] = true end end
  end
end

if arg[1] == "coverage" then debug.sethook(coverage, "lc") end

local t, pt, c, s = S.t, S.pt, S.c, S.s

local teststring = "this is a test string"
local size = 512
local buf = t.buffer(size)
local tmpfile = "XXXXYYYYZZZ4521" .. S.getpid()
local tmpfile2 = "./666666DDDDDFFFF" .. S.getpid()
local tmpfile3 = "MMMMMTTTTGGG" .. S.getpid()
local longfile = "1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890" .. S.getpid()
local efile = "/tmp/tmpXXYYY" .. S.getpid() .. ".sh"
local largeval = math.pow(2, 33) -- larger than 2^32 for testing

local clean = function()
  S.rmdir(tmpfile)
  S.unlink(tmpfile)
  S.unlink(tmpfile2)
  S.unlink(tmpfile3)
  S.unlink(longfile)
  S.unlink(efile)
end

test_basic = {
  test_octal = function()
    assert_equal(c.O.CREAT, 64, "wrong octal value for O_CREAT")
  end,
  test_signals = function()
    assert_equal(c.SIG.SYS, 31) -- test numbers correct
  end,
  test_b64 = function()
    local h, l = t.i6432(0xffffffffffffffffLL):to32()
    assert_equal(h, bit.tobit(0xffffffff))
    assert_equal(l, bit.tobit(0xffffffff))
    local h, l = t.i6432(0xaffffffffffbffffLL):to32()
    assert_equal(h, bit.tobit(0xafffffff))
    assert_equal(l, bit.tobit(0xfffbffff))
  end,
  test_major_minor = function()
    local d = t.device(2, 3)
    assert_equal(d:major(), 2)
    assert_equal(d:minor(), 3)
  end,
  test_mock = function()
    local test = "teststring"
    local oldread = rawget(S.C, "read") -- should be nil
    S.C.read = function(fd, buf, count)
      ffi.copy(buf, test)
      return #test
    end
    local fd = assert(S.open("/dev/null"))
    assert_equal(S.read(fd), test, "should be able to mock calls")
    assert(fd:close())
    rawset(S.C, "read", oldread)
  end,
  test_fd_nums = function() -- TODO should also test on the version from types.lua
    assert_equal(t.fd(18):nogc():getfd(), 18, "should be able to trivially create fd")
  end,
}

test_open_close = {
  teardown = clean,
  test_open_nofile = function()
    local fd, err = S.open("/tmp/file/does/not/exist", "rdonly")
    assert(err, "expected open to fail on file not found")
    assert(err.NOENT, "expect NOENT from open non existent file")
    assert(tostring(err) == "No such file or directory", "should get string error message")
  end,
  test_openat = function()
    local dfd = S.open(".")
    local fd = assert(dfd:openat(tmpfile, "rdwr,creat", "rwxu"))
    assert(dfd:unlinkat(tmpfile))
    assert(fd:close())
    assert(dfd:close())
  end,
  test_close_invalid_fd = function()
    local ok, err = S.close(127)
    assert(err, "expected to fail on close invalid fd")
    assert_equal(err.errno, c.E.BADF, "expect BADF from invalid numberic fd")
  end,
  test_open_valid = function()
    local fd = assert(S.open("/dev/null", "rdonly"))
    assert(fd:getfd() >= 3, "should get file descriptor of at least 3 back from first open")
    local fd2 = assert(S.open("/dev/zero", "RDONLY"))
    assert(fd2:getfd() >= 4, "should get file descriptor of at least 4 back from second open")
    assert(fd:close())
    assert(fd2:close())
  end,
  test_fd_cleared_on_close = function()
    local fd = assert(S.open("/dev/null", "rdonly"))
    assert(fd:close())
    local fd2 = assert(S.open("/dev/zero")) -- reuses same fd
    local ok, err = assert(fd:close()) -- this should not close fd again, but no error as does nothing
    assert(fd2:close()) -- this should succeed
  end,
  test_double_close = function()
    local fd = assert(S.open("/dev/null", "rdonly"))
    local fileno = fd:getfd()
    assert(fd:close())
    local fd, err = S.close(fileno)
    assert(err, "expected to fail on close already closed fd")
    assert(err.badf, "expect BADF from invalid numberic fd")
  end,
  test_access = function()
    assert(S.access("/dev/null", "r"), "expect access to say can read /dev/null")
    assert(S.access("/dev/null", c.OK.R), "expect access to say can read /dev/null")
    assert(S.access("/dev/null", "w"), "expect access to say can write /dev/null")
    assert(not S.access("/dev/null", "x"), "expect access to say cannot execute /dev/null")
  end,
  test_faccessat = function()
    local fd = S.open("/dev")
    assert(fd:faccessat("null", "r"), "expect access to say can read /dev/null")
    assert(fd:faccessat("null", c.OK.R), "expect access to say can read /dev/null")
    assert(fd:faccessat("null", "w"), "expect access to say can write /dev/null")
    assert(not fd:faccessat("/dev/null", "x"), "expect access to say cannot execute /dev/null")
    assert(fd:close())
  end,
  test_fd_gc = function()
    local fd = assert(S.open("/dev/null", "rdonly"))
    local fileno = fd:getfd()
    fd = nil
    collectgarbage("collect")
    local _, err = S.read(fileno, buf, size)
    assert(err, "should not be able to read from fd after gc")
    assert(err.BADF, "expect BADF from already closed fd")
  end,
  test_fd_nogc = function()
    local fd = assert(S.open("/dev/zero", "RDONLY"))
    local fileno = fd:getfd()
    fd:nogc()
    fd = nil
    collectgarbage("collect")
    local n = assert(S.read(fileno, buf, size))
    assert(S.close(fileno))
  end
}

test_read_write = {
  teardown = clean,
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
    assert(err.BADF, "expect BADF when writing read only file")
    assert(fd:close())
  end,
  test_write = function()
    local fd = assert(S.open("/dev/zero", "RDWR"))
    local n = assert(fd:write(buf, size))
    assert(n >= 0, "should not get error writing to /dev/zero")
    assert_equal(n, size, "should not get truncated write to /dev/zero")
    assert(fd:close())
  end,
  test_write_string = function()
    local fd = assert(S.open("/dev/zero", "RDWR"))
    local n = assert(fd:write(teststring))
    assert_equal(n, #teststring, "write on a string should write out its length")
    assert(fd:close())
  end,
  test_pread_pwrite = function()
    local fd = assert(S.open("/dev/zero", "RDWR"))
    local offset = 1
    local n
    n = assert(fd:pread(buf, size, offset))
    assert_equal(n, size, "should not get truncated pread on /dev/zero")
    n = assert(fd:pwrite(buf, size, offset))
    assert_equal(n, size, "should not get truncated pwrite on /dev/zero")
    assert(fd:close())
  end,
  test_readfile_writefile = function()
    assert(S.writefile(tmpfile, teststring, "RWXU"))
    local ss = assert(S.readfile(tmpfile))
    assert_equal(ss, teststring, "readfile should get back what writefile wrote")
    assert(S.unlink(tmpfile))
  end,
  test_mapfile = function()
    assert(S.writefile(tmpfile, teststring, "RWXU"))
    local ss = assert(S.mapfile(tmpfile))
    assert_equal(ss, teststring, "mapfile should get back what writefile wrote")
    assert(S.unlink(tmpfile))
  end,
  test_readv_writev = function()
    local fd = assert(S.open(tmpfile, "rdwr,creat", "rwxu"))
    local n = assert(fd:writev{"test", "ing", "writev"})
    assert_equal(n, 13, "expect length 13")
    assert(fd:seek())
    local b1, b2, b3 = t.buffer(6), t.buffer(4), t.buffer(3)
    local n = assert(fd:readv{b1, b2, b3})
    assert_equal(n, 13, "expect length 13")
    assert_equal(ffi.string(b1, 6), "testin")
    assert_equal(ffi.string(b2, 4), "gwri")
    assert_equal(ffi.string(b3, 3), "tev")
    assert(S.unlink(tmpfile))
  end,
  test_preadv_pwritev = function()
    local offset = largeval
    local fd = assert(S.open(tmpfile, "rdwr,creat", "rwxu"))
    local n = assert(fd:pwritev({"test", "ing", "writev"}, offset))
    assert_equal(n, 13, "expect length 13")
    local b1, b2, b3 = t.buffer(6), t.buffer(4), t.buffer(3)
    local n = assert(fd:preadv({b1, b2, b3}, offset))
    assert_equal(n, 13, "expect length 13")
    assert_equal(ffi.string(b1, 6), "testin")
    assert_equal(ffi.string(b2, 4), "gwri")
    assert_equal(ffi.string(b3, 3), "tev")
    assert(fd:seek(offset))
    local n = assert(fd:readv{b1, b2, b3})
    assert_equal(n, 13, "expect length 13")
    assert_equal(ffi.string(b1, 6), "testin")
    assert_equal(ffi.string(b2, 4), "gwri")
    assert_equal(ffi.string(b3, 3), "tev")
    assert(S.unlink(tmpfile))
  end,
}

test_file_operations = {
  teardown = clean,
  test_dup = function()
    local fd = assert(S.open("/dev/zero"))
    local fd2 = assert(fd:dup())
    assert(fd2:close())
    assert(fd:close())
  end,
  test_dup_to_number = function()
    local fd = assert(S.open("/dev/zero"))
    local fd2 = assert(fd:dup(17))
    assert_equal(fd2:getfd(), 17, "dup2 should set file id as specified")
    assert(fd2:close())
    assert(fd:close())
  end,
  test_link = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(S.link(tmpfile, tmpfile2))
    assert(S.unlink(tmpfile2))
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_linkat = function()
    local dirfd = assert(S.open("."))
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(S.linkat(dirfd, tmpfile, dirfd, tmpfile2, "symlink_follow"))
    assert(S.unlink(tmpfile2))
    assert(S.unlink(tmpfile))
    assert(fd:close())
    assert(dirfd:close())
  end,
  test_symlink = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(S.symlink(tmpfile, tmpfile2))
    local s = assert(S.readlink(tmpfile2))
    assert_equal(s, tmpfile, "should be able to read symlink")
    assert(S.unlink(tmpfile2))
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_symlinkat = function()
    local dirfd = assert(S.open("."))
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(S.symlinkat(tmpfile, dirfd, tmpfile2))
    local s = assert(S.readlinkat(dirfd, tmpfile2))
    assert_equal(s, tmpfile, "should be able to read symlink")
    assert(S.unlink(tmpfile2))
    assert(S.unlink(tmpfile))
    assert(fd:close())
    assert(dirfd:close())
  end,
  test_sync = function()
    S.sync() -- cannot fail...
  end,
  test_fchmod = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(fd:fchmod("RUSR, WUSR"))
    local st = fd:stat()
    assert_equal(st.mode, c.S_I["FREG, RUSR, WUSR"]) -- TODO should be better way to test
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_chmod = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(S.chmod(tmpfile, "RUSR, WUSR"))
    assert(S.access(tmpfile, "rw"))
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_fchmodat = function()
    local dirfd = assert(S.open("."))
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(dirfd:fchmodat(tmpfile, "RUSR, WUSR"))
    assert(S.access(tmpfile, "rw"))
    assert(S.unlink(tmpfile))
    assert(fd:close())
    assert(dirfd:close())
  end,
  test_chown_root = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(S.chown(tmpfile, 66, 55))
    local stat = S.stat(tmpfile)
    assert_equal(stat.uid, 66, "expect uid changed")
    assert_equal(stat.gid, 55, "expect gid changed")
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_chown = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(S.chown(tmpfile)) -- unchanged
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_fchown_root = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(fd:chown(66, 55))
    local stat = fd:stat()
    assert_equal(stat.uid, 66, "expect uid changed")
    assert_equal(stat.gid, 55, "expect gid changed")
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_lchown_root = function()
    assert(S.symlink("/dev/zero", tmpfile))
    assert(S.lchown(tmpfile, 66, 55))
    local stat = S.lstat(tmpfile)
    assert_equal(stat.uid, 66, "expect uid changed")
    assert_equal(stat.gid, 55, "expect gid changed")
    assert(S.unlink(tmpfile))
  end,
  test_fchownat_root = function()
    local dirfd = assert(S.open("."))
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(dirfd:fchownat(tmpfile, 66, 55, "symlink_nofollow"))
    local stat = S.stat(tmpfile)
    assert_equal(stat.uid, 66, "expect uid changed")
    assert_equal(stat.gid, 55, "expect gid changed")
    assert(S.unlink(tmpfile))
    assert(fd:close())
    assert(dirfd:close())
  end,
  test_sync = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(fd:fsync())
    assert(fd:fdatasync())
    assert(fd:sync()) -- synonym
    assert(fd:datasync()) -- synonym
    assert(fd:sync_file_range(0, 4096, "wait_before, write, wait_after"))
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_seek = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    local offset = 1
    local n
    n = assert(fd:lseek(offset, "set"))
    assert_equal(n, offset, "seek should position at set position")
    n = assert(fd:lseek(offset, "cur"))
    assert_equal(n, offset + offset, "seek should position at set position")
    local t = fd:tell()
    assert_equal(t, n, "tell should return current offset")
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_seek_error = function()
    local s, err = S.lseek(-1, 0, "set")
    assert(not s, "seek should fail with invalid fd")
    assert(err.badf, "bad file descriptor")
  end,
  test_mkdir_rmdir = function()
    assert(S.mkdir(tmpfile, "RWXU"))
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
  test_getcwd_long = function()
    local cwd = assert(S.getcwd())
    assert(S.mkdir(longfile, "RWXU"))
    assert(S.chdir(longfile))
    local nd = assert(S.getcwd())
    assert_equal(nd, cwd .. "/" .. longfile, "expect to get filename plus cwd")
    assert(S.chdir(cwd))
    assert(S.rmdir(longfile))
  end,
  test_mkdirat_unlinkat = function()
    local fd = assert(S.open("."))
    assert(fd:mkdirat(tmpfile, "RWXU"))
    assert(fd:unlinkat(tmpfile, "removedir"))
    assert(not fd:fstatat(tmpfile), "expect dir gone")
  end,
  test_rename = function()
    assert(S.writefile(tmpfile, teststring, "RWXU")) -- TODO just use touch instead
    assert(S.rename(tmpfile, tmpfile2))
    assert(not S.stat(tmpfile))
    assert(S.stat(tmpfile2))
    assert(S.unlink(tmpfile2))
  end,
  test_renameat = function()
    local fd = assert(S.open("."))
    assert(S.writefile(tmpfile, teststring, "RWXU"))
    assert(S.renameat(fd, tmpfile, fd, tmpfile2))
    assert(not S.stat(tmpfile))
    assert(S.stat(tmpfile2))
    assert(fd:close())
    assert(S.unlink(tmpfile2))
  end,
  test_stat = function()
    local stat = assert(S.stat("/dev/zero"))
    assert_equal(stat.nlink, 1, "expect link count on /dev/zero to be 1")
    assert(stat.ischr, "expect /dev/zero to be a character device")
    assert_equal(stat.rdev:major(), 1 , "expect major number of /dev/zero to be 1")
    assert_equal(stat.rdev:minor(), 5, "expect minor number of /dev/zero to be 5")
    assert_equal(stat.rdev, t.device(1, 5), "expect raw device to be makedev(1, 5)")
  end,
  test_stat_directory = function()
    local fd = assert(S.open("/"))
    local stat = assert(fd:stat())
    assert(stat.size == 4096, "expect / to be size 4096") -- might not be
    assert(stat.isdir, "expect / to be a directory")
    assert(fd:close())
  end,
  test_stat_symlink = function()
    assert(S.symlink("/etc/passwd", tmpfile))
    local stat = assert(S.stat(tmpfile))
    assert(stat.isreg, "expect /etc/passwd to be a regular file")
    assert(not stat.islnk, "should not be symlink")
    assert(S.unlink(tmpfile))
  end,
  test_lstat_symlink = function()
    assert(S.symlink("/etc/passwd", tmpfile))
    local stat = assert(S.lstat(tmpfile))
    assert(stat.islnk, "expect lstat to stat the symlink")
    assert(not stat.isreg, "lstat should find symlink not regular file")
    assert(S.unlink(tmpfile))
  end,
  test_fstatat = function()
    local fd = assert(S.open("."))
    assert(S.writefile(tmpfile, teststring, "RWXU"))
    local stat = assert(fd:fstatat(tmpfile))
    assert(stat.size == #teststring, "expect length to br what was written")
    assert(fd:close())
    assert(S.unlink(tmpfile))
  end,
  test_fstatat_fdcwd = function()
    assert(S.writefile(tmpfile, teststring, "RWXU"))
    local stat = assert(S.fstatat("fdcwd", tmpfile, nil, "no_automount, symlink_nofollow"))
    assert(stat.size == #teststring, "expect length to br what was written")
    assert(S.unlink(tmpfile))
  end,
  test_truncate = function()
    assert(S.writefile(tmpfile, teststring, "RWXU"))
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
    local fd = assert(S.open(tmpfile, "creat, rdwr", "RWXU"))
    assert(S.unlink(tmpfile))
    assert(fd:fadvise("random"))
    local ok, err = fd:fallocate("keep_size", 0, 4096)
    assert(ok or err.OPNOTSUPP or err.NOSYS, "expect fallocate to succeed if supported")
    ok, err = fd:posix_fallocate(0, 8192)
    assert(ok or err.OPNOTSUPP or err.NOSYS, "expect posix_fallocate to succeed if supported")
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
    assert(S.mkdir(tmpfile, "RWXU")) -- do in directory so ok to run in parallel
    local fd = assert(S.inotify_init("cloexec, nonblock"))
    local wd = assert(fd:inotify_add_watch(tmpfile, "create, delete"))
    assert(S.chdir(tmpfile))
    local n, err = fd:inotify_read()
    assert(err.again, "no inotify events yet")
    assert(S.writefile(tmpfile, "test", "RWXU"))
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
  end,
  test_xattr = function()
    assert(S.writefile(tmpfile, "test", "RWXU"))
    local l, err = S.listxattr(tmpfile)
    assert(l or err.NOTSUP, "expect to get xattr or not supported on fs")
    if l then
      local fd = assert(S.open(tmpfile, "rdwr"))
      assert(#l == 0 or (#l == 1 and l[1] == "security.selinux"), "expect no xattr on new file")
      l = assert(S.llistxattr(tmpfile))
      assert(#l == 0 or (#l == 1 and l[1] == "security.selinux"), "expect no xattr on new file")
      l = assert(fd:flistxattr())
      assert(#l == 0 or (#l == 1 and l[1] == "security.selinux"), "expect no xattr on new file")
      local nn = #l
      local ok, err = S.setxattr(tmpfile, "user.test", "42", "create")
      if ok then -- likely to get err.NOTSUP here if fs not mounted with user_xattr
        l = assert(S.listxattr(tmpfile))
        assert(#l == nn + 1, "expect another attribute set")
        assert(S.lsetxattr(tmpfile, "user.test", "44", "replace"))
        assert(fd:fsetxattr("user.test2", "42"))
        l = assert(S.listxattr(tmpfile))
        assert(#l == nn + 2, "expect another attribute set")
        local s = assert(S.getxattr(tmpfile, "user.test"))
        assert(s == "44", "expect to read set value of xattr")
        s = assert(S.lgetxattr(tmpfile, "user.test"))
        assert(s == "44", "expect to read set value of xattr")
        s = assert(fd:fgetxattr("user.test2"))
        assert(s == "42", "expect to read set value of xattr")
        local s, err = fd:fgetxattr("user.test3")
        assert(err and err.nodata, "expect to get NODATA (=NOATTR) from non existent xattr")
        s = assert(S.removexattr(tmpfile, "user.test"))
        s = assert(S.lremovexattr(tmpfile, "user.test2"))
        l = assert(S.listxattr(tmpfile))
        assert(#l == nn, "expect no xattr now")
        local s, err = fd:fremovexattr("user.test3")
        assert(err and err.nodata, "expect to get NODATA (=NOATTR) from remove non existent xattr")
        -- table helpers
        local tt = assert(S.xattr(tmpfile))
        local n = 0
        for k, v in pairs(tt) do n = n + 1 end
        assert(n == nn, "expect no xattr now")
        tt = {}
        for k, v in pairs{test = "42", test2 = "44"} do tt["user." .. k] = v end
        assert(S.xattr(tmpfile, tt))
        tt = assert(S.lxattr(tmpfile))
        assert(tt["user.test2"] == "44" and tt["user.test"] == "42", "expect to return values set")
        n = 0
        for k, v in pairs(tt) do n = n + 1 end
        assert(n == nn + 2, "expect 2 xattr now")
        tt = {}
        for k, v in pairs{test = "42", test2 = "44", test3="hello"} do tt["user." .. k] = v end
        assert(fd:fxattr(tt))
        tt = assert(fd:fxattr())
        assert(tt["user.test2"] == "44" and tt["user.test"] == "42" and tt["user.test3"] == "hello", "expect to return values set")
        n = 0
        for k, v in pairs(tt) do n = n + 1 end
        assert(n == nn + 3, "expect 3 xattr now")
      end
      assert(fd:close())
    end
    assert(S.unlink(tmpfile))
  end,
  test_mknod_chr_root = function()
    assert(S.mknod(tmpfile, "fchr,rwxu", t.device(1, 5)))
    local stat = assert(S.stat(tmpfile))
    assert(stat.ischr, "expect to be a character device")
    assert_equal(stat.rdev:major(), 1 , "expect major number to be 1")
    assert_equal(stat.rdev:minor(), 5, "expect minor number to be 5")
    assert_equal(stat.rdev, t.device(1, 5), "expect raw device to be makedev(1, 5)")
    assert(S.unlink(tmpfile))
  end,
  test_mknodat_fifo = function()
    local fd = assert(S.open("."))
    assert(fd:mknodat(tmpfile, "fifo,rwxu"))
    local stat = assert(S.stat(tmpfile))
    assert(stat.isfifo, "expect to be a fifo")
    assert(fd:close())
    assert(S.unlink(tmpfile))
  end,
  test_mkfifoat = function()
    local fd = assert(S.open("."))
    assert(fd:mkfifoat(tmpfile, "rwxu"))
    local stat = assert(S.stat(tmpfile))
    assert(stat.isfifo, "expect to be a fifo")
    assert(fd:close())
    assert(S.unlink(tmpfile))
  end,
  test_mkfifo = function()
    assert(S.mkfifo(tmpfile, "rwxu"))
    local stat = assert(S.stat(tmpfile))
    assert(stat.isfifo, "expect to be a fifo")
    assert(S.unlink(tmpfile))
  end,
}

test_largefile = {
  test_seek64 = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    local loff = t.loff(2^34)
    local offset = 2^34 -- should work with Lua numbers up to 56 bits, above that need explicit 64 bit type.
    local n
    n = assert(fd:lseek(loff, "set"))
    assert_equal(n, loff, "seek should position at set position")
    n = assert(fd:lseek(loff, "cur"))
    assert_equal(n, loff + loff, "seek should position at set position")
    n = assert(fd:lseek(offset, "set"))
    assert_equal(n, offset, "seek should position at set position")
    n = assert(fd:lseek(offset, "cur"))
    assert_equal(n, offset + offset, "seek should position at set position")
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_ftruncate64 = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    local offset = 2^35
    assert(fd:truncate(offset), "64 bit ftruncate should be ok")
    local st = assert(fd:stat(), "64 bit stat should be ok")
    assert(st.size == offset, "stat shoul be truncated length")
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_truncate64 = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    local offset = 2^35
    assert(S.truncate(tmpfile, offset), "64 bit truncate should be ok")
    local st = assert(S.stat(tmpfile), "64 bit stat should be ok")
    assert(st.size == offset, "stat shoul be truncated length")
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
}

test_locking = {
  test_fcntl_setlk = function()
    local fd = assert(S.open(tmpfile, "creat, rdwr", "RWXU"))
    assert(S.unlink(tmpfile))
    assert(fd:truncate(4096))
    assert(fd:fcntl("setlk", {type = "rdlck", whence = "set", start = 0, len = 4096}))
    assert(fd:close())
  end,
  test_lockf_lock = function()
    local fd = assert(S.open(tmpfile, "creat, rdwr", "RWXU"))
    assert(S.unlink(tmpfile))
    assert(fd:truncate(4096))
    assert(fd:lockf("lock", 4096))
    assert(fd:close())
  end,
  test_lockf_tlock = function()
    local fd = assert(S.open(tmpfile, "creat, rdwr", "RWXU"))
    assert(S.unlink(tmpfile))
    assert(fd:truncate(4096))
    assert(fd:lockf("tlock", 4096))
    assert(fd:close())
  end,
  test_lockf_ulock = function()
    local fd = assert(S.open(tmpfile, "creat, rdwr", "RWXU"))
    assert(S.unlink(tmpfile))
    assert(fd:truncate(4096))
    assert(fd:lockf("lock", 4096))
    assert(fd:lockf("ulock", 4096))
    assert(fd:close())
  end,
  test_lockf_test = function()
    local fd = assert(S.open(tmpfile, "creat, rdwr", "RWXU"))
    assert(S.unlink(tmpfile))
    assert(fd:truncate(4096))
    assert(fd:lockf("test", 4096))
    assert(fd:close())
  end,
}

test_sockets_pipes = {
  test_sockaddr_storage = function()
    local sa = t.sockaddr_storage{family = "netlink", pid = 2}
    assert_equal(sa.family, c.AF.NETLINK, "netlink family")
    assert_equal(sa.pid, 2, "should get pid back")
    sa.pid = 3
    assert_equal(sa.pid, 3, "should get pid back")
    sa.family = "inet"
    assert_equal(sa.family, c.AF.INET, "inet family")
    sa.port = 4
    assert_equal(sa.port, 4, "should get port back")
  end,
  test_pipe = function()
    local p = assert(S.pipe())
    assert(p:close())
    local ok, err = S.close(p[1])
    assert(err, "should be invalid")
    local ok, err = S.close(p[2])
    assert(err, "should be invalid")
  end,
  test_nonblock = function()
    local fds = assert(S.pipe())
    assert(fds:setblocking(false))
    local r, err = fds:read()
    assert(err.AGAIN, "expect AGAIN")
    assert(fds:close())
  end,
  test_tee_splice = function()
    local p = assert(S.pipe("nonblock"))
    local pp = assert(S.pipe("nonblock"))
    local s = assert(S.socketpair("unix", "stream, nonblock"))
    local fd = assert(S.open(tmpfile, "rdwr, creat", "RWXU"))
    assert(S.unlink(tmpfile))

    local str = teststring

    local n = assert(fd:write(str))
    assert(n == #str)
    n = assert(S.splice(fd, 0, p[2], nil, #str, "nonblock")) -- splice file at offset 0 into pipe
    assert(n == #str)
    local n, err = S.tee(p[1], pp[2], #str, "nonblock") -- clone our pipe
    if n then
      assert(n == #str)
      n = assert(S.splice(p[1], nil, s[1], nil, #str, "nonblock")) -- splice to socket
      assert(n == #str)
      n = assert(s[2]:read())
      assert(#n == #str)
      n = assert(S.splice(pp[1], nil, s[1], nil, #str, "nonblock")) -- splice the tee'd pipe into our socket
      assert(n == #str)
      n = assert(s[2]:read())
      assert(#n == #str)
      local buf2 = t.buffer(#str)
      ffi.copy(buf2, str, #str)

      n = assert(S.vmsplice(p[2], {{buf2, #str}}, "nonblock")) -- write our memory into pipe
      assert(n == #str)
      n = assert(S.splice(p[1], nil, s[1], nil, #str, "nonblock")) -- splice out to socket
      assert(n == #str)
      n = assert(s[2]:read())
      assert(#n == #str)
    else
      assert(err.NOSYS, "only allowed error is syscall not suported, as valgrind gives this")
    end

    assert(fd:close())
    assert(p:close())
    assert(pp:close())
    assert(s:close())
  end,
}

test_timers_signals = {
  test_timespec = function()
    local ts = t.timespec(1)
    assert_equal(ts.time, 1)
    assert_equal(ts.sec, 1)
    assert_equal(ts.nsec, 0)
    local ts = t.timespec{1, 0}
    assert_equal(ts.time, 1)
    assert_equal(ts.sec, 1)
    assert_equal(ts.nsec, 0)
  end,
  test_timeval = function()
    local ts = t.timeval(1)
    assert_equal(ts.time, 1)
    assert_equal(ts.sec, 1)
    assert_equal(ts.usec, 0)
    local ts = t.timeval{1, 0}
    assert_equal(ts.time, 1)
    assert_equal(ts.sec, 1)
    assert_equal(ts.usec, 0)
  end,
  test_nanosleep = function()
    local rem = assert(S.nanosleep(0.001))
    assert_equal(rem, true, "expect no elapsed time after nanosleep")
  end,
  test_alarm = function()
    assert(S.signal("alrm", "ign"))
    assert(S.sigaction("alrm", "ign")) -- should do same as above
    assert(S.alarm(10))
    assert(S.alarm(0)) -- cancel again
    assert(S.signal("alrm", "dfl"))
  end,
  test_itimer = function()
    local tt = assert(S.getitimer("real"))
    assert(tt.interval.sec == 0, "expect timer not set")
    local ss = "alrm"

    local fd = assert(S.signalfd(ss, "nonblock"))
    assert(S.sigprocmask("block", ss))

    assert(S.setitimer("real", {0, 0.01}))
    assert(S.nanosleep(0.1)) -- nanosleep does not interact with itimer

    local sig = assert(fd:signalfd_read())
    assert(#sig == 1, "expect one signal")
    assert(sig[1].alrm, "expect alarm clock to have rung")
    assert(fd:close())
    assert(S.sigprocmask("unblock", ss))
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
    m = m:add(c.SIG.WINCH)
    assert(not m.isemptyset, "expect set not empty")
    assert(m.winch, "expect to have added SIGWINCH")
    m = m:del("WINCH, pipe")
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
    assert_equal(ss[1].pid, S.getpid(), "signal sent by my pid")
    assert_equal(ss[2].pid, S.getpid(), "signal sent by my pid")
    assert(fd:close())
  end,
  test_timerfd = function()
    local fd = assert(S.timerfd_create("monotonic", "nonblock, cloexec"))
    local n = assert(fd:timerfd_read())
    assert(n == 0, "no timer events yet")
    assert(fd:block())
    local o = assert(fd:timerfd_settime(nil, {0, 0.000001}))
    assert(o.interval.time == 0 and o.value.time == 0, "old timer values zero")
    n = assert(fd:timerfd_read())
    assert(n == 1, "should have exactly one timer expiry")
    local o = assert(fd:timerfd_gettime())
    assert_equal(o.interval.time, 0, "expect 0 from gettime as expired")
    assert_equal(o.value.time, 0, "expect 0 from gettime as expired")
    assert(fd:close())
  end,
  test_gettimeofday = function()
    local tv = assert(S.gettimeofday())
    assert(math.floor(tv.time) == tv.sec, "should be able to get float time from timeval")
  end,
  test_time = function()
    local tt = S.time()
  end,
  test_clock = function()
    local tt = assert(S.clock_getres("realtime"))
    local tt = assert(S.clock_gettime("realtime"))
    -- TODO add settime
  end,
  test_clock_nanosleep = function()
    local rem = assert(S.clock_nanosleep("realtime", nil, 0.001))
    assert_equal(rem, true, "expect no elapsed time after clock_nanosleep")
  end,
  test_clock_nanosleep_abs = function()
    local rem = assert(S.clock_nanosleep("realtime", "abstime", 0)) -- in the past
    assert_equal(rem, true, "expect no elapsed time after clock_nanosleep")
  end,
}

test_mmap = {
  test_mmap_fail = function()
    local size = 4096
    local mem, err = S.mmap(pt.void(1), size, "read", "fixed, anonymous", -1, 0)
    assert(err, "expect non aligned fixed map to fail")
    assert(err.INVAL, "expect non aligned map to return EINVAL")
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
    mask = S.umask("WGRP, WOTH")
    mask = S.umask("WGRP, WOTH")
    assert_equal(mask, c.MODE.WGRP + c.MODE.WOTH, "umask not set correctly")
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
    assert(S.setenv("XXXXYYYYZZZZZZZZ", "test"))
    assert(S.environ().XXXXYYYYZZZZZZZZ == "test", "expect to be able to set env vars")
    assert(S.unsetenv("XXXXYYYYZZZZZZZZ"))
    assert_nil(S.environ().XXXXYYYYZZZZZZZZ, "expect to be able to unset env vars")
  end,
  test_rlimit = function()
    local r = assert(S.getrlimit("nofile"))
    assert(S.setrlimit("nofile", {0, r.rlim_max}))
    local fd, err = S.open("/dev/zero", "rdonly")
    assert(err.MFILE, "should be over rlimit")
    assert(S.setrlimit("nofile", r)) -- reset
    fd = assert(S.open("/dev/zero", "rdonly"))
    assert(fd:close())
  end,
  test_prlimit = function()
    local r = assert(S.prlimit(0, "nofile"))
    local r2 = assert(S.prlimit(0, "nofile", {512, r.max}))
    assert_equal(r2.cur, r.cur, "old value same")
    assert_equal(r2.max, r.max, "old value same")
    local r3 = assert(S.prlimit(0, "nofile"))
    assert_equal(r3.cur, 512, "new value zero")
    assert_equal(r3.max, r.max, "max unchanged")
    assert(S.prlimit(0, "nofile", r))
    local r4 = assert(S.prlimit(0, "nofile"))
    assert_equal(r4.cur, r.cur, "reset to original")
    assert_equal(r4.max, r.max, "reset to original")
  end,
  test_prlimit_root = function()
    local r = assert(S.prlimit(0, "nofile"))
    local r2 = assert(S.prlimit(0, "nofile", {512, 640}))
    assert_equal(r2.cur, r.cur, "old value same")
    assert_equal(r2.max, r.max, "old value same")
    local r3 = assert(S.prlimit(0, "nofile"))
    assert_equal(r3.cur, 512, "new value zero")
    assert_equal(r3.max, 640, "max unchanged")
    assert(S.prlimit(0, "nofile", r))
    local r4 = assert(S.prlimit(0, "nofile"))
    assert_equal(r4.cur, r.cur, "reset to original")
    assert_equal(r4.max, r.max, "reset to original")
  end,
  test_adjtimex = function()
    local tt = assert(S.adjtimex())
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
    assert(n == c.SIG.WINCH, "process pdeathsig should now be set to winch")
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
    assert_string(u.machine)
    assert_string(u.domainname)
  end,
  test_gethostname = function()
    local h = assert(S.gethostname())
    local u = assert(S.uname())
    assert_equal(h, u.nodename, "gethostname did not return nodename")
  end,
  test_getdomainname = function()
    local d = assert(S.getdomainname())
    local u = assert(S.uname())
    assert_equal(d, u.domainname, "getdomainname did not return domainname")
  end,
  test_sethostname_root = function()
    assert(S.sethostname("hostnametest"))
    assert_equal(S.gethostname(), "hostnametest")
  end,
  test_setdomainname_root = function()
    assert(S.setdomainname("domainnametest"))
    assert_equal(S.getdomainname(), "domainnametest")
  end,
  test_bridge = function()
    local ok, err = S.bridge_add("br0")
    assert(ok or err.NOPKG or err.PERM, err) -- ok not to to have bridge in kernel, may not be root
    if ok then
      local i = assert(nl.interfaces())
      assert(i.br0)
      local b = assert(S.bridge_list())
      assert(b.br0 and b.br0.bridge.root_id, "expect to find bridge in list")
      assert(S.bridge_del("br0"))
      i = assert(nl.interfaces())
      assert(not i.br0, "bridge should be gone")
    end
  end,
  test_bridge_delete_fail = function()
    local ok, err = S.bridge_del("nosuchbridge99")
    assert(not ok and (err.NOPKG or err.PERM or err.NXIO), err)
  end,

--[[
  -- may switch this back to a type
  test_inet_name = function()
    local addr, mask = util.inet_name("127.0.0.1/24")
    assert(addr, "expect to get valid address")
    assert(S.istype(t.in_addr, addr))
    assert_equal(tostring(addr), "127.0.0.1")
    assert_equal(mask, 24)
  end,
  test_inet_name6 = function()
    local addr, mask = util.inet_name("::1")
    assert(addr, "expect to get valid address")
    assert(S.istype(t.in6_addr, addr))
    assert_equal(tostring(addr), "::1")
    assert_equal(mask, 128, "expect default mask")
  end,
]]
}

test_sockets = {
  test_ipv4_print = function()
    assert_equal(tostring(t.in_addr("127.0.0.1")), "127.0.0.1", "print ipv4")
    assert_equal(tostring(t.in_addr("255.255.255.255")), "255.255.255.255", "print ipv4")
  end,
  test_socket_sizes = function()
    assert(ffi.sizeof(t.sockaddr) == ffi.sizeof(t.sockaddr_in)) -- inet socket addresses should be padded to same as sockaddr
    assert(ffi.sizeof(t.sockaddr_storage) == 128) -- this is the required size in Linux
    assert(ffi.sizeof(t.sockaddr_storage) >= ffi.sizeof(t.sockaddr))
    assert(ffi.sizeof(t.sockaddr_storage) >= ffi.sizeof(t.sockaddr_in))
    assert(ffi.sizeof(t.sockaddr_storage) >= ffi.sizeof(t.sockaddr_in6))
    assert(ffi.sizeof(t.sockaddr_storage) >= ffi.sizeof(t.sockaddr_un))
    assert(ffi.sizeof(t.sockaddr_storage) >= ffi.sizeof(t.sockaddr_nl))
  end,
  test_sockaddr_in_error = function()
    local sa = t.sockaddr_in(1234, "error")
    assert(not sa, "expect nil socket address from invalid ip string")
  end,
  test_inet_socket = function() -- should break this test up
    local s = assert(S.socket("inet", "stream, nonblock"))
    local loop = "127.0.0.1"
    local sa = assert(t.sockaddr_in(1234, loop))
    assert_equal(tostring(sa.sin_addr), loop, "expect address converted back to string to still be same")
    assert(sa.sin_family == 2, "expect family on inet socket to be 2")
    -- find a free port
    local port
    for i = 1024, 2048 do
      port = i
      sa.port = port
      if s:bind(sa) then break end
    end
    local ba = assert(s:getsockname())
    assert_equal(ba.sin_family, 2, "expect family on getsockname to be 2")
    assert(s:listen()) -- will fail if we did not bind
    local c = assert(S.socket("inet", "stream")) -- client socket
    assert(c:nonblock())
    assert(c:fcntl("setfd", "cloexec"))
    local ok, err = c:connect(sa)
    assert(not ok, "connect should fail here")
    assert(err.INPROGRESS, "have not accepted should get Operation in progress")
    local a = assert(s:accept()) --TODO this blocks on ARM, I think error in connect
    -- a is a table with the fd, but also the inbound connection details
    assert(a.addr.sin_family == 2, "expect ipv4 connection")
    assert(c:connect(sa)) -- able to connect now we have accepted
    local ba = assert(c:getpeername())
    assert(ba.sin_family == 2, "expect ipv4 connection")
    assert(tostring(ba.sin_addr) == "127.0.0.1", "expect peer on localhost")
    assert(ba.sin_addr.s_addr == S.INADDR_LOOPBACK.s_addr, "expect peer on localhost")
    local n = assert(c:send(teststring))
    assert(n == #teststring, "should be able to write out short string")
    n = assert(a.fd:read(buf, size))
    assert(n == #teststring, "should read back string into buffer")
    assert(ffi.string(buf, n) == teststring, "we should read back the same string that was sent")
    -- test scatter gather
    local b0 = t.buffer(4)
    local b1 = t.buffer(3)
    ffi.copy(b0, "test", 4) -- string init adds trailing 0 byte
    ffi.copy(b1, "ing", 3)
    n = assert(c:writev({{b0, 4}, {b1, 3}}))
    assert(n == 7, "expect writev to write 7 bytes")
    b0 = t.buffer(3)
    b1 = t.buffer(4)
    local iov = t.iovecs{{b0, 3}, {b1, 4}}
    n = assert(a.fd:readv(iov))
    assert_equal(n, 7, "expect readv to read 7 bytes")
    assert(ffi.string(b0, 3) == "tes" and ffi.string(b1, 4) == "ting", "expect to get back same stuff")
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
    assert(sv:close())
  end,
  test_sendcred = function()
    local sv = assert(S.socketpair("unix", "stream"))
    assert(sv[2]:setsockopt("socket", "passcred", true)) -- enable receive creds
    local so = assert(sv[2]:getsockopt(c.SOL.SOCKET, c.SO.PASSCRED))
    assert(so == 1, "getsockopt should have updated value")
    assert(sv[1]:sendmsg()) -- sends single byte, which is enough to send credentials
    local r = assert(sv[2]:recvmsg())
    assert(r.pid == S.getpid(), "expect to get my pid from sending credentials")
    assert(sv[1]:sendfds(S.stdin))
    local r = assert(sv[2]:recvmsg())
    assert(#r.fd == 1, "expect to get one file descriptor back")
    assert(r.fd[1]:close())
    assert(r.pid == S.getpid(), "should get my pid from sent credentals")
    assert(sv:close())
  end,
  test_sigpipe = function()
    local sv = assert(S.socketpair("unix", "stream"))
    assert(sv[1]:shutdown("rd"))
    assert(S.signal("pipe", "ign"))
    assert(sv[2]:close())
    local n, err = sv[1]:write("will get sigpipe")
    assert(err.PIPE, "should get sigpipe")
    assert(sv[1]:close())
  end,
  test_udp_socket = function()
    local loop = "127.0.0.1"
    local s = assert(S.socket("inet", "dgram"))
    local c = assert(S.socket("inet", "dgram"))
    local sa = assert(t.sockaddr_in(0, loop))
    local ca = assert(t.sockaddr_in(0, loop))
    assert(s:bind(sa))
    assert(c:bind(sa))
    local bca = c:getsockname() -- find bound address
    local serverport = s:getsockname().port -- find bound port
    local n = assert(s:sendto(teststring, nil, 0, bca))
    local f = assert(c:recvfrom(buf, size)) -- do not test as can drop data
    assert(s:close())
    assert(c:close())
  end,
  test_ipv6_socket = function()
    local s, err = S.socket("inet6", "dgram")
    if s then
      local c = assert(S.socket("inet6", "dgram"))
      local sa = assert(t.sockaddr_in6(0, S.in6addr_any))
      local ca = assert(t.sockaddr_in6(0, S.in6addr_any))
      assert_equal(tostring(sa.sin6_addr), "::", "expect :: for in6addr_any")
      assert(s:bind(sa))
      assert(c:bind(sa))
      local bca = c:getsockname() -- find bound address
      local serverport = s:getsockname().port -- find bound port
      local n = assert(s:sendto(teststring, nil, 0, bca))
      local f = assert(c:recvfrom(buf, size))
      assert(f.count == #teststring, "should get the whole string back")
      assert(f.addr.port == serverport, "should be able to get server port in recvfrom")
      assert(c:close())
      assert(s:close())
    else assert(err.AFNOSUPPORT, err) end -- fairly common to not have ipv6 in kernel
  end,
  test_ipv6_names = function()
    local sa = assert(t.sockaddr_in6(1234, "2002::4:5"))
    assert_equal(sa.port, 1234, "want same port back")
    assert_equal(tostring(sa.sin6_addr), "2002::4:5", "expect same address back")
  end
}

test_netlink = {
  test_getlink = function()
    local i = assert(nl.getlink())
    local df = assert(S.ls("/sys/class/net", true))
    assert_equal(#df, #i, "expect same number of interfaces as /sys/class/net")
    assert(i.lo, "expect a loopback interface")
    local lo = i.lo
    assert(lo.flags.up, "loopback interface should be up")
    assert(lo.flags.loopback, "loopback interface should be marked as loopback")
    assert(lo.flags.running, "loopback interface should be running")
    assert(not lo.flags.broadcast, "loopback interface should not be broadcast")
    assert(not lo.flags.multicast, "loopback interface should not be multicast")
    assert_equal(tostring(lo.macaddr), "00:00:00:00:00:00", "null hardware address on loopback")
    assert(lo.loopback, "loopback interface type should be loopback") -- TODO add getflag
    assert_equal(lo.mtu, 16436, "expect lo MTU is 16436")
    local eth = i.eth0 or i.eth1 -- may not exist
    if eth then
      assert(eth.flags.broadcast, "ethernet interface should be broadcast")
      assert(eth.flags.multicast, "ethernet interface should be multicast")
      assert(eth.ether, "ethernet interface type should be ether")
      assert_equal(eth.addrlen, 6, "ethernet hardware address length is 6")
      local mac = assert(S.readfile("/sys/class/net/" .. eth.name .. "/address"), "expect eth to have address file in /sys")
      assert_equal(tostring(eth.macaddr) .. '\n', mac, "mac address hsould match that from /sys")
      assert_equal(tostring(eth.broadcast), 'ff:ff:ff:ff:ff:ff', "ethernet broadcast mac")
      local mtu = assert(S.readfile("/sys/class/net/" .. eth.name .. "/mtu"), "expect eth to have mtu in /sys")
      assert_equal(eth.mtu, tonumber(mtu), "expect ethernet MTU to match /sys")
    end
    local wlan = i.wlan0
    if wlan then
      assert(wlan.ether, "wlan interface type should be ether")
      assert_equal(wlan.addrlen, 6, "wireless hardware address length is 6")
      local mac = assert(S.readfile("/sys/class/net/" .. wlan.name .. "/address"), "expect wlan to have address file in /sys")
      assert_equal(tostring(wlan.macaddr) .. '\n', mac, "mac address should match that from /sys")
    end
  end,
  test_get_addresses_in = function()
    local as = assert(nl.getaddr("inet"))
    local lo = assert(nl.getlink()).lo.index
    for i = 1, #as do
      if as[i].index == lo then
        assert_equal(tostring(as[i].addr), "127.0.0.1", "loopback ipv4 on lo")
      end
    end
  end,
  test_get_addresses_in6 = function()
    local as = assert(nl.getaddr("inet6"))
    local lo = assert(nl.getlink()).lo.index
    for i = 1, #as do
      if as[i].index == lo then
        assert_equal(tostring(as[i].addr), "::1", "loopback ipv6 on lo") -- allow fail if no ipv6
      end
    end
  end,
  test_interfaces = function()
    local i = nl.interfaces()
    assert_equal(tostring(i.lo.inet[1].addr), "127.0.0.1", "loopback ipv4 on lo")
    assert_equal(tostring(i.lo.inet6[1].addr), "::1", "loopback ipv6 on lo")
  end,
  test_newlink_flags_root = function()
    local p = assert(S.clone())
     if p == 0 then
      fork_assert(S.unshare("newnet"))
      local i = fork_assert(nl.interfaces())
      fork_assert(i.lo and not i.lo.flags.up, "expect new network ns has down lo interface")
      fork_assert(nl.newlink(i.lo.index, 0, "up", "up"))
      local lo = fork_assert(i.lo:refresh())
      fork_assert(lo.flags.up, "expect lo up now")
      S.exit()
    else
      local w = assert(S.waitpid(-1, "clone"))
      assert(w.EXITSTATUS == 0, "expect normal exit in clone")
    end
  end,
  test_interface_up_down_root = function()
    local i = assert(nl.interfaces())
    assert(i.lo:down())
    assert(not i.lo.flags.up, "expect lo down")
    assert(i.lo:up())
    assert(i.lo.flags.up, "expect lo up now")
  end,
  test_interface_setflags_root = function()
    local p = assert(S.clone())
     if p == 0 then
      fork_assert(S.unshare("newnet"))
      local i = fork_assert(nl.interfaces())
      fork_assert(i.lo, "expect new network ns has lo interface")
      fork_assert(not i.lo.flags.up, "expect new network lo is down")
      fork_assert(i.lo:setflags("up"))
      fork_assert(i.lo.flags.up, "expect lo up now")
      S.exit()
    else
      local w = assert(S.waitpid(-1, "clone"))
      assert(w.EXITSTATUS == 0, "expect normal exit in clone")
    end
  end,
  test_interface_set_mtu_root = function()
    local i = assert(nl.interfaces())
    local lo = assert(i.lo, "expect lo interface")
    assert(lo:up())
    assert(lo.flags.up, "expect lo up now")
    local mtu = lo.mtu
    assert(lo:setmtu(16000))
    assert_equal(lo.mtu, 16000, "expect MTU now 16000")
    assert(lo:setmtu(mtu))
  end,
  test_interface_set_mtu_byname_root = function()
    local i = assert(nl.interfaces())
    local lo = assert(i.lo, "expect lo interface")
    local mtu = lo.mtu
    assert(lo:up())
    assert(nl.newlink(0, 0, "up", "up", "ifname", "lo", "mtu", 16000))
    assert(lo:refresh())
    assert_equal(lo.mtu, 16000, "expect MTU now 16000")
    assert(lo.flags.up, "expect lo up now")
    assert(lo:setmtu(mtu))
  end,
  test_interface_rename_root = function()
    -- using bridge to test this as no other interface in container yet and not sure you can rename lo
    assert(S.bridge_add("br0"))
    local i = assert(nl.interfaces())
    assert(i.br0)
    assert(i.br0:rename("newname"))
    assert(i:refresh())
    assert(i.newname and not i.br0, "interface should be renamed")
    assert(S.bridge_del("newname"))
  end,
  test_interface_set_macaddr_root = function()
    -- using bridge to test this as no other interface in container yet (now could use dummy)
    assert(S.bridge_add("br0"))
    local i = assert(nl.interfaces())
    assert(i.br0)
    assert(i.br0:setmac("46:9d:c9:06:dd:dd"))
    assert_equal(tostring(i.br0.macaddr), "46:9d:c9:06:dd:dd", "interface should have new mac address")
    assert(i.br0:down())
    assert(S.bridge_del("br0"))
  end,
  test_interface_set_macaddr_fail = function()
    local i = assert(nl.interfaces())
    assert(i.lo, "expect to find lo")
    local ok, err = nl.newlink(i.lo.index, 0, 0, 0, "address", "46:9d:c9:06:dd:dd")
    assert(not ok and err and (err.PERM or err.OPNOTSUPP), "should not be able to change macaddr on lo")
  end,
  test_newlink_error_root = function()
    local ok, err = nl.newlink(-1, 0, "up", "up")
    assert(not ok, "expect bogus newlink to fail")
    assert(err.NODEV, "expect no such device error")
  end,
  test_newlink_newif_dummy_root = function()
    local ok, err = nl.create_interface{name = "dummy0", type = "dummy"}
    local i = assert(nl.interfaces())
    assert(i.dummy0, "expect dummy interface")
    assert(i.dummy0:delete())
  end,
  test_newlink_newif_bridge_root = function()
    assert(nl.create_interface{name = "br0", type = "bridge"})
    local i = assert(nl.interfaces())
    assert(i.br0, "expect bridge interface")
    local b = assert(S.bridge_list())
    assert(b.br0, "expect to find new bridge")
    assert(i.br0:delete())
  end,
  test_dellink_by_name_root = function()
    assert(nl.create_interface{name = "dummy0", type = "dummy"})
    local i = assert(nl.interfaces())
    assert(i.dummy0, "expect dummy interface")
    assert(nl.dellink(0, "ifname", "dummy0"))
    local i = assert(nl.interfaces())
    assert(not i.dummy0, "expect dummy interface gone")
  end,
  test_newaddr_root = function()
    local lo = assert(nl.interface("lo"))
    assert(nl.newaddr(lo, "inet6", 128, "permanent", "address", "::2"))
    assert(lo:refresh())
    assert_equal(#lo.inet6, 2, "expect two inet6 addresses on lo now")
    if tostring(lo.inet6[1].addr) == "::1"
      then assert_equal(tostring(lo.inet6[2].addr), "::2")
      else assert_equal(tostring(lo.inet6[1].addr), "::2")
    end
    assert_equal(lo.inet6[2].prefixlen, 128, "expect /128")
    assert_equal(lo.inet6[1].prefixlen, 128, "expect /128")
    assert(nl.deladdr(lo.index, "inet6", 128, "address", "::2"))
    assert(lo:refresh())
    assert_equal(#lo.inet6, 1, "expect one inet6 addresses on lo now")
    assert_equal(tostring(lo.inet6[1].addr), "::1", "expect only ::1 now")
    -- TODO this leaves a route to ::2 which we should delete
  end,
  test_newaddr_helper_root = function()
    local lo = assert(nl.interface("lo"))
    assert(lo:address("::2/128"))
    assert(lo:refresh())
    assert_equal(#lo.inet6, 2, "expect two inet6 addresses on lo now")
    if tostring(lo.inet6[1].addr) == "::1"
      then assert_equal(tostring(lo.inet6[2].addr), "::2")
      else assert_equal(tostring(lo.inet6[1].addr), "::2")
    end
    assert_equal(lo.inet6[2].prefixlen, 128, "expect /128")
    assert_equal(lo.inet6[1].prefixlen, 128, "expect /128")
    assert(lo:deladdress("::2"))
    assert_equal(#lo.inet6, 1, "expect one inet6 addresses on lo now")
    assert_equal(tostring(lo.inet6[1].addr), "::1", "expect only ::1 now")
    -- TODO this leaves a route to ::2 which we should delete
  end,
  test_getroute_inet = function()
    local r = assert(nl.routes("inet", "unspec"))
    local nr = r:match("127.0.0.0/32")
    assert_equal(#nr, 1, "expect 1 route")
    local lor = nr[1]
    assert_equal(tostring(lor.source), "0.0.0.0", "expect empty source route")
    assert_equal(lor.output, "lo", "expect to be on lo")
  end,
  test_getroute_inet6 = function()
    local r = assert(nl.routes("inet6", "unspec"))
    local nr = r:match("::1/128")
    assert_equal(#nr, 1, "expect one matched route")
    local lor = nr[1]
    assert_equal(tostring(lor.source), "::", "expect empty source route")
    assert_equal(lor.output, "lo", "expect to be on lo")
  end,
  test_newroute_inet6_root = function()
    local r = assert(nl.routes("inet6", "unspec"))
    local lo = assert(nl.interface("lo"))
    assert(nl.newroute("create", {family = "inet6", dst_len = 128, type = "unicast", protocol = "static"}, "dst", "::3", "oif", lo.index))
    r:refresh()
    local nr = r:match("::3/128")
    assert_equal(#nr, 1, "expect to find new route")
    nr = nr[1]
    assert_equal(nr.oif, lo.index, "expect route on lo")
    assert_equal(nr.output, "lo", "expect route on lo")
    assert_equal(nr.dst_len, 128, "expect /128")
    assert(nl.delroute({family = "inet6", dst_len = 128}, "dst", "::3", "oif", lo.index))
    r:refresh()
    local nr = r:match("::3/128")
    assert_equal(#nr, 0, "expect route deleted")
  end,
  test_netlink_events_root = function()
    local sock = assert(nl.socket("route", {groups = "link"}))
    assert(nl.create_interface{name = "dummy1", type = "dummy"})
    local m = assert(nl.read(sock))
    assert(m.dummy1, "should find dummy 1 in returned info")
    assert_equal(m.dummy1.op, "newlink", "new interface")
    assert(m.dummy1.newlink, "new interface")
    assert(m.dummy1:setmac("46:9d:c9:06:dd:dd"))
    assert(m.dummy1:delete())
    local m = assert(nl.read(sock))
    assert(m.dummy1, "should get info about deleted interface")
    assert_equal(tostring(m.dummy1.macaddr), "46:9d:c9:06:dd:dd", "should get address that was set")
    assert(sock:close())
  end,
  test_move_interface_ns_root = function()
    assert(nl.create_interface{name = "dummy0", type = "dummy"})
    local i = assert(nl.interfaces())
    assert(i.dummy0, "expect dummy0 interface")
    local p = assert(S.clone("newnet"))
    if p == 0 then
      local sock = assert(nl.socket("route", {groups = "link"}))
      local i = fork_assert(nl.interfaces())
      if not i.dummy0 then
        local m = assert(nl.read(sock))
        fork_assert(m.dummy0, "expect dummy0 appeared")
      end
      fork_assert(sock:close())
      local i = fork_assert(nl.interfaces())
      fork_assert(i.dummy0, "expect dummy0 interface in child")
      fork_assert(i.dummy0:delete())
      fork_assert(i:refresh())
      fork_assert(not i.dummy0, "expect no dummy if")
      S.exit()
    else
      assert(i.dummy0:move_ns(p))
      assert(i:refresh())
      assert(not i.dummy0, "expect dummy0 vanished")
      local w = assert(S.waitpid(-1, "clone"))
      assert(w.EXITSTATUS == 0, "expect normal exit in clone")
    end
  end,
  test_netlink_veth_root = function()
    assert(nl.newlink(0, c.NLMSG_NEWLINK.CREATE, 0, 0, "linkinfo", {"kind", "veth", "data", {"peer", {t.ifinfomsg, {}, "ifname", "veth1"}}}, "ifname", "veth0"))
    local i = assert(nl.interfaces())
    assert(i.veth0, "expect veth0")
    assert(i.veth1, "expect veth1")
    assert(nl.dellink(0, "ifname", "veth0"))
    assert(i:refresh())
    assert(not i.veth0, "expect no veth0")
    assert(not i.veth1, "expect no veth1")
  end,
  test_create_veth_root = function()
    -- TODO create_interface version
    assert(nl.create_interface{name = "veth0", type = "veth", peer = {name = "veth1"}})
    local i = assert(nl.interfaces())
    assert(i.veth0, "expect veth0")
    assert(i.veth1, "expect veth1")
    assert(nl.dellink(0, "ifname", "veth0"))
    assert(i:refresh())
    assert(not i.veth0, "expect no veth0")
    assert(not i.veth1, "expect no veth1")
  end,
}

test_termios = {
  test_pts_termios = function()
    local ptm = assert(S.posix_openpt("rdwr, noctty"))
    assert(ptm:grantpt())
    assert(ptm:unlockpt())
    local pts_name = assert(ptm:ptsname())
    local pts = assert(S.open(pts_name, "rdwr, noctty"))
    assert(pts:isatty(), "should be a tty")
    local termios = assert(pts:tcgetattr())
    assert(termios:cfgetospeed() ~= 115200)
    termios:cfsetspeed(115200)
    assert_equal(termios:cfgetispeed(), 115200, "expect input speed as set")
    assert_equal(termios:cfgetospeed(), 115200, "expect output speed as set")
    assert(bit.band(termios.c_lflag, c.LFLAG.ICANON) ~= 0)
    termios:cfmakeraw()
    assert(bit.band(termios.c_lflag, c.LFLAG.ICANON) == 0)
    assert(pts:tcsetattr("now", termios))
    termios = assert(pts:tcgetattr())
    assert(termios:cfgetospeed() == 115200)
    assert(bit.band(termios.c_lflag, c.LFLAG.ICANON) == 0)
    assert(pts:tcsendbreak(0))
    assert(pts:tcdrain())
    assert(pts:tcflush('ioflush'))
    assert(pts:tcflow('ooff'))
    assert(pts:tcflow('ioff'))
    assert(pts:tcflow('oon'))
    assert(pts:tcflow('ion'))
    assert(pts:close())
    assert(ptm:close())
  end,
  test_isatty_fail = function()
    local fd = S.open("/dev/zero")
    assert(not fd:isatty(), "not a tty")
    assert(fd:close())
  end,
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
  end,
  test_poll = function()
    local sv = assert(S.socketpair("unix", "stream"))
    local a, b = sv[1], sv[2]
    local pev = {{fd = a, events = "in"}}
    local p = assert(S.poll(pev, 0))
    assert(p[1].fd == a:getfd() and p[1].revents == 0, "no events")
    assert(b:write(teststring))
    local p = assert(S.poll(pev, 0))
    assert(p[1].fd == a:getfd() and p[1].IN, "one event now")
    assert(a:read())
    assert(b:close())
    assert(a:close())
  end,
  test_ppoll = function()
    local sv = assert(S.socketpair("unix", "stream"))
    local a, b = sv[1], sv[2]
    local pev = {{fd = a, events = c.POLL.IN}}
    local p = assert(S.ppoll(pev, 0, nil))
    assert(p[1].fd == a:getfd() and p[1].revents == 0, "one event now")
    assert(b:write(teststring))
    local p = assert(S.ppoll(pev, nil, "alrm"))
    assert(p[1].fd == a:getfd() and p[1].IN, "one event now")
    assert(a:read())
    assert(b:close())
    assert(a:close())
  end,
  test_select = function()
    local sv = assert(S.socketpair("unix", "stream"))
    local a, b = sv[1], sv[2]
    local sel = assert(S.select{readfds = {a, b}, timeout = t.timeval(0,0)})
    assert(sel.count == 0, "nothing to read select now")
    assert(b:write(teststring))
    sel = assert(S.select{readfds = {a, b}, timeout = {0, 0}})
    assert(sel.count == 1, "one fd available for read now")
    assert(b:close())
    assert(a:close())
  end,
  test_pselect = function()
    local sv = assert(S.socketpair("unix", "stream"))
    local a, b = sv[1], sv[2]
    local sel = assert(S.pselect{readfds = {1, b}, timeout = 0, sigset = "alrm"})
    assert(sel.count == 0, "nothing to read select now")
    assert(b:write(teststring))
    sel = assert(S.pselect{readfds = {a, b}, timeout = 0, sigset = sel.sigset})
    assert(sel.count == 1, "one fd available for read now")
    assert(b:close())
    assert(a:close())
  end,
  test_epoll = function()
    local sv = assert(S.socketpair("unix", "stream"))
    local a, b = sv[1], sv[2]
    local ep = assert(S.epoll_create("cloexec"))
    assert(ep:epoll_ctl("add", a, "in"))
    local r = assert(ep:epoll_wait(nil, 1, 0))
    assert(#r == 0, "no events yet")
    assert(b:write(teststring))
    r = assert(ep:epoll_wait())
    assert(#r == 1, "one event now")
    assert(r[1].IN, "read event")
    assert(r[1].fd == a:getfd(), "expect to get fd of ready file back") -- by default our epoll_ctl sets this
    assert(ep:close())
    assert(a:read()) -- clear event
    assert(b:close())
    assert(a:close())
  end
}

test_aio = {
  teardown = clean,
  test_aio_setup = function()
    local ctx = assert(S.io_setup(8))
    assert(S.io_destroy(ctx))
  end,
--[[ -- temporarily disabled gc and methods on aio
  test_aio_ctx_gc = function()
    local ctx = assert(S.io_setup(8))
    local ctx2 = t.aio_context()
    ffi.copy(ctx2, ctx, s.aio_context)
    ctx = nil
    collectgarbage("collect")
    local ok, err = S.io_destroy(ctx2)
    assert(not ok, "should have closed aio ctx")
  end,
]]
  test_aio = function()
    local abuf = assert(S.mmap(nil, 4096, "read, write", "private, anonymous", -1, 0))
    ffi.copy(abuf, teststring)
    local fd = S.open(tmpfile, "creat, direct, rdwr", "RWXU") -- use O_DIRECT or aio may not
    assert(S.unlink(tmpfile))
    assert(fd:pwrite(abuf, 4096, 0))
    ffi.fill(abuf, 4096)
    local ctx = assert(S.io_setup(8))
    assert_equal(S.io_submit(ctx, {{cmd = "pread", data = 42, fd = fd, buf = abuf, nbytes = 4096, offset = 0}}), 1)
    local r = assert(S.io_getevents(ctx, 1, 1))
    assert(#r == 1, "expect one aio event") -- TODO test what is returned
    assert(fd:close())
    assert(S.munmap(abuf, 4096))
  end,
  test_aio_cancel = function()
    local abuf = assert(S.mmap(nil, 4096, "read, write", "private, anonymous", -1, 0))
    ffi.copy(abuf, teststring)
    local fd = S.open(tmpfile, "creat, direct, rdwr", "RWXU")
    assert(S.unlink(tmpfile))
    assert(fd:pwrite(abuf, 4096, 0))
    ffi.fill(abuf, 4096)
    local ctx = assert(S.io_setup(8))
    assert_equal(S.io_submit(ctx, {{cmd = "pread", data = 42, fd = fd, buf = abuf, nbytes = 4096, offset = 0}}), 1)
    -- erroring, giving EINVAL which is odd, man page says means ctx invalid TODO fix
    --local r, err = S.io_cancel(ctx, {cmd = "pread", data = 42, fd = fd, buf = abuf, nbytes = 4096, offset = 0})
    --r = assert(S.io_getevents(ctx, 1, 1))
    --assert(#r == 0, "expect no aio events")
    assert(S.io_destroy(ctx))
    assert(fd:close())
    assert(S.munmap(abuf, 4096))
  end,
  test_aio_eventfd = function()
    local abuf = assert(S.mmap(nil, 4096, "read, write", "private, anonymous", -1, 0))
    ffi.copy(abuf, teststring)
    local fd = S.open(tmpfile, "creat, direct, rdwr", "RWXU") -- need to use O_DIRECT for aio to work
    assert(S.unlink(tmpfile))
    assert(fd:pwrite(abuf, 4096, 0))
    ffi.fill(abuf, 4096)
    local ctx = assert(S.io_setup(8))
    local efd = assert(S.eventfd())
    local ep = assert(S.epoll_create())
    assert(ep:epoll_ctl("add", efd, "in"))
    assert_equal(S.io_submit(ctx, {{cmd = "pread", data = 42, fd = fd, buf = abuf, nbytes = 4096, offset = 0, resfd = efd}}), 1)
    local r = assert(ep:epoll_wait())
    assert_equal(#r, 1, "one event now")
    assert(efd:close())
    assert(ep:close())
    assert(S.io_destroy(ctx))
    assert(fd:close())
    assert(S.munmap(abuf, 4096))
  end,
}

test_processes = {
  test_proc_self = function()
    local p = assert(S.proc())
    assert(not p.wrongname, "test non existent files")
    assert(p.cmdline and #p.cmdline > 1, "expect cmdline to exist")
    assert(p.exe and #p.exe > 1, "expect an executable")
    assert_equal(p.root, "/", "expect our root to be / usually")
  end,
  test_proc_init = function()
    local p = S.proc(1)
    assert(p and p.cmdline, "expect init to have cmdline")
    assert(p.cmdline:find("init") or p.cmdline:find("systemd"), "expect init or systemd to be process 1 usually")
  end,
  test_ps = function()
    local ps = S.ps()
    local me = S.getpid()
    local found = false
    for i = 1, #ps do
      if ps[i].pid == 1 then
        assert(ps[i].cmdline:find("init") or ps[i].cmdline:find("systemd"), "expect init or systemd to be process 1 usually")
      end
      if ps[i].pid == me then found = true end
    end
    assert(found, "expect to find my process in ps")
    assert(tostring(ps), "can convert ps to string")
  end,
  test_nice = function()
    local n = assert(S.getpriority("process"))
    assert (n == 0, "process should start at priority 0")
    assert(S.nice(1))
    assert(S.setpriority("process", 0, 1)) -- sets to 1, which it already is
    if S.geteuid() ~= 0 then
      local n, err = S.nice(-2)
      assert(err, "non root user should not be able to set negative priority")
      local n, err = S.setpriority("process", 0, -1)
      assert(err, "non root user should not be able to set negative priority")
    end
  end,
  test_fork = function() -- TODO split up
    local pid0 = S.getpid()
    assert(pid0 > 1, "expecting my pid to be larger than 1")
    assert(S.getppid() > 1, "expecting my parent pid to be larger than 1")

    assert(S.getsid())
    S.setsid() -- may well fail

    local pid = assert(S.fork())
    if pid == 0 then -- child
      fork_assert(S.getppid() == pid0, "parent pid should be previous pid")
      S.exit(23)
    else -- parent
      local w = assert(S.wait())
      assert(w.pid == pid, "expect fork to return same pid as wait")
      assert(w.WIFEXITED, "process should have exited normally")
      assert(w.EXITSTATUS == 23, "exit should be 23")
    end

    pid = assert(S.fork())
    if (pid == 0) then -- child
      fork_assert(S.getppid() == pid0, "parent pid should be previous pid")
      S.exit(23)
    else -- parent
      local w = assert(S.waitid("all", 0, "exited, stopped, continued"))
      assert(w.si_signo == c.SIG.CHLD, "waitid to return SIGCHLD")
      assert(w.si_status == 23, "exit should be 23")
      assert(w.si_code == c.SIGCLD.EXITED, "normal exit expected")
    end

    pid = assert(S.fork())
    if (pid == 0) then -- child
      local script = [[
#!/bin/sh

[ $1 = "test" ] || (echo "shell assert $1"; exit 1)
[ $2 = "ing" ] || (echo "shell assert $2"; exit 1)
[ $PATH = "/bin:/usr/bin" ] || (echo "shell assert $PATH"; exit 1)

]]
      fork_assert(S.writefile(efile, script, "RWXU"))
      fork_assert(S.execve(efile, {efile, "test", "ing"}, {"PATH=/bin:/usr/bin"})) -- note first param of args overwritten
      -- never reach here
      os.exit()
    else -- parent
      local w = assert(S.waitpid(-1))
      assert(w.pid == pid, "expect fork to return same pid as wait")
      assert(w.WIFEXITED, "process should have exited normally")
      assert(w.EXITSTATUS == 0, "exit should be 0")
      assert(S.unlink(efile))
    end
  end,
  test_clone = function()
    local pid0 = S.getpid()
    local p = assert(S.clone()) -- no flags, should be much like fork.
    if p == 0 then -- child
      fork_assert(S.getppid() == pid0, "parent pid should be previous pid")
      S.exit(23)
    else -- parent
      local w = assert(S.waitpid(-1, "clone"))
      assert_equal(w.pid, p, "expect clone to return same pid as wait")
      assert(w.WIFEXITED, "process should have exited normally")
      assert(w.EXITSTATUS == 23, "exit should be 23")
    end
  end,
}

test_ids = {
  test_setuid = function()
    assert(S.setuid(S.getuid()))
  end,
  test_setgid = function()
    assert(S.setgid(S.getgid()))
  end,
  test_setgid_root = function()
    local gid = S.getgid()
    assert(S.setgid(66))
    assert_equal(S.getgid(), 66, "gid should be as set")
    assert(S.setgid(gid))
    assert_equal(S.getgid(), gid, "gid should be as set")
  end,
  test_seteuid = function()
    assert(S.seteuid(S.geteuid()))
  end,
  test_seteuid_root = function()
    local uid = S.geteuid()
    assert(S.seteuid(66))
    assert_equal(S.geteuid(), 66, "gid should be as set")
    assert(S.seteuid(uid))
    assert_equal(S.geteuid(), uid, "gid should be as set")
  end,
  test_setegid = function()
    assert(S.setegid(S.getegid()))
  end,
  test_setegid_root = function()
    local gid = S.getegid()
    assert(S.setegid(66))
    assert_equal(S.getegid(), 66, "gid should be as set")
    assert(S.setegid(gid))
    assert_equal(S.getegid(), gid, "gid should be as set")
  end,
  test_setreuid = function()
    assert(S.setreuid(S.geteuid(), S.getuid()))
  end,
  test_setregid = function()
    assert(S.setregid(S.getegid(), S.getgid()))
  end,
  test_getresuid = function()
    local u = assert(S.getresuid())
    assert_equal(u.ruid, S.getuid(), "real uid same")
    assert_equal(u.euid, S.geteuid(), "effective uid same")
  end,
  test_getresgid = function()
    local g = assert(S.getresgid())
    assert_equal(g.rgid, S.getgid(), "real gid same")
    assert_equal(g.egid, S.getegid(), "effective gid same")
  end,
  test_setresuid = function()
    local u = assert(S.getresuid())
    assert(S.setresuid(u))
  end,
  test_resuid_root = function()
    local u = assert(S.getresuid())
    assert(S.setresuid(0, 33, 44))
    local uu = assert(S.getresuid())
    assert_equal(uu.ruid, 0, "real uid as set")
    assert_equal(uu.euid, 33, "effective uid as set")
    assert_equal(uu.suid, 44, "saved uid as set")
    assert(S.setresuid(u))
  end,
  test_setresgid = function()
    local g = assert(S.getresgid())
    assert(S.setresgid(g))
  end,
  test_resgid_root = function()
    local g = assert(S.getresgid())
    assert(S.setresgid(0, 33, 44))
    local gg = assert(S.getresgid())
    assert_equal(gg.rgid, 0, "real gid as set")
    assert_equal(gg.egid, 33, "effective gid as set")
    assert_equal(gg.sgid, 44, "saved gid as set")
    assert(S.setresgid(g))
  end,
  test_getgroups = function()
    local g = assert(S.getgroups())
    assert(#g, "groups behaves like a table")
  end,
  test_setgroups_root = function()
    local og = assert(S.getgroups())
    assert(S.setgroups{0, 1, 66, 77, 5})
    local g = assert(S.getgroups())
    assert_equal(#g, 5, "expect 5 groups now")
    assert(S.setgroups(og))
    local g = assert(S.getgroups())
    assert_equal(#g, #og, "expect same number of groups as previously")
  end,
}

test_namespaces_root = {
  test_netns = function()
    local p = assert(S.clone("newnet"))
    if p == 0 then
      local i = fork_assert(nl.interfaces())
      fork_assert(i.lo and not i.lo.flags.up, "expect new network ns only has down lo interface")
      S.exit()
    else
      assert(S.waitpid(-1, "clone"))
    end
  end,
  test_netns_unshare = function()
    local p = assert(S.clone())
    if p == 0 then
      local ok = fork_assert(S.unshare("newnet"))
      local i = fork_assert(nl.interfaces())
      fork_assert(i.lo and not i.lo.flags.up, "expect new network ns only has down lo interface")
      S.exit()
    else
      assert(S.waitpid(-1, "clone"))
    end
  end,
  test_pidns = function()
    local p = assert(S.clone("newpid"))
    if p == 0 then
      fork_assert(S.getpid() == 1, "expec our pid to be 1 new new process namespace")
      S.exit()
    else
      assert(S.waitpid(-1, "clone"))
    end
  end,
  test_setns = function()
    local fd = assert(S.open("/proc/self/ns/net"))
    assert(fd:setns("newnet"))
    assert(fd:close())
  end,
  test_setns_fail = function()
    local fd = assert(S.open("/proc/self/ns/net"))
    assert(not fd:setns("newipc"))
    assert(fd:close())
  end,
}

test_filesystem = {
  test_statfs = function()
    local st = assert(S.statfs("."))
    assert(st.f_bfree < st.f_blocks, "expect less free space than blocks")
  end,
  test_fstatfs = function()
    local fd = assert(S.open(".", "rdonly"))
    local st = assert(S.fstatfs(fd))
    assert(st.f_bfree < st.f_blocks, "expect less free space than blocks")
    assert(fd:close())
  end,
  test_futimens = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(fd:futimens())
    local st1 = fd:stat()
    assert(fd:futimens{"omit", "omit"})
    local st2 = fd:stat()
    assert(st1.atime == st2.atime and st1.mtime == st2.mtime, "atime and mtime unchanged")
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_utimensat = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    local dfd = assert(S.open("."))
    assert(S.utimensat(nil, tmpfile))
    local st1 = fd:stat()
    assert(S.utimensat(dfd, tmpfile, {"omit", "omit"}))
    local st2 = fd:stat()
    assert(st1.atime == st2.atime and st1.mtime == st2.mtime, "atime and mtime unchanged")
    assert(S.unlink(tmpfile))
    assert(fd:close())
    assert(dfd:close())
  end,
  test_utime = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    local st1 = fd:stat()
    assert(S.utime(tmpfile, 100, 200))
    local st2 = fd:stat()
    assert(st1.atime ~= st2.atime and st1.mtime ~= st2.mtime, "atime and mtime changed")
    assert(st2.atime == 100 and st2.mtime == 200, "times as set")
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
}

test_misc_root = {
  test_mount = function()
    assert(S.mkdir(tmpfile))
    assert(S.mount("none", tmpfile, "tmpfs", "rdonly, noatime"))
    assert(S.umount(tmpfile, "detach, nofollow"))
    assert(S.rmdir(tmpfile))
  end,
  test_mount_table = function()
    assert(S.mkdir(tmpfile))
    assert(S.mount{source = "none", target = tmpfile, type = "tmpfs", flags = "rdonly, noatime"})
    assert(S.umount(tmpfile))
    assert(S.rmdir(tmpfile))
  end,
  test_mounts = function()
    local cwd = assert(S.getcwd())
    local dir = cwd .. "/" .. tmpfile
    assert(S.mkdir(dir))
    local a = {source = "none", target = dir, type = "tmpfs", flags = "rdonly, noatime"}
    assert(S.mount(a))
    local m = assert(S.mounts())
    assert(#m > 0, "expect at least one mount point")
    local b = m[#m]
    assert_equal(b.source, a.source, "expect source match")
    assert_equal(b.target, a.target, "expect target match")
    assert_equal(b.type, a.type, "expect type match")
    assert_equal(c.MS[b.flags], c.MS[a.flags], "expect flags match")
    assert_equal(b.freq, "0")
    assert_equal(b.passno, "0")
    assert(S.umount(dir))
    assert(S.rmdir(dir))
  end,
  test_acct = function()
    S.acct() -- may not be configured
  end,
  test_sethostname = function()
    local h = S.gethostname()
    local hh = "testhostname"
    assert(S.sethostname(hh))
    assert_equal(hh, assert(S.gethostname()))
    assert(S.sethostname(h))
    assert_equal(h, assert(S.gethostname()))
  end,
  test_bridge = function()
    local ok, err = S.bridge_add("br0")
    assert(ok or err.NOPKG, err) -- ok not to to have bridge in kernel
    if ok then
      local i = assert(nl.interfaces())
      assert(i.br0)
      local b = assert(S.bridge_list())
      assert(b.br0 and b.br0.bridge.root_id, "expect to find bridge in list")
      assert(S.bridge_del("br0"))
      i = assert(nl.interfaces())
      assert(not i.br0, "bridge should be gone")
    end
  end,
  test_chroot = function()
    assert(S.chroot("/"))
  end,
  test_pivot_root = function()
    assert(S.mkdir(tmpfile3))
    local p = assert(S.clone("newns"))
    if p == 0 then
      fork_assert(S.mount(tmpfile3, tmpfile3, "none", "bind")) -- to make sure on different mount point
      fork_assert(S.mount(tmpfile3, tmpfile3, nil, "private"))
      fork_assert(S.chdir(tmpfile3))
      fork_assert(S.mkdir("old"))
      fork_assert(S.pivot_root(".", "old"))
      fork_assert(S.chdir("/"))
      local d = fork_assert(S.dirfile("/"))
      fork_assert(d["old"])
      --fork_assert(S.umount("old")) -- returning busy, TODO need to sort out why.
      S.exit()
    else
      local w = assert(S.waitpid(-1, "clone"))
      assert(w.EXITSTATUS == 0, "expect normal exit in clone")
    end
    assert(S.rmdir(tmpfile3 .. "/old")) -- until we can unmount above
    assert(S.rmdir(tmpfile3))
  end,
  test_reboot = function()
    local p = assert(S.clone("newpid"))
    if p == 0 then
      fork_assert(S.reboot("restart")) -- will send SIGHUP to us as in pid namespace NB older kernels may reboot! if so disable test
      S.pause()
    else
      local w = assert(S.waitpid(-1, "clone"))
      assert(w.IFSIGNALED, "expect signal killed process")
    end
  end,
}

-- note at present we check for uid 0, but could check capabilities instead.
if S.geteuid() == 0 then

  -- some tests are causing issues, eg one of my servers reboots on pivot_root
  if not (arg[1] and arg[1] == "all") then
    test_misc_root.test_pivot_root = nil
  else
    arg[1] = nil
  end

  assert(S.unshare("newnet, newns, newuts")) -- do not interfere with anything on host during tests
  local i = assert(nl.interfaces())
  local lo = assert(i.lo)
  assert(lo:up())
  assert(S.mount("none", "/sys", "sysfs"))
else -- remove tests that need root
  for k in pairs(_G) do
    if k:match("test") then
      if k:match("root")
      then _G[k] = nil;
      else
        for j in pairs(_G[k]) do
          if j:match("test") and j:match("root") then _G[k][j] = nil end
        end
      end
    end
  end
end

local f
if arg[1] and arg[1] ~= "coverage" then f = luaunit:run(arg[1]) else f = luaunit:run() end

clean()

debug.sethook()

if f ~= 0 then S.exit("failure") end

-- TODO iterate through all functions in S and upvalues for active rather than trace
-- also check for non interesting cases, eg fall through to end
-- TODO add more files

if arg[1] == "coverage" then
  cov.covered = 0
  cov.count = 0
  cov.nocov = {}
  cov.max = 1
  for k, _ in pairs(cov.active) do
    cov.count = cov.count + 1
    if k > cov.max then cov.max = k end
  end
  for k, _ in pairs(cov.cov) do
    cov.active[k] = nil
    cov.covered = cov.covered + 1
  end
  for k, _ in pairs(cov.active) do
    cov.nocov[k] = true
  end
  local gs, ge
  for i = 1, cov.max do
    if cov.nocov[i] then
      if gs then ge = i else gs, ge = i, i end
    else
      if gs then
        if gs == ge then
          print("no coverage of line " .. gs)
        else
          print("no coverage of lines " .. gs .. "-" .. ge)
        end
      end
      gs, ge = nil, nil
    end
  end
  print("\ncoverage is " .. cov.covered .. " of " .. cov.count .. " " .. math.floor(cov.covered / cov.count * 100) .. "%")
end

collectgarbage("collect")

S.exit("success")



