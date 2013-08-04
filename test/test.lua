-- test suite for ljsyscall.

-- TODO stop using globals for tests

arg = arg or {}

-- only use this installation for tests
package.path = "./?.lua;"

local strict = require "include.strict.strict"

local oldassert = assert
local function assert(cond, s)
  collectgarbage("collect") -- force gc, to test for bugs
  return oldassert(cond, tostring(s)) -- annoyingly, assert does not call tostring!
end

local helpers = require "syscall.helpers"

local S, rump

if arg[1] == "rump" or arg[1] == "rumplinux" then
  local abi
  -- it is too late to set this now, needs to be set before executions starts
  if jit.os == "Linux" then
    assert(os.getenv("LD_DYNAMIC_WEAK"), "you need to set LD_DYNAMIC_WEAK=1 before running this test")
  end
  if arg[1] == "rumplinux" then
    abi = require "syscall.rump.abi"
    abi.types = "linux" -- monkeypatch
  end
  local modules = {"vfs", "kern.tty", "dev", "net", "fs.tmpfs", "fs.kernfs", "fs.ptyfs",
                   "net.net", "net.local", "net.netinet", "net.shmif"}
  S = require "syscall.rump.init".init(modules)
  table.remove(arg, 1)
  rump = true
else
  S = require "syscall"
end

local abi = S.abi
local types = S.types
local t, pt, s = types.t, types.pt, types.s
local c = S.c
local features = S.features
local util = S.util

if rump and abi.types == "linux" then -- Linux rump ABI cannot do much, so switch from root so it does not try
  assert(S.chmod("/", "0777"))
  assert(S.chmod("/dev/zero", "0666"))
  assert(S.mkdir("/tmp", "0777"))
  local pid = S.getpid()
  assert(S.rump.newlwp(pid))
  local lwp1 = assert(S.rump.curlwp())
  assert(S.rump.newlwp(pid))
  local lwp2 = assert(S.rump.curlwp())
  S.rump.switchlwp(lwp1)
  S.rump.i_know_what_i_am_doing_sysent_usenative() -- switch to netBSD syscalls in this thread
  local data = t.tmpfs_args{ta_version = 1, ta_nodes_max=1000, ta_size_max=104857600, ta_root_mode = helpers.octal("0777")}
  assert(S.mount("tmpfs", "/tmp", 0, data, s.tmpfs_args))
  assert(S.mkdir("/dev/pts", "0555"))
  local data = t.ptyfs_args{version = 2, gid = 0, mode = helpers.octal("0320")}
  assert(S.mount("ptyfs", "/dev/pts", 0, data, s.ptyfs_args))
  assert(S.chdir("/tmp"))
  S.rump.switchlwp(lwp2)
  assert(S.seteuid(100))
end

if rump and S.geteuid() == 0 then -- some initial setup
  local octal = helpers.octal
  assert(S.mkdir("/tmp", "0777"))
  local data = {ta_version = 1, ta_nodes_max=1000, ta_size_max=104857600, ta_root_mode = octal("0777")}
  assert(S.mount{dir="/tmp", type="tmpfs", data=data})
  assert(S.chdir("/tmp"))
  assert(S.mkdir("/dev/pts", "0555"))
  assert(S.mount{dir="/dev/pts", type="ptyfs", data = {version = 2, gid = 0, mode = octal("0320")}})
end

local bit = require "bit"
local ffi = require "ffi"

if not (rump and abi.types == "linux") then
  local test = require("test." .. abi.os).init(S) -- OS specific tests
  for k, v in pairs(test) do _G["test_" .. k] = v end
end
if rump then
  local test = require "test.rump".init(S) -- rump specific tests
  for k, v in pairs(test) do _G["test_" .. k] = v end
end

local function fork_assert(cond, str) -- if we have forked we need to fail in main thread not fork
  if not cond then
    print(tostring(str))
    print(debug.traceback())
    os.exit(1)
  end
  return cond, str
end

local function assert_equal(...)
  collectgarbage("collect") -- force gc, to test for bugs
  return assert_equals(...)
end

USE_EXPECTED_ACTUAL_IN_ASSERT_EQUALS = true -- strict wants this to be set
local luaunit = require "include.luaunit.luaunit"

local sysfile = debug.getinfo(S.open).source
local cov = {active = {}, cov = {}}

-- TODO no longer working as more files now
local function coverage(event, line)
  local ss = debug.getinfo(2, "nLlS")
  if ss.source ~= sysfile then return end
  if event == "line" then
    cov.cov[line] = true
  elseif event == "call" then
    if ss.activelines then for k, _ in pairs(ss.activelines) do cov.active[k] = true end end
  end
end

if arg[1] == "coverage" then debug.sethook(coverage, "lc") end

local teststring = "this is a test string"
local size = 512
local buf = t.buffer(size)
local tmpfile = "XXXXYYYYZZZ4521" .. S.getpid()
local tmpfile2 = "./666666DDDDDFFFF" .. S.getpid()
local tmpfile3 = "MMMMMTTTTGGG" .. S.getpid()
local tmpdir = "FFFFGGGGHHH123" .. S.getpid()
local longdir = "1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890" .. S.getpid()
local efile = "./tmpexXXYYY" .. S.getpid() .. ".sh"
local largeval = math.pow(2, 33) -- larger than 2^32 for testing
local mqname = "ljsyscallXXYYZZ" .. S.getpid()

local clean = function()
  S.rmdir(tmpfile)
  S.unlink(tmpfile)
  S.unlink(tmpfile2)
  S.unlink(tmpfile3)
  S.rmdir(tmpdir)
  S.rmdir(longdir)
  S.unlink(efile)
end

-- type tests use reflection
local reflect = require "include.reflect.reflect"

test_types = {
  test_allocate = function() -- create an element of every ctype
    for k, v in pairs(t) do
      if type(v) == "cdata" then
        local x
        if reflect.typeof(v).vla then
          x = v(1)
        else
          x = v()
        end
      end
    end
  end,
  test_meta = function() -- read every __index metatype; unfortunately most are functions, so coverage not that useful yet
    for k, v in pairs(t) do
      if type(v) == "cdata" then
        local x
        if reflect.typeof(v).vla then
          x = v(1)
        else
          x = v()
        end
        local mt = reflect.getmetatable(x)
        if mt and type(mt.__index) == "table" then
          for kk, _ in pairs(mt.__index) do
            local r = x[kk] -- read value via metatable
            if mt.__newindex and mt.__newindex[kk] then x[kk] = r end -- write, unlikely to actually test anything
          end
        end
        if mt and mt.index then
          for kk, _ in pairs(mt.index) do
            local r = x[kk] -- read value via metatable
            if mt.newindex and mt.newindex[kk] then x[kk] = r end
          end
        end
      end
    end
  end,
}

test_basic = {
  test_b64 = function()
    local h, l = t.i6432(-1):to32()
    assert_equal(h, bit.tobit(0xffffffff))
    assert_equal(l, bit.tobit(0xffffffff))
    local h, l = t.i6432(0xfffbffff):to32()
    assert_equal(h, bit.tobit(0x0))
    assert_equal(l, bit.tobit(0xfffbffff))
  end,
  test_major_minor = function()
    local d = t.device(2, 3)
    assert_equal(d:major(), 2)
    assert_equal(d:minor(), 3)
  end,
  test_fd_nums = function() -- TODO should also test on the version from types.lua
    assert_equal(t.fd(18):nogc():getfd(), 18, "should be able to trivially create fd")
  end,
  test_error_string = function()
    local err = t.error(c.E.NOENT)
    assert(tostring(err) == "No such file or directory", "should get correct string error message")
  end,
  test_missing_error_string = function()
    local err = t.error(0)
    assert(not tostring(err), "should get missing error message")
  end,
  test_no_missing_error_strings = function()
    local allok = true
    for k, v in pairs(c.E) do
      local msg = t.error(v)
      if not msg then
        print("no error message for " .. k)
        allok = false
      end
    end
    assert(allok, "missing error message")
  end,
  test_booltoc = function()
    assert_equal(helpers.booltoc(true), 1)
    assert_equal(helpers.booltoc[true], 1)
    assert_equal(helpers.booltoc[0], 0)
  end,
  test_constants = function()
    assert_equal(c.O.CREAT, c.O.creat) -- test can use upper and lower case
    assert_equal(c.O.CREAT, c.O.Creat) -- test can use mixed case
    assert(rawget(c.O, "CREAT"))
    assert(not rawget(c.O, "creat"))
    assert(rawget(getmetatable(c.O).__index, "creat")) -- a little implementation dependent
  end,
  test_at_flags = function()
    if not c.AT_FDCWD then return end -- OSX does no support any *at functions
    assert_equal(c.AT_FDCWD[nil], c.AT_FDCWD.FDCWD) -- nil returns current dir
    assert_equal(c.AT_FDCWD.fdcwd, c.AT_FDCWD.FDCWD)
    local fd = t.fd(-1)
    assert_equal(c.AT_FDCWD[fd], -1)
    assert_equal(c.AT_FDCWD[33], 33)
  end,
  test_multiflags = function()
    assert_equal(c.O["creat, excl, rdwr"], c.O("creat", "excl", "rdwr")) -- function form takes multiple arguments
  end,
}

test_open_close = {
  teardown = clean,
  test_open_nofile = function()
    local fd, err = S.open("/tmp/file/does/not/exist", "rdonly")
    assert(err, "expected open to fail on file not found")
    assert(err.NOENT, "expect NOENT from open non existent file")
  end,
  test_close_invalid_fd = function()
    local ok, err = S.close(127)
    assert(err, "expected to fail on close invalid fd")
    assert_equal(err.errno, c.E.BADF, "expect BADF from invalid numberic fd")
  end,
  test_open_valid = function()
    local fd = assert(S.open("/dev/null", "rdonly"))
    local fd2 = assert(S.open("/dev/zero", "RDONLY"))
    assert_equal(fd2:getfd(), fd:getfd() + 1)
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
    assert(not fd, "expected to fail on close already closed fd")
    assert(err and err.badf, "expect BADF from invalid numberic fd")
  end,
  test_access = function()
    assert(S.access("/dev/null", "r"), "expect access to say can read /dev/null")
    assert(S.access("/dev/null", c.OK.R), "expect access to say can read /dev/null")
    assert(S.access("/dev/null", "w"), "expect access to say can write /dev/null")
    assert(not S.access("/dev/null", "x"), "expect access to say cannot execute /dev/null")
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
  end,
  test_umask = function() -- TODO also test effect on permissions
    local mask
    mask = S.umask("WGRP, WOTH")
    mask = S.umask("WGRP, WOTH")
    assert_equal(mask, c.MODE.WGRP + c.MODE.WOTH, "umask not set correctly")
  end,
}

test_read_write = {
  teardown = clean,
  test_read = function()
    local fd = assert(S.open("/dev/zero"))
    for i = 0, size - 1 do buf[i] = 255 end
    local n = assert(fd:read(buf, size))
    assert(n >= 0, "should not get error reading from /dev/zero")
    assert_equal(n, size)
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
    if not features.preadv() then return true end
    local offset = 0
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

test_poll_select = {
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
}

test_address_names = {
  test_ipv4_names = function()
    assert_equal(tostring(t.in_addr("127.0.0.1")), "127.0.0.1")
    assert_equal(tostring(t.in_addr("loopback")), "127.0.0.1")
    assert_equal(tostring(t.in_addr("1.2.3.4")), "1.2.3.4")
    assert_equal(tostring(t.in_addr("255.255.255.255")), "255.255.255.255")
    assert_equal(tostring(t.in_addr("broadcast")), "255.255.255.255")
  end,
  test_ipv6_names = function()
    local sa = assert(t.sockaddr_in6(1234, "2002::4:5"))
    assert_equal(sa.port, 1234, "want same port back")
    assert_equal(tostring(sa.sin6_addr), "2002::4:5", "expect same address back")
    local sa = assert(t.sockaddr_in6(1234, "loopback"))
    assert_equal(sa.port, 1234, "want same port back")
    assert_equal(tostring(sa.sin6_addr), "::1", "expect same address back")
  end,
  test_inet_name = function()
    local addr = t.in_addr("127.0.0.1")
    assert(addr, "expect to get valid address")
    assert_equal(tostring(addr), "127.0.0.1")
  end,
  test_inet_name6 = function()
    for _, a in ipairs {"::1", "::2:0:0:0", "0:0:0:2::", "1::"} do
      local addr = t.in6_addr(a)
      assert(addr, "expect to get valid address")
      assert_equal(tostring(addr), a)
    end
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
    local fd = assert(S.creat(tmpfile, "0755"))
    assert(S.link(tmpfile, tmpfile2))
    assert(S.unlink(tmpfile2))
    assert(S.unlink(tmpfile))
    assert(fd:close())
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
  test_sync = function()
    S.sync() -- cannot fail...
  end,
  test_fchmod = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(fd:fchmod("RUSR, WUSR"))
    local st = fd:stat()
    assert_equal(bit.band(st.mode, c.S_I["RUSR, WUSR"]), c.S_I["RUSR, WUSR"])
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
  test_sync = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(fd:fsync())
    assert(fd:fdatasync())
    assert(fd:sync()) -- synonym
    assert(fd:datasync()) -- synonym
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
    assert(S.mkdir(tmpdir, "RWXU"))
    assert(S.rmdir(tmpdir))
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
    local cwd2 = cwd
    if cwd2 == "/" then cwd2 = "" end
    assert(S.mkdir(longdir, "RWXU"))
    assert(S.chdir(longdir))
    local nd = assert(S.getcwd())
    assert_equal(nd, cwd2 .. "/" .. longdir, "expect to get filename plus cwd")
    assert(S.chdir(cwd))
    assert(S.rmdir(longdir))
  end,
  test_rename = function()
    local fd = assert(S.creat(tmpfile, "rwxu"))
    assert(fd:close())
    assert(S.rename(tmpfile, tmpfile2))
    assert(not S.stat(tmpfile))
    assert(S.stat(tmpfile2))
    assert(S.unlink(tmpfile2))
  end,
  test_stat_device = function()
    local stat = assert(S.stat("/dev/zero"))
    assert_equal(stat.nlink, 1, "expect link count on /dev/zero to be 1")
    assert(stat.ischr, "expect /dev/zero to be a character device")
  end,
  test_stat_file = function()
    local fd = assert(S.creat(tmpfile, "rwxu"))
    assert(fd:write("four"))
    assert(fd:close())
    local stat = assert(S.stat(tmpfile))
    assert_equal(stat.size, 4, "expect size 4")
    assert(stat.isreg, "regular file")
    assert(S.unlink(tmpfile))
  end,
  test_stat_directory = function()
    local fd = assert(S.open("/"))
    local stat = assert(fd:stat())
    assert(stat.isdir, "expect / to be a directory")
    assert(fd:close())
  end,
  test_stat_symlink = function()
    local fd = assert(S.creat(tmpfile2, "rwxu"))
    assert(fd:close())
    assert(S.symlink(tmpfile2, tmpfile))
    local stat = assert(S.stat(tmpfile))
    assert(stat.isreg, "expect file to be a regular file")
    assert(not stat.islnk, "should not be symlink")
    assert(S.unlink(tmpfile))
    assert(S.unlink(tmpfile2))
  end,
  test_lstat_symlink = function()
    local fd = assert(S.creat(tmpfile2, "rwxu"))
    assert(fd:close())
    assert(S.symlink(tmpfile2, tmpfile))
    local stat = assert(S.lstat(tmpfile))
    assert(stat.islnk, "expect lstat to stat the symlink")
    assert(not stat.isreg, "lstat should find symlink not regular file")
    assert(S.unlink(tmpfile))
    assert(S.unlink(tmpfile2))
  end,
  test_truncate = function()
    local fd = assert(S.creat(tmpfile, "rwxu"))
    assert(fd:write(teststring))
    assert(fd:close())
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
  test_mknod_chr_root = function()
    assert(S.mknod(tmpfile, "fchr,0666", t.device(1, 5)))
    local stat = assert(S.stat(tmpfile))
    assert(stat.ischr, "expect to be a character device")
    assert_equal(stat.rdev:major(), 1 , "expect major number to be 1")
    assert_equal(stat.rdev:minor(), 5, "expect minor number to be 5")
    assert_equal(stat.rdev, t.device(1, 5), "expect raw device to be makedev(1, 5)")
    assert(S.unlink(tmpfile))
  end,
  test_mkfifo = function()
    assert(S.mkfifo(tmpfile, "rwxu"))
    local stat = assert(S.stat(tmpfile))
    assert(stat.isfifo, "expect to be a fifo")
    assert(S.unlink(tmpfile))
  end,
  test_futimens = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(fd:futimens())
    local st1 = fd:stat()
    assert(fd:futimens{"omit", "omit"})
    local st2 = fd:stat()
    assert_equal(st1.atime, st2.atime)
    assert_equal(st1.mtime, st2.mtime)
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_futimes = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    local st1 = fd:stat()
    assert(fd:futimes{100, 200})
    local st2 = fd:stat()
    assert(st1.atime ~= st2.atime and st1.mtime ~= st2.mtime, "atime and mtime changed")
    assert_equal(st2.atime, 100)
    assert_equal(st2.mtime, 200)
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_utime = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    local st1 = fd:stat()
    assert(S.utime(tmpfile, 100, 200))
    local st2 = fd:stat()
    assert(st1.atime ~= st2.atime and st1.mtime ~= st2.mtime, "atime and mtime changed")
    assert_equal(st2.atime, 100)
    assert_equal(st2.mtime, 200)
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_utimes = function()
    assert(util.touch(tmpfile))
    local st1 = S.stat(tmpfile)
    assert(S.utimes(tmpfile, {100, 200}))
    local st2 = S.stat(tmpfile)
    assert(st1.atime ~= st2.atime and st1.mtime ~= st2.mtime, "atime and mtime changed")
    assert_equal(st2.atime, 100)
    assert_equal(st2.mtime, 200)
    assert(S.unlink(tmpfile))
  end,
  test_lutimes = function()
    assert(S.symlink("/no/such/file", tmpfile))
    local st1 = S.lstat(tmpfile)
    assert(S.lutimes(tmpfile, {100, 200}))
    local st2 = S.lstat(tmpfile)
    assert(st1.atime ~= st2.atime and st1.mtime ~= st2.mtime, "atime and mtime changed")
    assert_equal(st2.atime, 100)
    assert_equal(st2.mtime, 200)
    assert(S.unlink(tmpfile))
  end,
}

test_directory_operations = {
  teardown = clean,
  test_getdents_dev = function()
    local d = {}
    for fn, f in util.ls("/dev") do
      d[fn] = true
      if fn == "zero" then assert(f.CHR, "/dev/zero is a character device") end
      if fn == "." then
        assert(f.DIR, ". is a directory")
        assert(not f.CHR, ". is not a character device")
        assert(not f.SOCK, ". is not a socket")
        assert(not f.LNK, ". is not a symlink")
      end
      if fn == ".." then assert(f.DIR, ".. is a directory") end
    end
    assert(d.zero, "expect to find /dev/zero")
  end,
  test_getdents_error = function()
    local fd = assert(S.open("/dev/zero", "RDONLY"))
    local d, err = S.getdents(fd)
    assert(err, "getdents should fail on /dev/zero")
    assert(fd:close())
  end,
  test_getdents = function()
    assert(S.mkdir(tmpdir, "rwxu"))
    assert(util.touch(tmpdir .. "/file1"))
    assert(util.touch(tmpdir .. "/file2"))
    -- with only two files will get in one iteration of getdents
    local fd = assert(S.open(tmpdir, "directory, rdonly"))
    local f, count = {}, 0
    for d in fd:getdents() do
      f[d.name] = true
      count = count + 1
    end
    assert_equal(count, 4)
    assert(f.file1 and f.file2 and f["."] and f[".."], "expect four files")
    assert(fd:close())
    assert(S.unlink(tmpdir .. "/file1"))
    assert(S.unlink(tmpdir .. "/file2"))
    assert(S.rmdir(tmpdir))
  end,
  test_dents_stat_conversion = function()
    local st = assert(S.stat("/dev/zero"))
    assert(st.ischr, "/dev/zero is a character device")
    for fn, f in util.ls("/dev") do
      if fn == "zero" then
        assert(f.CHR, "/dev/zero is a character device")
        assert_equal(st.todt, f.type)
        assert_equal(f.toif, st.type)
        assert_equal(st.todt, c.DT.CHR)
        assert_equal(f.toif, c.S_I.FCHR)
      end
    end
  end,
  test_ls = function()
    assert(S.mkdir(tmpdir, "rwxu"))
    assert(util.touch(tmpdir .. "/file1"))
    assert(util.touch(tmpdir .. "/file2"))
    local f, count = {}, 0
    for d in util.ls(tmpdir) do
      f[d] = true
      count = count + 1
    end
    assert_equal(count, 4)
    assert(f.file1 and f.file2 and f["."] and f[".."], "expect four files")
    assert(S.unlink(tmpdir .. "/file1"))
    assert(S.unlink(tmpdir .. "/file2"))
    assert(S.rmdir(tmpdir))
  end,
  test_ls_long = function()
    assert(S.mkdir(tmpdir, "rwxu"))
    local num = 300 -- sufficient to need more than one getdents call
    for i = 1, num do assert(util.touch(tmpdir .. "/file" .. i)) end
    local f, count = {}, 0
    for d in util.ls(tmpdir) do
      f[d] = true
      count = count + 1
    end
    assert_equal(count, num + 2)
    for i = 1, num do assert(f["file" .. i]) end
    for i = 1, num do assert(S.unlink(tmpdir .. "/file" .. i)) end
    assert(S.rmdir(tmpdir))
  end,
  test_dirtable = function()
    assert(S.mkdir(tmpdir, "0777"))
    assert(util.touch(tmpdir .. "/file"))
    local list = assert(util.dirtable(tmpdir, true))
    assert_equal(#list, 1, "one item in directory")
    assert_equal(list[1], "file", "one file called file")
    assert_equal(tostring(list), "file\n")
    assert(S.unlink(tmpdir .. "/file"))
    assert(S.rmdir(tmpdir))
  end,
}

test_largefile = {
  test_seek = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    local off = t.off(2^34)
    local offset = 2^34 -- should work with Lua numbers up to 56 bits, above that need explicit 64 bit type.
    local n
    n = assert(fd:lseek(off, "set"))
    assert_equal(n, off, "seek should position at set position")
    n = assert(fd:lseek(off, "cur"))
    assert_equal(n, off + off, "seek should position at set position")
    n = assert(fd:lseek(offset, "set"))
    assert_equal(n, offset, "seek should position at set position")
    n = assert(fd:lseek(offset, "cur"))
    assert_equal(n, offset + offset, "seek should position at set position")
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_ftruncate = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    local offset = largeval
    assert(fd:truncate(offset))
    local st = assert(fd:stat())
    assert_equal(st.size, offset)
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_truncate = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    local offset = largeval
    assert(S.truncate(tmpfile, offset))
    local st = assert(S.stat(tmpfile))
    assert_equal(st.size, offset)
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_preadv_pwritev = function()
    if not features.preadv() then return true end
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

test_sockets_pipes = {
  test_sockaddr_storage = function()
    local sa = t.sockaddr_storage{family = "inet6", port = 2}
    assert_equal(sa.family, c.AF.INET6, "inet6 family")
    assert_equal(sa.port, 2, "should get port back")
    sa.port = 3
    assert_equal(sa.port, 3, "should get port back")
    sa.family = "inet"
    assert_equal(sa.family, c.AF.INET, "inet family")
    sa.port = 4
    assert_equal(sa.port, 4, "should get port back")
  end,
  test_pipe = function()
    local p = assert(S.pipe())
    assert(p:write("test"))
    assert_equal(p:read(), "test")
    assert(p:close())
  end,
  test_pipe_nonblock = function()
    if rump and S.abi.types == "linux" then print("skipping test as blocks"); return end
    local fds = assert(S.pipe())
    assert(fds:nonblock())
    local r, err = fds:read()
    assert(err.AGAIN, "expect AGAIN")
    assert(fds:close())
  end,
  test_sockaddr_in_error = function()
    local sa = t.sockaddr_in(1234, "error")
    assert(not sa, "expect nil socket address from invalid ip string")
  end,
  test_inet_socket = function() -- TODO break this test up
    local s = assert(S.socket("inet", "stream"))
    assert(s:nonblock())
    local sa = assert(t.sockaddr_in(1234, "loopback"))
    assert(sa.sin_family == 2, "expect family on inet socket to be 2")
    -- find a free port
    local bound = false
    for port = 32768, 60000 do
      sa.port = port
      if s:bind(sa) then
        bound = true
        break
      end
    end
    assert(bound, "should be able to bind to a port")
    local ba = assert(s:getsockname())
    assert_equal(ba.sin_family, 2, "expect family on getsockname to be 2")
    assert(s:listen()) -- will fail if we did not bind
    local c = assert(S.socket("inet", "stream")) -- client socket
    assert(c:block())
    assert(c:fcntl("setfd", "cloexec"))
    local ok, err = c:connect(sa)
    local a = assert(s:accept())
    assert(a.fd:block())
    local ok, err = c:connect(sa) -- Linux will have returned INPROGRESS above, other OS may have connected
    assert(s:block()) -- force accept to wait
    a = a or assert(s:accept())
    -- a is a table with the fd, but also the inbound connection details
    assert(a.addr.sin_family == 2, "expect ipv4 connection")
    local ba = assert(c:getpeername())
    assert(ba.sin_family == 2, "expect ipv4 connection")
    assert(tostring(ba.sin_addr) == "127.0.0.1", "expect peer on localhost")
    assert(ba.sin_addr.s_addr == t.in_addr("loopback").s_addr, "expect peer on localhost")
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
    assert(c:close())
    assert(a.fd:close())
    assert(s:close())
  end,
  test_unix_socketpair = function()
    local sv = assert(S.socketpair("unix", "stream"))
    assert(sv[1]:write("test"))
    local r = assert(sv[2]:read())
    assert_equal(r, "test")
    assert(sv:close())
  end,
  test_udp_socket = function()
    local ss = assert(S.socket("inet", "dgram"))
    local cs = assert(S.socket("inet", "dgram"))
    local sa = assert(t.sockaddr_in(0, "loopback"))
    assert(ss:bind(sa))
    local bsa = ss:getsockname() -- find bound address
    local n = assert(cs:sendto(teststring, #teststring, 0, bsa))
    local f = assert(ss:recv(buf, size))
    assert_equal(f, #teststring)
    assert(ss:close())
    assert(cs:close())
  end,
  test_ipv6_socket = function()
    if not features.ipv6() then return true end -- TODO rump temporarily failing for ipv6, need to init lo0
    local loop6 = "::1"
    local ss = assert(S.socket("inet6", "dgram"))
    local cs = assert(S.socket("inet6", "dgram"))
    local sa = assert(t.sockaddr_in6(0, loop6))
    assert(ss:bind(sa))
    local bsa = ss:getsockname() -- find bound address
    local n = assert(cs:sendto(teststring, nil, 0, bsa))
    local f = assert(ss:recv(buf, size))
    assert_equal(f, #teststring)
    assert(cs:close())
    assert(ss:close())
  end,
  test_recvfrom = function()
    local ss = assert(S.socket("inet", "dgram"))
    local cs = assert(S.socket("inet", "dgram"))
    local sa = assert(t.sockaddr_in(0, "loopback"))
    assert(ss:bind(sa))
    assert(cs:bind(sa))
    local bsa = ss:getsockname()
    local csa = cs:getsockname()
    local n = assert(cs:sendto(teststring, #teststring, 0, bsa))
    local rsa = t.sockaddr_in()
    local f = assert(ss:recvfrom(buf, size, "", rsa))
    assert_equal(f, #teststring)
    assert_equal(rsa.port, csa.port)
    assert_equal(tostring(rsa.addr), "127.0.0.1")
    assert(ss:close())
    assert(cs:close())
  end,
}

test_timers = {
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
  test_flock = function()
    local fd = assert(S.open(tmpfile, "creat, rdwr", "RWXU"))
    assert(fd:flock("sh, nb"))
    assert(fd:flock("ex"))
    assert(fd:flock("un"))
    assert(fd:close())
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
    local ok, err = pts:tcgetsid()
    assert(not ok, "should not get sid as noctty")
    local termios = assert(pts:tcgetattr())
    assert(termios.ospeed ~= 115200)
    termios.speed = 115200
    assert_equal(termios.ispeed, 115200)
    assert_equal(termios.ospeed, 115200)
    assert(bit.band(termios.c_lflag, c.LFLAG.ICANON) ~= 0)
    termios:makeraw()
    assert(bit.band(termios.c_lflag, c.LFLAG.ICANON) == 0)
    assert(pts:tcsetattr("now", termios))
    termios = assert(pts:tcgetattr())
    assert_equal(termios.ospeed, 115200)
    assert(bit.band(termios.c_lflag, c.LFLAG.ICANON) == 0)
    local ok, err = pts:tcsendbreak(0) -- as this is not actually a serial line, NetBSD seems to fail here
    assert(pts:tcdrain())
    assert(pts:tcflush('ioflush'))
    assert(pts:tcflow('ooff'))
    --assert(pts:tcflow('ioff')) -- blocking in NetBSD
    assert(pts:tcflow('oon'))
    --assert(pts:tcflow('ion')) -- blocking in NetBSD
    assert(pts:close())
    assert(ptm:close())
  end,
  test_isatty_fail = function()
    local fd = S.open("/dev/zero")
    assert(not fd:isatty(), "not a tty")
    assert(fd:close())
  end,
}

test_misc = {
  test_chroot_root = function()
    assert(S.chroot("/"))
  end,
  test_pathconf = function()
    local pc = assert(S.pathconf(".", "name_max"))
    assert(pc >= 255, "name max should be at least 255")
  end,
  test_fpathconf = function()
    local fd = assert(S.open(".", "rdonly"))
    local pc = assert(fd:pathconf("name_max"))
    assert(pc >= 255, "name max should be at least 255")
    assert(fd:close())
  end,
}

test_raw_socket = {
  test_ip_checksum = function()
    local packet = {0x45, 0x00,
      0x00, 0x73, 0x00, 0x00,
      0x40, 0x00, 0x40, 0x11,
      0xb8, 0x61, 0xc0, 0xa8, 0x00, 0x01,
      0xc0, 0xa8, 0x00, 0xc7}

    local expected = 0x61B8 -- note reversed from example at https://en.wikipedia.org/wiki/IPv4_header_checksum#Example:_Calculating_a_checksum due to byte order issue

    local buf = t.buffer(#packet, packet)
    local iphdr = pt.iphdr(buf)
    iphdr[0].check = 0
    local cs = iphdr[0]:checksum()
    assert(cs == expected, "expect correct ip checksum: " .. string.format("%%%04X", cs) .. " " .. string.format("%%%04X", expected))
  end,
  test_raw_udp_root = function() -- TODO create some helper functions, this is not very nice

    local h = require "syscall.helpers" -- TODO should not have to use later

    local loop = "127.0.0.1"
    local raw = assert(S.socket("inet", "raw", "raw"))
    -- needed if not on Linux
    assert(raw:setsockopt(c.IPPROTO.IP, c.IP.HDRINCL, 1)) -- TODO new sockopt code should be able to cope
    local msg = "raw message."
    local udplen = s.udphdr + #msg
    local len = s.iphdr + udplen
    local buf = t.buffer(len)
    local iphdr = pt.iphdr(buf)
    local udphdr = pt.udphdr(buf + s.iphdr)
    ffi.copy(buf + s.iphdr + s.udphdr, msg, #msg)
    local bound = false
    local sport = 666
    local sa = t.sockaddr_in(sport, loop)

    local buf2 = t.buffer(#msg)

    local cl = assert(S.socket("inet", "dgram")) -- destination
    local ca = t.sockaddr_in(0, loop)
    assert(cl:bind(ca))
    local ca = cl:getsockname()

    -- TODO iphdr should have __index helpers for endianness etc (note use raw s_addr)
    iphdr[0] = {ihl = 5, version = 4, tos = 0, id = 0, frag_off = h.htons(0x4000), ttl = 64, protocol = c.IPPROTO.UDP, check = 0,
             saddr = sa.sin_addr.s_addr, daddr = ca.sin_addr.s_addr, tot_len = h.htons(len)}

    --udphdr[0] = {src = sport, dst = ca.port, length = udplen} -- doesnt work with metamethods
    udphdr[0].src = sport
    udphdr[0].length = udplen

    udphdr[0].dst = ca.port
    -- we do not need to calulate checksum, can leave as zero (for Linux at least)
    --udphdr[0]:checksum(iphdr[0], buf + s.iphdr + s.udphdr)
    iphdr[0].check = 0

    -- TODO in FreeBSD, NetBSD len is in host byte order not net, see Stephens, http://developerweb.net/viewtopic.php?id=4657
    -- TODO the metamethods should take care of this
    if abi.os == "netbsd" then iphdr[0].tot_len = len end

    ca.port = 0 -- should not set port

    local n = assert(raw:sendto(buf, len, 0, ca))

    -- TODO receive issues on netBSD 
    if abi.os ~= "netbsd" then
      local f = assert(cl:recvfrom(buf2, #msg))
      assert_equal(f, #msg)
    end
    assert(raw:close())
    assert(cl:close())
  end,
}

if not abi.rump then -- rump has no processes, memory allocation so not applicable
test_mmap = {
  test_mmap_fail = function()
    local size = 4096
    local mem, err = S.mmap(pt.void(1), size, "read", "private, fixed, anonymous", -1, 0)
    assert(err, "expect non aligned fixed map to fail")
    assert(err.INVAL, "expect non aligned map to return EINVAL")
  end,
  test_mmap_anon = function()
    local size = 4096
    local mem = assert(S.mmap(nil, size, "read", "private, anonymous", -1, 0))
    assert(S.munmap(mem, size))
  end,
  test_mmap_file = function()
    local fd = assert(S.open(tmpfile, "rdwr,creat", "rwxu"))
    assert(S.unlink(tmpfile))
    local size = 4096
    local mem = assert(fd:mmap(nil, size, "read", "shared", 0))
    assert(S.munmap(mem, size))
    assert(fd:close())
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
  test_mlock = function()
    local size = 4096
    local mem = assert(S.mmap(nil, size, "read", "private, anonymous", -1, 0))
    assert(S.mlock(mem, size))
    assert(S.munlock(mem, size))
    assert(S.munmap(mem, size))
  end,
  test_mlockall = function()
    local ok, err = S.mlockall("current")
    assert(ok or err.nomem, "expect mlockall to succeed, or fail due to rlimit")
    assert(S.munlockall())
  end,
}
end

if S.environ then -- use this as a proxy for whether libc functions defined (eg not defined in rump)
test_libc = {
  test_environ = function()
    local e = S.environ()
    assert(e.PATH, "expect PATH to be set in environment")
    assert(S.setenv("XXXXYYYYZZZZZZZZ", "test"))
    assert(S.environ().XXXXYYYYZZZZZZZZ == "test", "expect to be able to set env vars")
    assert(S.unsetenv("XXXXYYYYZZZZZZZZ"))
    assert(not S.environ().XXXXYYYYZZZZZZZZ, "expect to be able to unset env vars")
  end,
}
end

local function removeroottests()
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

-- basically largefile on NetBSD is always going to work but tests may not use sparse files so run out of memory
if rump then
  test_largefile = nil
end

-- note at present we check for uid 0, but could check capabilities instead.
if S.geteuid() == 0 then
  if abi.os == "linux" then
    -- cut out this section if you want to (careful!) debug on real interfaces
    -- TODO add to features as may not be supported
    local ok, err = S.unshare("newnet, newns, newuts")
    if not ok then removeroottests() -- remove if you like, but may interfere with networking
    else
      local nl = S.nl
      local i = assert(nl.interfaces())
      local lo = assert(i.lo)
      assert(lo:up())
      assert(S.mount("none", "/sys", "sysfs"))
    end
  else -- not Linux
    -- run all tests, no namespaces available
  end
else -- remove tests that need root
  removeroottests()
end

local f
if arg[1] and arg[1] ~= "coverage" then f = luaunit:run(arg[1]) else f = luaunit:run() end

clean()

debug.sethook()

if f ~= 0 then
  os.exit(1)
end

-- TODO iterate through all functions in S and upvalues for active rather than trace
-- also check for non interesting cases, eg fall through to end
-- TODO this is not working any more, FIXME

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

os.exit(0)



