-- test suite for ljsyscall.

-- TODO stop using globals for tests

arg = arg or {}

local strict = require "test.strict"

local helpers = require "test.helpers"

local assert = helpers.assert

local S
local tmpabi
local short

if arg[1] == "rumplinuxshort" then short, arg[1] = true, "rumplinux" end -- don't run Linux tests

if arg[1] == "rump" or arg[1] == "rumplinux" then
  tmpabi = require "syscall.abi"
  if arg[1] == "rumplinux" then
    tmpabi.types = "linux" -- monkeypatch
  end
  local modules = {"kern.tty", "dev", "net", "fs.tmpfs", "fs.kernfs", "fs.ptyfs",
                   "net.net", "net.local", "net.netinet", "net.netinet6", "vfs"}
  S = require "syscall.rump.init".init(modules)
  table.remove(arg, 1)
else
  S = require "syscall"
end

local abi = S.abi
local types = S.types
local t, pt, s = types.t, types.pt, types.s
local c = S.c
local util = S.util

if S.__rump and abi.types == "linux" then -- Linux rump ABI cannot do much, so switch from root so it does not try
  assert(S.rump.newlwp(S.getpid()))
  assert(S.chmod("/", "0777"))
  assert(S.chmod("/dev/zero", "0666"))
  local lwp1 = assert(S.rump.curlwp())
  assert(S.rump.rfork("CFDG"))
  S.rump.i_know_what_i_am_doing_sysent_usenative() -- switch to netBSD syscalls in this thread
  local data = t.tmpfs_args{ta_version = 1, ta_nodes_max=1000, ta_size_max=104857600, ta_root_mode = helpers.octal("0777")}
  assert(S.mount("tmpfs", "/tmp", 0, data, s.tmpfs_args))
  assert(S.mkdir("/dev/pts", "0555"))
  local data = t.ptyfs_args{version = 2, gid = 0, mode = helpers.octal("0555")}
  assert(S.mount("ptyfs", "/dev/pts", 0, data, s.ptyfs_args))
  S.rump.switchlwp(lwp1)
  local ok, err = S.mount("tmpfs", "/tmp", 0, data, s.tmpfs_args)
  assert(err, "mount should fail as not in NetBSD compat now")
  assert(S.chdir("/tmp"))
  -- TODO can run as non root
  --assert(S.rump.rfork("CFDG"))
  --assert(S.setuid(100))
  --assert(S.seteuid(100))
elseif (S.__rump or abi.xen) and S.geteuid() == 0 then -- some initial setup for non-Linux rump
  assert(S.rump.newlwp(S.getpid()))
  local octal = helpers.octal
  local data = {ta_version = 1, ta_nodes_max=1000, ta_size_max=104857600, ta_root_mode = octal("0777")}
  assert(S.mount("tmpfs", "/tmp", 0, data))
  assert(S.chdir("/tmp"))
  assert(S.mkdir("/dev/pts", "0555"))
  assert(S.mount("ptyfs", "/dev/pts", 0, {version = 2, gid = 0, mode = octal("0320")}))
end

local bit = require "syscall.bit"
local ffi = require "ffi"

if not S.__rump then
  local test = require("test." .. abi.os).init(S) -- OS specific tests
  for k, v in pairs(test) do _G["test_" .. k] = v end
  if abi.bsd then
    local test = require("test.bsd").init(S) -- BSD tests
    for k, v in pairs(test) do _G["test_" .. k] = v end
  end
end
if S.__rump then
  if abi.types == "linux" and not short then -- add linux tests unless running short tests
    local test = require("test.linux").init(S) -- OS specific tests
    for k, v in pairs(test) do _G["test_" .. k] = v end
  elseif abi.types == "netbsd" then
    local test = require("test.netbsd").init(S) -- OS specific tests
    for k, v in pairs(test) do _G["test_" .. k] = v end
    local test = require("test.bsd").init(S) -- BSD tests
    for k, v in pairs(test) do _G["test_" .. k] = v end
  end
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
local luaunit = require "test.luaunit"

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

-- TODO make locals in each test
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

-- type tests use reflection TODO move to seperate test file
local ok, reflect = nil, nil
if not ffi.abi("64bit") or "x64" == ffi.arch then -- ffi-reflect does not support the new 64bit abi (LuaJIT's LJ_GC64 mode)
  ok, reflect = pcall(require, "include.ffi-reflect.reflect")
end
if ok then
test_types_reflect = {
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
            if mt.__newindex and type(mt.__newindex) == "table" and mt.__newindex[kk] then x[kk] = r end -- write, unlikely to actually test anything
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
  test_invalid_index_newindex = function()
    local function index(x, k) return x[k] end
    local function newindex(x, k) x[k] = x[k] end -- dont know type so assign to self
    local badindex = "_____this_index_is_not_found"
    local allok = true
    for k, v in pairs(t) do
      if type(v) == "cdata" then
        local x
        if reflect.typeof(v).vla then
          x = v(1)
        else
          x = v()
        end
        local mt = reflect.getmetatable(x)
        if mt then
          local ok, err = pcall(index, x, badindex)
          if ok then print("index error on " .. k); allok = false end
          local ok, err = pcall(newindex, x, badindex)
          if ok then print("newindex error on " .. k); allok = false end
        end
      end
    end
    assert_equal(allok, true)
  end,
  test_length = function()
    local nolen = {fd = true, error = true, mqd = true, timer = true} -- internal use
    local function len(x) return #x end
    local allok = true
    for k, v in pairs(t) do
      if type(v) == "cdata" then
        if not reflect.typeof(v).vla then
          local x = v()
          local mt = reflect.getmetatable(x)
          local ok, err = pcall(len, x)
          if mt and not ok and not nolen[k] then
            print("no len on " .. k)
            allok = false
            end
        end
      end
    end
    assert_equal(allok, true)
  end,
  test_tostring = function()
    for k, v in pairs(t) do
      if type(v) == "cdata" then
        local x, s
        if reflect.typeof(v).vla then
          x = v(1)
          s = tostring(v)
        else
          x = v()
          s = tostring(v)
        end
      end
    end
  end,
}
end

test_basic = {
  test_b64 = function()
    local h, l = bit.i6432(-1)
    assert_equal(h, bit.tobit(0xffffffff))
    assert_equal(l, bit.tobit(0xffffffff))
    local h, l = bit.i6432(0xfffbffff)
    assert_equal(h, bit.tobit(0x0))
    assert_equal(l, bit.tobit(0xfffbffff))
  end,
  test_bor64 = function()
    local a, b = t.int64(0x10ffff0000), t.int64(0x020000ffff)
    assert_equal(tonumber(bit.bor64(a, b)), 0x12ffffffff)
    assert_equal(tonumber(bit.bor64(a, b, a, b)), 0x12ffffffff)
  end,
  test_band64 = function()
    local a, b = t.int64(0x12ffffffff), t.int64(0x020000ffff)
    assert_equal(tonumber(bit.band64(a, b)), 0x020000ffff)
    assert_equal(tonumber(bit.band64(a, b, a, b)), 0x020000ffff)
  end,
  test_lshift64 = function()
    assert_equal(tonumber(bit.lshift64(1, 0)), 1)
    assert_equal(tonumber(bit.lshift64(1, 1)), 2)
    assert_equal(tonumber(bit.lshift64(0xffffffff, 4)), 0xffffffff0)
    assert_equal(tonumber(bit.lshift64(0xffffffff, 8)), 0xffffffff00)
    assert_equal(tonumber(bit.lshift64(1, 32)), 0x100000000)
    assert_equal(tonumber(bit.lshift64(1, 36)), 0x1000000000)
  end,
  test_rshift64 = function()
    assert_equal(tonumber(bit.rshift64(1, 0)), 1)
    assert_equal(tonumber(bit.rshift64(2, 1)), 1)
    assert_equal(tonumber(bit.rshift64(0xffffffff0, 4)), 0xffffffff)
    assert_equal(tonumber(bit.rshift64(0xffffffff00, 8)), 0xffffffff)
    assert_equal(tonumber(bit.rshift64(0x100000000, 32)), 1)
    assert_equal(tonumber(bit.rshift64(0x1000000000, 36)), 1)
  end,
  test_major_minor = function()
    local d = t.device(2, 3)
    assert_equal(d.major, 2)
    assert_equal(d.minor, 3)
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
  test_multiflags_negation = function()
    assert_equal(c.O("creat", "~creat"), 0) -- negating flag should clear
    assert_equal(c.O("creat, excl", "~creat", "rdwr", "~rdwr"), c.O.EXCL)
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
    local size = 64
    local buf = t.buffer(size)
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
    if not S.preadv then error "skipped" end
    local offset = 10
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
    local a, b = assert(S.socketpair("unix", "stream"))
    local pev = t.pollfds{{fd = a, events = "in"}}
    local p = assert(S.poll(pev, 0))
    assert_equal(p, 0) -- no events
    for k, v in ipairs(pev) do
      assert_equal(v.fd, a:getfd())
      assert_equal(v.revents, 0)
    end
    assert(b:write(teststring))
    local p = assert(S.poll(pev, 0))
    assert_equal(p, 1) -- 1 event
    for k, v in ipairs(pev) do
      assert_equal(v.fd, a:getfd())
      assert(v.IN, "one IN event now")
    end
    assert(a:read())
    assert(b:close())
    assert(a:close())
  end,
  test_select = function()
    local a, b = assert(S.socketpair("unix", "stream"))
    local sel = assert(S.select({readfds = {a, b}}, 0))
    assert_equal(sel.count, 0)
    assert(b:write(teststring))
    sel = assert(S.select({readfds = {a, b}}, 0))
    assert_equal(sel.count, 1)
    assert(b:close())
    assert(a:close())
  end,
  test_pselect = function()
    local a, b = assert(S.socketpair("unix", "stream"))
    local sel = assert(S.pselect({readfds = {a, b}}, 0, "alrm"))
    assert_equal(sel.count, 0)
    assert(b:write(teststring))
    sel = assert(S.pselect({readfds = {a, b}}, 0, "alrm"))
    assert_equal(sel.count, 1)
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
  test_util_netmask_broadcast = function()
    local addr = t.in_addr("0.0.0.0")
    local nb = addr:get_mask_bcast(32)
    assert_equal(tostring(nb.broadcast), "0.0.0.0")
    assert_equal(tostring(nb.netmask), "0.0.0.0")
    local addr = t.in_addr("10.10.20.1")
    local nb = addr:get_mask_bcast(24)
    assert_equal(tostring(nb.broadcast), "10.10.20.255")
    assert_equal(tostring(nb.netmask), "0.0.0.255")
    local addr = t.in_addr("0.0.0.0")
    local nb = addr:get_mask_bcast(0)
    assert_equal(tostring(nb.broadcast), "255.255.255.255")
    assert_equal(tostring(nb.netmask), "255.255.255.255")
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
  test_dup2 = function()
    if not S.dup2 then error "skipped" end
    local fd = assert(S.open("/dev/zero"))
    local fd2 = assert(fd:dup2(17))
    assert_equal(fd2:getfd(), 17, "dup2 should set file id as specified")
    assert(fd2:close())
    assert(fd:close())
  end,
  test_dup3 = function()
    if not S.dup3 then error "skipped" end
    local fd = assert(S.open("/dev/zero"))
    local fd2 = assert(fd:dup3(17))
    assert_equal(fd2:getfd(), 17, "dup3 should set file id as specified")
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
  test_syncfs = function()
    if not S.syncfs then error "skipped" end
    local fd = S.open("/dev/null")
    assert(fd:syncfs())
    assert(fd:close())
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
  test_fsync = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(fd:fsync())
    assert(fd:sync()) -- synonym
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_fdatasync = function()
    if not S.fdatasync then error "skipped" end
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(fd:fdatasync())
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
    assert_equal(stat.typename, "char device")
  end,
  test_stat_file = function()
    local fd = assert(S.creat(tmpfile, "rwxu"))
    assert(fd:write("four"))
    assert(fd:close())
    local stat = assert(S.stat(tmpfile))
    assert_equal(stat.size, 4, "expect size 4")
    assert(stat.isreg, "regular file")
    assert_equal(stat.typename, "file")
    assert(S.unlink(tmpfile))
  end,
  test_stat_directory = function()
    local fd = assert(S.open("/"))
    local stat = assert(fd:stat())
    assert(stat.isdir, "expect / to be a directory")
    assert_equal(stat.typename, "directory")
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
  test_stat_aliases = function()
    local st = S.stat(".")
    assert(st.access)
    assert(st.modification)
    assert(st.change)
    assert_equal(st.typename, "directory")
  end,
  test_lstat_symlink = function()
    local fd = assert(S.creat(tmpfile2, "rwxu"))
    assert(fd:close())
    assert(S.symlink(tmpfile2, tmpfile))
    local stat = assert(S.lstat(tmpfile))
    assert(stat.islnk, "expect lstat to stat the symlink")
    assert_equal(stat.typename, "link")
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
    assert(S.mknod(tmpfile, "fchr,0666", {1, 5}))
    local stat = assert(S.stat(tmpfile))
    assert(stat.ischr, "expect to be a character device")
    assert_equal(stat.rdev.major, 1)
    assert_equal(stat.rdev.minor, 5)
    assert_equal(stat.rdev.device, t.device(1, 5).device)
    assert(S.unlink(tmpfile))
  end,
  test_copy_dev_zero_root = function()
    local st = assert(S.stat("/dev/zero"))
    assert(S.mknod(tmpfile, "fchr,0666", st.rdev)) -- copy device node
    local st2 = assert(S.stat(tmpfile))
    assert_equal(st2.rdev.dev, st.rdev.dev)
    local fd, err = S.open(tmpfile, "rdonly")
    if not fd and (err.OPNOTSUPP or err.NXIO) then error "skipped" end -- FreeBSD, OpenBSD have restrictibe device policies
    assert(fd, err)
    assert(S.unlink(tmpfile))
    local buf = t.buffer(64)
    local n = assert(fd:read(buf, 64))
    assert_equal(n, 64)
    for i = 0, 63 do assert_equal(buf[i], 0) end
    assert(fd:close())
  end,
  test_mkfifo = function()
    assert(S.mkfifo(tmpfile, "rwxu"))
    local stat = assert(S.stat(tmpfile))
    assert(stat.isfifo, "expect to be a fifo")
    assert(S.unlink(tmpfile))
  end,
  test_futimens = function()
    if not S.futimens then error "skipped" end
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
    assert(util.createfile(tmpfile))
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

test_file_operations_at = {
  teardown = clean,
  test_linkat = function()
    if not S.linkat then error "skipped" end
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(S.linkat("fdcwd", tmpfile, "fdcwd", tmpfile2, "symlink_follow"))
    assert(S.unlink(tmpfile2))
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_openat = function()
    if not S.openat then error "skipped" end
    local fd = assert(S.openat("fdcwd", tmpfile, "rdwr,creat", "rwxu"))
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_faccessat = function()
    if not S.faccessat then error "skipped" end
    local fd = S.open("/dev")
    assert(fd:faccessat("null", "r"))
    assert(fd:faccessat("null", c.OK.R), "expect access to say can read /dev/null")
    assert(fd:faccessat("null", "w"), "expect access to say can write /dev/null")
    assert(not fd:faccessat("/dev/null", "x"), "expect access to say cannot execute /dev/null")
    assert(fd:close())
  end,
  test_symlinkat = function()
    if not (S.symlinkat and S.readlinkat) then error "skipped" end
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
  test_mkdirat_unlinkat = function()
    if not (S.mkdirat and S.unlinkat) then error "skipped" end
    local fd = assert(S.open("."))
    assert(fd:mkdirat(tmpfile, "RWXU"))
    assert(fd:unlinkat(tmpfile, "removedir"))
    assert(not S.stat(tmpfile), "expect dir gone")
    assert(fd:close())
  end,
  test_renameat = function()
    if not S.renameat then error "skipped" end
    assert(util.writefile(tmpfile, teststring, "RWXU"))
    assert(S.renameat("fdcwd", tmpfile, "fdcwd", tmpfile2))
    assert(not S.stat(tmpfile))
    assert(S.stat(tmpfile2))
    assert(S.unlink(tmpfile2))
  end,
  test_fstatat = function()
    if not S.fstatat then error "skipped" end
    local fd = assert(S.open("."))
    assert(util.writefile(tmpfile, teststring, "RWXU"))
    local stat = assert(fd:fstatat(tmpfile))
    assert(stat.size == #teststring, "expect length to be what was written")
    assert(fd:close())
    assert(S.unlink(tmpfile))
  end,
  test_fstatat_fdcwd = function()
    if not S.fstatat then error "skipped" end
    assert(util.writefile(tmpfile, teststring, "RWXU"))
    local stat = assert(S.fstatat("fdcwd", tmpfile, nil, "symlink_nofollow"))
    assert(stat.size == #teststring, "expect length to be what was written")
    assert(S.unlink(tmpfile))
  end,
  test_fchmodat = function()
    if not S.fchmodat then error "skipped" end
    local dirfd = assert(S.open("."))
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(dirfd:fchmodat(tmpfile, "RUSR, WUSR"))
    assert(S.access(tmpfile, "rw"))
    assert(S.unlink(tmpfile))
    assert(fd:close())
    assert(dirfd:close())
  end,
  test_fchownat_root = function()
    if not S.fchownat then error "skipped" end
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
  test_mkfifoat = function()
    if not S.mkfifoat then error "skipped" end
    local fd = assert(S.open("."))
    assert(S.mkfifoat(fd, tmpfile, "rwxu"))
    local stat = assert(S.stat(tmpfile))
    assert(stat.isfifo, "expect to be a fifo")
    assert(fd:close())
    assert(S.unlink(tmpfile))
  end,
  test_mknodat_root = function()
    if not S.mknodat then error "skipped" end
    local fd = assert(S.open("."))
    assert(fd:mknodat(tmpfile, "fchr,0666", t.device(1, 5)))
    local stat = assert(S.stat(tmpfile))
    assert(stat.ischr, "expect to be a character device")
    assert_equal(stat.rdev.major, 1)
    assert_equal(stat.rdev.minor, 5)
    assert_equal(stat.rdev.device, t.device(1, 5).device)
    assert(fd:close())
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
    assert(util.createfile(tmpdir .. "/file1"))
    assert(util.createfile(tmpdir .. "/file2"))
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
    assert(util.createfile(tmpdir .. "/file1"))
    assert(util.createfile(tmpdir .. "/file2"))
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
    for i = 1, num do assert(util.createfile(tmpdir .. "/file" .. i)) end
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
    assert(util.createfile(tmpdir .. "/file"))
    local list = assert(util.dirtable(tmpdir, true))
    assert_equal(#list, 1, "one item in directory")
    assert_equal(list[1], "file", "one file called file")
    assert_equal(tostring(list), "file\n")
    assert(S.unlink(tmpdir .. "/file"))
    assert(S.rmdir(tmpdir))
  end,
}

test_largefile = {
  teardown = clean,
  test_seek = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(S.unlink(tmpfile))
    local offset = 2^34 -- should work with Lua numbers up to 56 bits, above that need explicit 64 bit type.
    local n
    n = assert(fd:lseek(offset, "set"))
    assert_equal(n, offset, "seek should position at set position")
    n = assert(fd:lseek(offset, "cur"))
    assert_equal(n, offset + offset, "seek should position at set position")
    assert(fd:close())
  end,
  test_seek_error = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(S.unlink(tmpfile))
    local off, err = fd:lseek(-1, "cur")
    assert(not off and err.INVAL)
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
    if not S.preadv then error "skipped" end
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
  test_open = function()
    local fd = assert(S.open(tmpfile, "creat,wronly,trunc", "RWXU"))
    local offset = largeval
    assert(fd:truncate(offset))
    local st = assert(fd:stat())
    assert_equal(st.size, offset)
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_openat = function()
    if not S.openat then error "skipped" end
    local fd = assert(S.openat("fdcwd", tmpfile, "creat,wronly,trunc", "RWXU"))
    local offset = largeval
    assert(fd:truncate(offset))
    local st = assert(fd:stat())
    assert_equal(st.size, offset)
    assert(S.unlink(tmpfile))
    assert(fd:close())
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
  teardown = clean,
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
    local pr, pw = assert(S.pipe())
    assert(pw:write("test"))
    assert_equal(pr:read(), "test")
    assert(pr:close())
    assert(pw:close())
  end,
  test_pipe2 = function()
    if not S.pipe2 then error "skipped" end
    local pr, pw = assert(S.pipe2("nonblock, cloexec"))
    assert(pw:write("test"))
    assert_equal(pr:read(), "test")
    assert(pr:close())
    assert(pw:close())
  end,
  test_socketpair = function()
    local sv1, sv2 = assert(S.socketpair("unix", "stream"))
    assert(sv1:write("test"))
    local r = assert(sv2:read())
    assert_equal(r, "test")
    assert(sv1:close())
    assert(sv2:close())
  end,
  test_inet_socket = function() -- TODO break this test up
    local ss, err = S.socket("inet", "stream")
    if not ss and err.AFNOSUPPORT then error "skipped" end
    assert(ss, err)
    assert(ss:nonblock())
    local sa = assert(t.sockaddr_in(0, "loopback"))
    assert_equal(sa.family, c.AF.INET)
    assert(ss:bind(sa))
    local ba = assert(ss:getsockname())
    assert_equal(ba.family, c.AF.INET)
    assert(ss:listen()) -- will fail if we did not bind
    local cs, err = S.socket("inet", "stream")
    if not cs and err.AFNOSUPPORT then error "skipped" end
    assert(cs, err)
    local ok, err = cs:connect(ba)
    local as = ss:accept()
    local ok, err = cs:connect(ba)
    assert(ok or err.ISCONN);
    assert(ss:block()) -- force accept to wait
    as = as or assert(ss:accept())
    assert(as:block())
    local ba = assert(cs:getpeername())
    assert_equal(ba.family, c.AF.INET)
    assert_equal(tostring(ba.addr), "127.0.0.1")
    assert_equal(ba.sin_addr.s_addr, t.in_addr("loopback").s_addr)
    local n = assert(cs:send(teststring))
    assert_equal(n, #teststring)
    local str = assert(as:read(nil, #teststring))
    assert_equal(str, teststring)
    -- test scatter gather
    local b0 = t.buffer(4)
    local b1 = t.buffer(3)
    ffi.copy(b0, "test", 4) -- string init adds trailing 0 byte
    ffi.copy(b1, "ing", 3)
    n = assert(cs:writev({{b0, 4}, {b1, 3}}))
    assert_equal(n, 7)
    b0 = t.buffer(3)
    b1 = t.buffer(4)
    local iov = t.iovecs{{b0, 3}, {b1, 4}}
    n = assert(as:readv(iov))
    assert_equal(n, 7)
    assert(ffi.string(b0, 3) == "tes" and ffi.string(b1, 4) == "ting", "expect to get back same stuff")
    assert(cs:close())
    assert(as:close())
    assert(ss:close())
  end,
  test_inet_socket_readv = function() -- part of above, no netbsd bug (but commenting out writev does trigger)
    local ss, err = S.socket("inet", "stream")
    if not ss and err.AFNOSUPPORT then error "skipped" end
    assert(ss, err)
    assert(ss:nonblock())
    local sa = assert(t.sockaddr_in(0, "loopback"))
    assert_equal(sa.family, c.AF.INET)
    assert(ss:bind(sa))
    local ba = assert(ss:getsockname())
    assert_equal(ba.family, c.AF.INET)
    assert(ss:listen()) -- will fail if we did not bind
    local cs = assert(S.socket("inet", "stream")) -- client socket
    local ok, err = cs:connect(ba)
    local as = ss:accept()
    local ok, err = cs:connect(ba)
    assert(ok or err.ISCONN);
    assert(ss:block()) -- force accept to wait
    as = as or assert(ss:accept())
    assert(as:block())
    local b0 = t.buffer(4)
    local b1 = t.buffer(3)
    ffi.copy(b0, "test", 4) -- string init adds trailing 0 byte
    ffi.copy(b1, "ing", 3)
    local n = assert(cs:writev({{b0, 4}, {b1, 3}}))
    assert(n == 7, "expect writev to write 7 bytes")
    b0 = t.buffer(3)
    b1 = t.buffer(4)
    local iov = t.iovecs{{b0, 3}, {b1, 4}}
    n = assert(as:readv(iov))
    assert_equal(n, 7, "expect readv to read 7 bytes")
    assert(ffi.string(b0, 3) == "tes" and ffi.string(b1, 4) == "ting", "expect to get back same stuff")
    assert(cs:close())
    assert(as:close())
    assert(ss:close())
  end,
  test_inet6_socket = function() -- TODO break this test up
    local ss, err = S.socket("inet6", "stream")
    if not ss and err.AFNOSUPPORT then error "skipped" end
    assert(ss, err)
    assert(ss:nonblock())
    local sa = assert(t.sockaddr_in6(0, "loopback"))
    assert_equal(sa.family, c.AF.INET6)
    ok, err = ss:bind(sa)
    if not ok and err.ADDRNOTAVAIL then error "skipped" end
    assert(ok, err)
    local ba = assert(ss:getsockname())
    assert_equal(ba.family, c.AF.INET6)
    assert(ss:listen()) -- will fail if we did not bind
    local cs = assert(S.socket("inet6", "stream")) -- client socket
    local ok, err = cs:connect(ba)
    local as = ss:accept()
    local ok, err = cs:connect(ba)
    assert(ok or err.ISCONN);
    assert(ss:block()) -- force accept to wait
    as = as or assert(ss:accept())
    assert(as:block())
    local ba = assert(cs:getpeername())
    assert_equal(ba.family, c.AF.INET6)
    assert_equal(tostring(ba.addr), "::1")
    local n = assert(cs:send(teststring))
    assert_equal(n, #teststring)
    local str = assert(as:read(nil, #teststring))
    assert_equal(str, teststring)
    -- test scatter gather
    local b0 = t.buffer(4)
    local b1 = t.buffer(3)
    ffi.copy(b0, "test", 4) -- string init adds trailing 0 byte
    ffi.copy(b1, "ing", 3)
    n = assert(cs:writev({{b0, 4}, {b1, 3}}))
    assert_equal(n, 7)
    b0 = t.buffer(3)
    b1 = t.buffer(4)
    local iov = t.iovecs{{b0, 3}, {b1, 4}}
    n = assert(as:readv(iov))
    assert_equal(n, 7)
    assert(ffi.string(b0, 3) == "tes" and ffi.string(b1, 4) == "ting", "expect to get back same stuff")
    assert(cs:close())
    assert(as:close())
    assert(ss:close())
  end,
  test_inet6_inet_conn_socket = function() -- TODO break this test up
    local ss, err = S.socket("inet6", "stream")
    if not ss and err.AFNOSUPPORT then error "skipped" end
    assert(ss, err)
    assert(ss:nonblock())
    local ok, err = ss:setsockopt(c.IPPROTO.IPV6, c.IPV6.V6ONLY, 0)
    if not ok and err.INVAL then error "skipped" end -- OpenBSD does not support inet on inet6 sockets
    local sa = assert(t.sockaddr_in6(0, "any"))
    assert_equal(sa.family, c.AF.INET6)
    assert(ss:bind(sa))
    local ba = assert(ss:getsockname())
    assert_equal(ba.family, c.AF.INET6)
    assert(ss:listen()) -- will fail if we did not bind
    local cs = assert(S.socket("inet6", "stream")) -- ipv6 client socket, ok
    local ba6 = t.sockaddr_in6(ba.port, "loopback") 
    local ok, err = cs:connect(ba6)
    local as = ss:accept()
    local ok, err = cs:connect(ba6)
    if err.ADDRNOTAVAIL or err.NETUNREACH then error "skipped" end
    assert(ok or err.ISCONN, "unexpected error " .. tostring(err));
    assert(ss:block()) -- force accept to wait
    as = as or assert(ss:accept())
    assert(as:block())
    local ba = assert(cs:getpeername())
    assert_equal(ba.family, c.AF.INET6)
    assert_equal(tostring(ba.addr), "::1")
    local n = assert(cs:send(teststring))
    assert_equal(n, #teststring)
    local str = assert(as:read(nil, #teststring))
    assert_equal(str, teststring)
    assert(cs:close())
    assert(as:close())
    -- second connection
    assert(ss:nonblock())
    local cs, err = S.socket("inet", "stream") -- ipv4 client socket, ok
    if not cs and err.AFNOSUPPORT then error "skipped" end
    assert(cs, err)
    local ba4 = t.sockaddr_in(ba.port, "loopback") -- TODO add function to convert sockaddr in6 to in4
    local ok, err = cs:connect(ba4)
    local as = ss:accept()
    local ok, err = cs:connect(ba4)
    assert(ok or err.ISCONN, "unexpected error " .. tostring(err));
    assert(ss:block()) -- force accept to wait
    as = as or assert(ss:accept())
    assert(as:block())
    local ba = assert(cs:getpeername())
    assert_equal(ba.family, c.AF.INET)
    assert_equal(tostring(ba.addr), "127.0.0.1")
    local n = assert(cs:send(teststring))
    assert_equal(n, #teststring)
    local str = assert(as:read(nil, #teststring))
    assert_equal(str, teststring)
    assert(cs:close())
    assert(as:close())
    assert(ss:close())
  end,
  test_inet6_only_inet_conn_socket = function()
    local ss, err = S.socket("inet6", "stream")
    if not ss and err.AFNOSUPPORT then error "skipped" end
    assert(ss, err)
    assert(ss:nonblock())
    assert(ss:setsockopt(c.IPPROTO.IPV6, c.IPV6.V6ONLY, 1))
    local sa = assert(t.sockaddr_in6(0, "loopback"))
    assert_equal(sa.family, c.AF.INET6)
    ok, err = ss:bind(sa)
    if not ok and err.ADDRNOTAVAIL then error "skipped" end
    assert(ok, err)
    local ba = assert(ss:getsockname())
    assert_equal(ba.family, c.AF.INET6)
    assert(ss:listen()) -- will fail if we did not bind
    local cs = assert(S.socket("inet6", "stream")) -- ipv6 client socket, ok
    local ok, err = cs:connect(ba)
    local as = ss:accept()
    local ok, err = cs:connect(ba)
    assert(ok or err.ISCONN, "unexpected error " .. tostring(err));
    assert(ss:block()) -- force accept to wait
    as = as or assert(ss:accept())
    assert(as:block())
    local ba = assert(cs:getpeername())
    assert_equal(ba.family, c.AF.INET6)
    assert_equal(tostring(ba.addr), "::1")
    local n = assert(cs:send(teststring))
    assert_equal(n, #teststring)
    local str = assert(as:read(nil, #teststring))
    assert_equal(str, teststring)
    assert(cs:close())
    assert(as:close())
    -- second connection
    assert(ss:nonblock())
    local cs, err = S.socket("inet", "stream") -- ipv4 client socket, will fail to connect
    if not cs and err.AFNOSUPPORT then error "skipped" end
    assert(cs, err)
    local ba4 = t.sockaddr_in(ba.port, "loopback") -- TODO add function to convert sockaddr in6 to in4
    local ok, err = cs:connect(ba4)
    assert(not ok, "expect connect to fail with ipv4 connection when set to ipv6 only")
    assert(err.CONNREFUSED, err)
    assert(cs:close())
    assert(as:close())
    assert(ss:close())
  end,
  test_inet6_only_inet_conn_socket2 = function()
    local ss, err = S.socket("inet6", "stream")
    if not ss and err.AFNOSUPPORT then error "skipped" end
    assert(ss, err)
    assert(ss:nonblock())
    assert(ss:setsockopt(c.IPPROTO.IPV6, c.IPV6.V6ONLY, 1))
    local sa = assert(t.sockaddr_in6(0, "loopback"))
    assert_equal(sa.family, c.AF.INET6)
    ok, err = ss:bind(sa)
    if not ok and err.ADDRNOTAVAIL then error "skipped" end
    assert(ok, err)
    local ba = assert(ss:getsockname())
    assert_equal(ba.family, c.AF.INET6)
    assert(ss:listen()) -- will fail if we did not bind
    local cs, err = S.socket("inet", "stream") -- ipv4 client socket, will fail to connect
    if not cs and err.AFNOSUPPORT then error "skipped" end
    assert(cs, err)
    local ba4 = t.sockaddr_in(ba.port, "loopback") -- TODO add function to convert sockaddr in6 to in4
    local ok, err = cs:connect(ba4)
    assert(not ok, "expect connect to fail with ipv4 connection when set to ipv6 only")
    assert(err.CONNREFUSED, err)
    assert(cs:close())
    assert(ss:close())
  end,
  test_udp_socket = function()
    local ss, err = S.socket("inet", "dgram")
    if not ss and err.AFNOSUPPORT then error "skipped" end
    assert(ss, err)
    local cs, err = S.socket("inet", "dgram")
    if not cs and err.AFNOSUPPORT then error "skipped" end
    assert(cs, err)
    local sa = assert(t.sockaddr_in(0, "loopback"))
    assert(ss:bind(sa))
    local bsa = ss:getsockname() -- find bound address
    local n = assert(cs:sendto(teststring, #teststring, 0, bsa))
    local f = assert(ss:recv(buf, size))
    assert_equal(f, #teststring)
    assert(ss:close())
    assert(cs:close())
  end,
  test_inet6_udp_socket = function()
    local ss, err = S.socket("inet6", "dgram")
    if not ss and err.AFNOSUPPORT then error "skipped" end
    assert(ss, err)
    local loop6 = "::1"
    local cs = assert(S.socket("inet6", "dgram"))
    local sa = assert(t.sockaddr_in6(0, loop6))
    ok, err = ss:bind(sa)
    if not ok and err.ADDRNOTAVAIL then error "skipped" end
    assert(ok, err)
    local bsa = ss:getsockname() -- find bound address
    local n = assert(cs:sendto(teststring, nil, c.MSG.NOSIGNAL or 0, bsa)) -- got a sigpipe here on MIPS
    local f = assert(ss:recv(buf, size))
    assert_equal(f, #teststring)
    assert(cs:close())
    assert(ss:close())
  end,
  test_recvfrom = function()
    local ss, err = S.socket("inet", "dgram")
    if not ss and err.AFNOSUPPORT then error "skipped" end
    assert(ss, err)
    local cs, err = S.socket("inet", "dgram")
    if not cs and err.AFNOSUPPORT then error "skipped" end
    assert(cs, err)
    local sa = t.sockaddr_in(0, "loopback")
    assert(ss:bind(sa))
    assert(cs:bind(sa))
    local bsa = ss:getsockname()
    local csa = cs:getsockname()
    local n = assert(cs:sendto(teststring, #teststring, c.MSG.NOSIGNAL or 0, bsa))
    local rsa = t.sockaddr_in()
    local f = assert(ss:recvfrom(buf, size, "", rsa))
    assert_equal(f, #teststring)
    assert_equal(rsa.port, csa.port)
    assert_equal(tostring(rsa.addr), "127.0.0.1")
    assert(ss:close())
    assert(cs:close())
  end,
  test_recvfrom_alloc = function()
    local ss, err = S.socket("inet", "dgram")
    if not ss and err.AFNOSUPPORT then error "skipped" end
    assert(ss, err)
    local cs, err = S.socket("inet", "dgram")
    if not cs and err.AFNOSUPPORT then error "skipped" end
    assert(cs, err)
    local sa = t.sockaddr_in(0, "loopback")
    assert(ss:bind(sa))
    assert(cs:bind(sa))
    local bsa = ss:getsockname()
    local csa = cs:getsockname()
    local n = assert(cs:sendto(teststring, #teststring, c.MSG.NOSIGNAL or 0, bsa))
    local f, rsa = assert(ss:recvfrom(buf, size)) -- will allocate and return address
    assert_equal(f, #teststring)
    assert_equal(rsa.port, csa.port)
    assert_equal(tostring(rsa.addr), "127.0.0.1")
    assert(ss:close())
    assert(cs:close())
  end,
  test_named_unix = function()
    local sock = assert(S.socket("local", "stream"))
    local sa = t.sockaddr_un(tmpfile)
    assert(sock:bind(sa))
    local st = assert(S.stat(tmpfile))
    assert(st.issock)
    assert(sock:close())
    assert(S.unlink(tmpfile))
  end,
  test_notsock_error = function() -- this error number differs on NetBSD, Linux so good test of rump/rumplinux error handling
    local fd = assert(S.open("/dev/null", "RDONLY"))
    local sa = t.sockaddr_in(0, "loopback")
    local ok, err = fd:bind(sa)
    assert(not ok and err.NOTSOCK)
    assert_equal(tostring(err), "Socket operation on non-socket")
    assert(fd:close())
  end,
  test_getsockopt_acceptconn = function()
    local s, err = S.socket("inet", "stream")
    if not s and err.AFNOSUPPORT then error "skipped" end
    assert(s, err)
    local sa = t.sockaddr_in(0, "loopback")
    assert(s:bind(sa))
    local ok, err = s:getsockopt("socket", "acceptconn")
    if not ok and err.NOPROTOOPT then error "skipped" end -- NetBSD 6, OSX do not support this on socket level
    assert(ok, err)
    assert_equal(ok, 0)
    assert(s:close())
  end,
  test_sockopt_sndbuf = function()
    local s, err = S.socket("inet", "stream")
    if not s and err.AFNOSUPPORT then error "skipped" end
    assert(s, err)
    local n = assert(s:getsockopt("socket", "sndbuf"))
    assert(n > 0)
    assert(s:close())
  end,
  test_sockopt_sndbuf_inet6 = function()
    local s, err = S.socket("inet6", "stream")
    if not s and err.AFNOSUPPORT then error "skipped" end
    assert(s, err)
    local n = assert(s:getsockopt("socket", "sndbuf"))
    assert(n > 0)
    assert(s:close())
  end,
  test_setsockopt_keepalive = function()
    local s, err = S.socket("inet", "stream")
    if not s and err.AFNOSUPPORT then error "skipped" end
    assert(s, err)
    local sa = t.sockaddr_in(0, "loopback")
    assert(s:bind(sa))
    assert_equal(s:getsockopt("socket", "keepalive"), 0)
    assert(s:setsockopt("socket", "keepalive", 1))
    assert(s:getsockopt("socket", "keepalive") ~= 0)
    assert(s:close())
  end,
  test_setsockopt_keepalive_inet6 = function()
    local s, err = S.socket("inet6", "stream")
    if not s and err.AFNOSUPPORT then error "skipped" end
    assert(s, err)
    local s = assert(S.socket("inet6", "stream"))
    local sa = t.sockaddr_in6(0, "loopback")
    ok, err = s:bind(sa)
    if not ok and err.ADDRNOTAVAIL then error "skipped" end
    assert(ok, err)
    assert_equal(s:getsockopt("socket", "keepalive"), 0)
    assert(s:setsockopt("socket", "keepalive", 1))
    assert(s:getsockopt("socket", "keepalive") ~= 0)
    assert(s:close())
  end,
  test_sockopt_tcp_nodelay = function()
    local s, err = S.socket("inet", "stream")
    if not s and err.AFNOSUPPORT then error "skipped" end
    assert(s, err)
    local sa = t.sockaddr_in(0, "loopback")
    assert(s:bind(sa))
    assert_equal(s:getsockopt(c.IPPROTO.TCP, c.TCP.NODELAY), 0)
    assert(s:setsockopt(c.IPPROTO.TCP, c.TCP.NODELAY, 1))
    assert(s:getsockopt(c.IPPROTO.TCP, c.TCP.NODELAY) ~= 0)
    assert(s:close())
  end,
  test_sockopt_tcp_nodelay_inet6 = function()
    local s, err = S.socket("inet6", "stream")
    if not s and err.AFNOSUPPORT then error "skipped" end
    assert(s, err)
    local s = assert(S.socket("inet6", "stream"))
    local sa = t.sockaddr_in6(0, "loopback")
    ok, err = s:bind(sa)
    if not ok and err.ADDRNOTAVAIL then error "skipped" end
    assert(ok, err)
    assert_equal(s:getsockopt(c.IPPROTO.TCP, c.TCP.NODELAY), 0)
    assert(s:setsockopt(c.IPPROTO.TCP, c.TCP.NODELAY, 1))
    assert(s:getsockopt(c.IPPROTO.TCP, c.TCP.NODELAY) ~= 0)
    assert(s:close())
  end,
  test_accept_noaddr = function()
    local s = S.socket("unix", "stream")
    assert(s:nonblock())
    local sa = t.sockaddr_un(tmpfile)
    assert(s:bind(sa))
    assert(s:listen())
    local a, err = s:accept()
    assert((not a) and err.AGAIN, "expect again: " .. tostring(err))
    assert(s:close())
    assert(S.unlink(tmpfile))
  end,
  test_accept4 = function()
    if not S.accept4 then error "skipped" end
    local s = S.socket("unix", "stream, nonblock")
    local sa = t.sockaddr_un(tmpfile)
    assert(s:bind(sa))
    assert(s:listen())
    local sa = t.sockaddr_un()
    local a, err = s:accept4(sa, nil, "nonblock")
    assert((not a) and err.AGAIN, "expect again: " .. tostring(err))
    assert(s:close())
    assert(S.unlink(tmpfile))
  end,
  test_send = function()
    local buf = t.buffer(10)
    local sv1, sv2 = assert(S.socketpair("unix", "stream"))
    assert(sv1:send("test"))
    local r = assert(sv2:recv(buf, 10))
    assert_equal(r, #"test")
    assert_equal(ffi.string(buf, r), "test")
    assert(sv1:close())
    assert(sv2:close())
  end,
  test_sendto = function()
    local buf = t.buffer(10)
    local sv1, sv2 = assert(S.socketpair("unix", "stream"))
    assert(sv1:sendto("test"))
    local r, addr = assert(sv2:recvfrom(buf, 10))
    assert_equal(r, #"test")
    assert_equal(ffi.string(buf, r), "test")
    --assert_equal(addr.family, c.AF.UNIX) -- TODO addrlen seen as 0 so not filled in?
    assert(sv1:close())
    assert(sv2:close())
  end,
  test_sendto_src = function()
    local buf = t.buffer(10)
    local sa = t.sockaddr_un()
    local sv1, sv2 = assert(S.socketpair("unix", "stream"))
    assert(sv1:sendto("test"))
    local r = assert(sv2:recvfrom(buf, 10, 0, sa))
    assert_equal(r, #"test")
    assert_equal(ffi.string(buf, r), "test")
    assert_equal(sa.family, c.AF.UNIX) -- TODO addrlen seen as 0 so not filled in?
    assert(sv1:close())
    assert(sv2:close())
  end,
  test_sendmsg = function()
    local buf = t.buffer(4)
    ffi.copy(buf, "test", 4)
    local iov = t.iovecs{{buf, 4}}
    local sa = t.sockaddr_storage()
    local sv1, sv2 = assert(S.socketpair("unix", "stream"))
    local msg = t.msghdr{iov = iov}
    assert(sv1:sendmsg(msg))
    local msg = t.msghdr{name = sa, iov = iov}
    local r = assert(sv2:recvmsg(msg))
    assert_equal(r, #"test")
    assert_equal(ffi.string(buf, r), "test")
    --assert_equal(sa.family, c.AF.UNIX) -- TODO addrlen seen as 0 so not filled in?
    assert(sv1:close())
    assert(sv2:close())
  end,
  test_sendmmsg = function()
    if not S.sendmmsg then error "skipped" end
    local buf = t.buffer(4)
    ffi.copy(buf, "test", 4)
    local iov = t.iovecs{{buf, 4}}
    local sa = t.sockaddr_storage()
    local sv1, sv2 = assert(S.socketpair("unix", "stream"))
    local msg = t.mmsghdrs{{iov = iov}}
    local ok, err = sv1:sendmmsg(msg)
    if not ok and err.NOSYS then error "skipped" end
    assert(ok, err)
    local msg = t.mmsghdrs{{name = sa, iov = iov}}
    assert(sv2:recvmmsg(msg))
    assert_equal(msg.msg[0].len, #"test")
    assert_equal(ffi.string(msg.msg[0].hdr.msg_iov[0].base, msg.msg[0].len), "test")
    --assert_equal(sa.family, c.AF.UNIX) -- TODO addrlen seen as 0 so not filled in?
    assert(sv1:close())
    assert(sv2:close())
  end,
}

test_timespec_timeval = {
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
  teardown = clean,
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
    --assert(ptm:isatty()) -- oddly fails in osx, unclear if that is valid
    local pts_name = assert(ptm:ptsname())
    local pts = assert(S.open(pts_name, "rdwr, noctty"))
    assert(pts:isatty(), "should be a tty")
    if S.tcgetsid then
      local ok, err = pts:tcgetsid()
      assert(not ok, "should not get sid as noctty")
    end
    local termios = assert(pts:tcgetattr())
    assert(termios.ospeed ~= 115200, "speed should not be 115200")
    termios.speed = 115200
    assert_equal(termios.ispeed, 115200)
    assert_equal(termios.ospeed, 115200)
    --assert(bit.band(termios.lflag, c.LFLAG.ICANON) ~= 0, "CANON non zero") -- default seems to differ on mips?
    termios:makeraw()
    assert_equal(bit.band(termios.lflag, c.LFLAG.ICANON), 0)
    assert(pts:tcsetattr("now", termios))
    termios = assert(pts:tcgetattr()) -- TODO failing on mips
    assert_equal(termios.ospeed, 115200)
    assert_equal(bit.band(termios.lflag, c.LFLAG.ICANON), 0)
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
  test_ioctl_winsize = function()
    local ws, err = S.stdout:ioctl("TIOCGWINSZ")
    if not ws and err.NOTTY then error "skipped" end -- stdout might not be a tty in test env
    assert(ws, err)
    if ws.row == 0 and ws.col == 0 then error "skipped" end
    assert(ws.row > 0 and ws.col > 0, "expect positive winsz")
  end,
}

test_misc = {
  teardown = clean,
  test_chroot_root = function()
    local cwd = assert(S.open(".", "rdonly"))
    local cname = assert(S.getcwd())
    local root = assert(S.open("/", "rdonly"))
    assert(S.mkdir(tmpfile, "0700"))
    assert(S.chdir("/"))
    assert(S.chroot(cname .. "/" .. tmpfile))
    local ok, err = S.stat("/dev")
    assert(not ok, "should not find /dev after chroot")
    -- note that NetBSD will chdir after chroot, so chroot(".") will not work, but does provide fchroot, which Linux does not
    -- however other BSDs also do this; we could only test with fork so give up
    if S.fchroot then
      assert(root:chroot())
    else
      if abi.os ~= "linux" then error "skipped" end
      assert(S.chroot("."))
    end
    assert(cwd:chdir())
    assert(S.rmdir(tmpfile))
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
  test_sysctl = function()
    local os = abi.os
    if S.__rump then os = "netbsd" end
    local sc = "kern.ostype"
    if os == "linux" then sc = "kernel.ostype" end
    local val = assert(S.sysctl(sc))
    if val:lower() == "darwin" then val = "osx" end
    assert_equal(val:lower(), os)
  end,
}

test_raw_socket = {
  test_ip_checksum = function()
    local packet = {0x45, 0x00,
      0x00, 0x73, 0x00, 0x00,
      0x40, 0x00, 0x40, 0x11,
      0xb8, 0x61, 0xc0, 0xa8, 0x00, 0x01,
      0xc0, 0xa8, 0x00, 0xc7}

    local expected
    if abi.le then expected = 0x61B8 else expected = 0xB861 end

    local buf = t.buffer(#packet, packet)
    local iphdr = pt.iphdr(buf)
    iphdr[0].check = 0
    local cs = iphdr[0]:checksum()
    assert(cs == expected, "expect correct ip checksum: got " .. string.format("%%%04X", cs) .. " expected " .. string.format("%%%04X", expected))
  end,
  test_raw_udp_root = function() -- TODO create some helper functions, this is not very nice
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
    iphdr[0] = {ihl = 5, version = 4, tos = 0, id = 0, frag_off = helpers.htons(0x4000), ttl = 64, protocol = c.IPPROTO.UDP, check = 0,
             saddr = sa.sin_addr.s_addr, daddr = ca.sin_addr.s_addr, tot_len = helpers.htons(len)}

    --udphdr[0] = {src = sport, dst = ca.port, length = udplen} -- doesnt work with metamethods
    udphdr[0].src = sport
    udphdr[0].length = udplen

    udphdr[0].dst = ca.port
    -- we do not need to calulate checksum, can leave as zero (for Linux at least)
    --udphdr[0]:checksum(iphdr[0], buf + s.iphdr + s.udphdr)
    iphdr[0].check = 0

    -- TODO in FreeBSD, NetBSD len is in host byte order not net, see Stephens, http://developerweb.net/viewtopic.php?id=4657
    -- TODO the metamethods should take care of this
    if S.__rump or abi.bsd then iphdr[0].tot_len = len end

    ca.port = 0 -- should not set port

    if abi.os == "openbsd" then error "skipped" end -- TODO fix
    local n = assert(raw:sendto(buf, len, 0, ca))

    -- TODO receive issues on netBSD 
    if not (S.__rump or abi.bsd) then
      local f = assert(cl:recvfrom(buf2, #msg))
      assert_equal(f, #msg)
    end
    assert(raw:close())
    assert(cl:close())
  end,
}

test_util = {
  teardown = clean,
  test_rm_recursive = function()
    assert(S.mkdir(tmpdir, "rwxu"))
    assert(S.mkdir(tmpdir .. "/subdir", "rwxu"))
    assert(util.createfile(tmpdir .. "/file"))
    assert(util.createfile(tmpdir .. "/subdir/subfile"))
    assert(S.stat(tmpdir), "directory should be there")
    assert(S.stat(tmpdir).isdir, "should be a directory")
    local ok, err = S.rmdir(tmpdir)
    assert(util.rm(tmpdir)) -- rm -r
    assert(not S.stat(tmpdir), "directory should be deleted")
    assert(not ok and err.notempty, "should have failed as not empty")
  end,
  test_rm_broken_symlink = function()
    assert(S.mkdir(tmpdir, "rwxu"))
    assert(S.symlink(tmpdir .. "/none", tmpdir .. "/link"))
    assert(util.rm(tmpdir))
    assert(not S.stat(tmpdir), "directory should be deleted")
  end,
  test_touch = function()
    assert(not S.stat(tmpfile3))
    assert(util.touch(tmpfile3))
    assert(S.stat(tmpfile3))
    assert(util.touch(tmpfile3))
    assert(S.unlink(tmpfile3))
  end,
  test_readfile_writefile = function()
    assert(util.writefile(tmpfile, teststring, "RWXU"))
    local ss = assert(util.readfile(tmpfile))
    assert_equal(ss, teststring, "readfile should get back what writefile wrote")
    assert(S.unlink(tmpfile))
  end,
  test_cp = function()
    assert(util.writefile(tmpfile, teststring, "rusr,wusr"))
    assert(util.cp(tmpfile, tmpfile2, "rusr,wusr"))
    assert_equal(assert(util.readfile(tmpfile2)), teststring)
    assert(S.unlink(tmpfile))
    assert(S.unlink(tmpfile2))
  end,
  test_basename_dirname = function()
    assert_equal(util.dirname  "/usr/lib", "/usr")
    assert_equal(util.basename "/usr/lib", "lib")
    assert_equal(util.dirname  "/usr/", "/")
    assert_equal(util.basename "/usr/", "usr")
    assert_equal(util.dirname  "usr", ".")
    assert_equal(util.basename "usr", "usr")
    assert_equal(util.dirname  "/", "/")
    assert_equal(util.basename "/", "/")
    assert_equal(util.dirname  ".", ".")
    assert_equal(util.basename ".", ".")
    assert_equal(util.dirname  "..", ".")
    assert_equal(util.basename "..", "..")
    assert_equal(util.dirname  "", ".")
    assert_equal(util.basename "", ".")
  end,
}

-- TODO work in progress to make work in BSD, temp commented out
-- note send creds moved, as varies by OS
if not (S.__rump or abi.bsd) then
test_sendfd = {
  test_sendfd = function()
    local sv1, sv2 = assert(S.socketpair("unix", "stream"))
    assert(util.sendfds(sv1, S.stdin))
    local r = assert(util.recvcmsg(sv2))
    assert(#r.fd == 1, "expect to get one file descriptor back")
    assert(r.fd[1]:close())
    assert(sv1:close())
    assert(sv2:close())
  end,
}
end

test_sleep = {
  test_nanosleep = function()
    assert(S.nanosleep(0.001))
  end,
  test_sleep = function()
    assert(S.sleep(0))
  end,
}

test_clock = {
  test_clock_gettime = function()
    if not S.clock_gettime then error "skipped" end
    local tt = assert(S.clock_getres("realtime"))
    local tt = assert(S.clock_gettime("realtime"))
    -- TODO add settime
  end,
  test_clock_nanosleep = function()
    if not S.clock_nanosleep then error "skipped" end
    local rem = assert(S.clock_nanosleep("realtime", nil, 0.001))
    assert_equal(rem, nil)
  end,
  test_clock_nanosleep_abs = function()
    if not S.clock_nanosleep then error "skipped" end
    assert(S.clock_nanosleep("realtime", "abstime", 0))
  end,
}

test_timeofday = {
  test_gettimeofday = function()
    if not S.gettimeofday then error "skipped" end
    local tv = assert(S.gettimeofday())
    assert(math.floor(tv.time) == tv.sec, "should be able to get float time from timeval")
  end,
  test_settimeofday_fail = function()
    if not S.settimeofday then error "skipped" end
    local ok, err = S.settimeofday()
    -- eg NetBSD does nothing on null, Linux errors
    assert(ok or (err.PERM or err.INVAL or err.FAULT), "null settimeofday should succeed or fail correctly")
  end,
}

-- on rump timers may not deliver signals, but for our tests we will not let them expire, or disable signals
test_timers = {
  test_timers = function()
    if not S.timer_create then error "skipped" end
    local tid = assert(S.timer_create("monotonic"))
    local it = tid:gettime()
    assert_equal(it.value.time, 0)
    assert(tid:settime(0, {0, 10000}))
    local it = tid:gettime()
    assert(it.value.time > 0, "expect some time left")
    local over = assert(tid:getoverrun())
    assert_equal(over, 0)
    assert(tid:delete())
  end,
  test_timers_nosig = function()
    if not S.timer_create then error "skipped" end
    local tid = assert(S.timer_create("monotonic", {notify = "none"}))
    local it = tid:gettime()
    assert_equal(it.value.time, 0)
    assert(tid:settime(0, {0, 10000}))
    local it = tid:gettime()
    assert(it.value.time > 0, "expect some time left")
    local over = assert(tid:getoverrun())
    assert_equal(over, 0)
    assert(tid:delete())
  end,
}

if not (S.__rump or abi.xen) then -- rump has no processes, memory allocation, process accounting, mmap and proc not applicable

test_signals = {
  test_signal_return = function()
    local orig = assert(S.signal("alrm", "ign"))
    local ret = assert(S.signal("alrm", "dfl"))
    assert_equal(ret, "IGN")
    local ret = assert(S.signal("alrm", orig))
    assert_equal(ret, "DFL")
  end,
  test_pause = function()
    local pid = assert(S.fork())
    if pid == 0 then -- child
      S.pause()
      S.exit(23)
    else -- parent
      S.kill(pid, "term")
      local _, status = assert(S.waitpid(pid))
      assert(status.WIFSIGNALED, "expect normal exit in clone")
      assert_equal(status.WTERMSIG, c.SIG.TERM)
    end
  end,
  test_alarm = function()
    assert(S.signal("alrm", "ign"))
    assert(S.alarm(10))
    assert(S.alarm(0)) -- cancel again
    assert(S.signal("alrm", "dfl"))
  end,
}

test_shm = {
  test_shm = function()
    if not S.shm_open then error "skipped" end
    local name = "/XXXXXYYYY" .. S.getpid()
    local fd, err = S.shm_open(name, "rdwr, creat", "0600")
    if not fd and (err.ACCES or err.NOENT) then error "skipped" end -- Travis CI, Android do not have mounted...
    assert(fd, err)
    assert(S.shm_unlink(name))
    assert(fd:truncate(4096))
    assert(fd:close())
  end,
}

test_util_misc = {
  teardown = clean,
  test_mapfile = function()
    assert(util.writefile(tmpfile, teststring, "RWXU"))
    local ss = assert(util.mapfile(tmpfile))
    assert_equal(ss, teststring, "mapfile should get back what writefile wrote")
    assert(S.unlink(tmpfile))
  end,
}

test_rusage = {
  test_rusage = function()
    local ru = assert(S.getrusage("self"))
    assert(ru.utime.time > 0, "should have used some cpu time")
  end,
}

test_proc = {
  test_ps = function()
    local ps, err = util.ps()
    if not ps and err.NOENT then error "skipped" end -- FreeBSD usually does not have proc mounted, although usually mount point
    assert(ps)
    local me = S.getpid()
    local found = false
    if #ps == 0 then error "skipped" end -- not mounted but mount point exists
    for i = 1, #ps do
      if ps[i].pid == me then found = true end
    end
    assert(found, "expect to find my process in ps")
    assert(tostring(ps), "can convert ps to string")
  end,
  test_proc_self = function()
    local p = util.proc()
    if not p.cmdline then error "skipped" end -- no files found, /proc not mounted
    assert(p.cmdline and #p.cmdline > 1, "expect cmdline to exist")
    assert(not p.wrongname, "test non existent files")
    assert_equal(p.root, "/", "expect our root to be / usually")
  end,
  test_proc_init = function()
    local p = util.proc(1)
    if not p.cmdline then error "skipped" end -- no files found, /proc not mounted
    assert(p and p.cmdline, "expect init to have cmdline")
  end,
}

test_mmap = {
  teardown = clean,
  test_getpagesize = function()
    local pagesize = assert(S.getpagesize())
    assert(pagesize >= 4096, "pagesize at least 4k")
  end,
  test_mmap_fail = function()
    local size = 4096
    local mem, err = S.mmap(pt.void(1), size, "read", "private, fixed, anon", -1, 0)
    assert(err, "expect non aligned fixed map to fail")
    assert(err.INVAL, "expect non aligned map to return EINVAL")
  end,
  test_mmap_anon = function()
    local size = 4096
    local mem = assert(S.mmap(nil, size, "read", "private, anon", -1, 0))
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
  test_mmap_page_offset = function()
    local fd = assert(S.open(tmpfile, "rdwr,creat", "rwxu"))
    assert(S.unlink(tmpfile))
    local pagesize = S.getpagesize()
    local mem = assert(fd:mmap(nil, pagesize, "read", "shared", pagesize))
    assert(S.munmap(mem, size))
    assert(fd:close())
  end,
  test_msync = function()
    local size = 4096
    local mem = assert(S.mmap(nil, size, "read", "private, anon", -1, 0))
    assert(S.msync(mem, size, "sync"))
    assert(S.munmap(mem, size))
  end,
  test_madvise = function()
    local size = 4096
    local mem = assert(S.mmap(nil, size, "read", "private, anon", -1, 0))
    assert(S.madvise(mem, size, "random"))
    assert(S.munmap(mem, size))
  end,
  test_mlock = function()
    local size = 4096
    local mem = assert(S.mmap(nil, size, "read", "private, anon", -1, 0))
    local ok, err = S.mlock(mem, size)
    if not ok and err.PERM then error "skipped" end -- may not be allowed by default
    assert(ok, err)
    assert(S.munlock(mem, size))
    assert(S.munmap(mem, size))
  end,
  test_mlockall = function()
    if not S.mlockall then error "skipped" end
    local ok, err = S.mlockall("current")
    if not ok and err.PERM then error "skipped" end -- may not be allowed by default
    if not ok and err.NOMEM then error "skipped" end -- may fail due to rlimit
    assert(ok, err)
    assert(S.munlockall())
  end,
}

test_processes = {
  test_nice = function()
    local n = assert(S.getpriority("process"))
    --assert_equal(n, 0, "process should start at priority 0")
    --local nn = assert(S.nice(1))
    --assert_equal(nn, 1)
    --local nn = assert(S.setpriority("process", 0, n)) -- sets to 1, which it already is
  end,
  test_fork_wait = function()
    local pid0 = S.getpid()
    local pid = assert(S.fork())
    if pid == 0 then -- child
      fork_assert(S.getppid() == pid0, "parent pid should be previous pid")
      S.exit(23)
    else -- parent
      local rpid, status = assert(S.wait())
      assert(rpid == pid, "expect fork to return same pid as wait")
      assert(status.WIFEXITED, "process should have exited normally")
      assert(status.EXITSTATUS == 23, "exit should be 23")
    end
  end,
  test_fork_waitpid = function()
    local pid0 = S.getpid()
    local pid = assert(S.fork())
    if pid == 0 then -- child
      fork_assert(S.getppid() == pid0, "parent pid should be previous pid")
      S.exit(23)
    else -- parent
      local rpid, status = assert(S.waitpid(-1))
      assert(rpid == pid, "expect fork to return same pid as wait")
      assert(status.WIFEXITED, "process should have exited normally")
      assert(status.EXITSTATUS == 23, "exit should be 23")
    end
  end,
  test_fork_waitid = function()
    if not S.waitid then error "skipped" end -- NetBSD at least has no waitid
    local pid0 = S.getpid()
    local pid = assert(S.fork())
    if pid == 0 then -- child
      fork_assert(S.getppid() == pid0, "parent pid should be previous pid")
      S.exit(23)
    else -- parent
      local infop = assert(S.waitid("all", 0, "exited, stopped, continued"))
      assert_equal(infop.signo, c.SIG.CHLD, "waitid to return SIGCHLD")
      assert_equal(infop.signame, "CHLD", "name of signal is CHLD")
      assert_equal(infop.status, 23, "exit should be 23")
      assert_equal(infop.code, c.SIGCLD.EXITED, "normal exit expected")
    end
  end,
  test_fork_wait4 = function()
    local pid0 = S.getpid()
    local pid = assert(S.fork())
    if pid == 0 then -- child
      fork_assert(S.getppid() == pid0, "parent pid should be previous pid")
      S.exit(23)
    else -- parent
      local rpid, status, rusage = assert(S.wait4("any"))
      assert(rpid == pid, "expect fork to return same pid as wait")
      assert(status.WIFEXITED, "process should have exited normally")
      assert(status.EXITSTATUS == 23, "exit should be 23")
      assert(rusage, "expect to get rusage data back")
    end
  end,
  test_fork_wait3 = function()
    local pid0 = S.getpid()
    local pid = assert(S.fork())
    if pid == 0 then -- child
      fork_assert(S.getppid() == pid0, "parent pid should be previous pid")
      S.exit(23)
    else -- parent
      local rpid, status, rusage = assert(S.wait3())
      assert(rpid == pid, "expect fork to return same pid as wait")
      assert(status.WIFEXITED, "process should have exited normally")
      assert(status.EXITSTATUS == 23, "exit should be 23")
      assert(rusage, "expect to get rusage data back")
    end
  end,
  test_execve = function()
    local pid = assert(S.fork())
    if (pid == 0) then -- child
      local shell = "/bin/sh"
      if not S.stat(shell) then shell = "/system/bin/sh" end -- Android has no /bin/sh
      if not S.stat(shell) then return end -- no shell!
      local script = "#!" .. shell .. [[

[ $1 = "test" ] || (echo "shell assert $1"; exit 1)
[ $2 = "ing" ] || (echo "shell assert $2"; exit 1)
[ $PATH = "/bin:/usr/bin" ] || (echo "shell assert $PATH"; exit 1)

]]
      fork_assert(util.writefile(efile, script, "RWXU"))
      fork_assert(S.execve(efile, {efile, "test", "ing"}, {"PATH=/bin:/usr/bin"})) -- note first param of args overwritten
      -- never reach here
      os.exit()
    else -- parent
      local rpid, status = assert(S.waitpid("any"))
      assert(rpid == pid, "expect fork to return same pid as wait")
      assert(status.WIFEXITED, "process should have exited normally")
      assert(status.EXITSTATUS == 0, "exit should be 0")
      assert(S.unlink(efile))
    end
  end,
  test_setsid = function()
    -- need to fork twice in case start as process leader
    local pp1r, pp1w = assert(S.pipe())
    local pp2r, pp2w = assert(S.pipe())
    local pid = assert(S.fork())
    if (pid == 0) then -- child
      local pid = fork_assert(S.fork())
      if (pid == 0) then -- child
        fork_assert(pp1r:read(nil, 1))
        local ok, err = S.setsid()
        ok = ok and ok == S.getpid() and ok == S.getsid()
        if ok then pp2w:write("y") else pp2w:write("n") end
        S.exit(0)
      else
        S.exit(0)
      end
    else
      assert(S.wait())
      assert(pp1w:write("a"))
      local ok = pp2r:read(nil, 1)
      assert_equal(ok, "y")
      pp1r:close()
      pp1w:close()
      pp2r:close()
      pp2w:close()
    end
  end,
  test_setpgid = function()
    S.setpgid()
    assert_equal(S.getpgid(), S.getpid())
    assert_equal(S.getpgrp(), S.getpid())
  end,
}

end

-- currently disabled in xen as not much use, probably could add though
if S.environ and not abi.xen then -- use this as a proxy for whether libc functions defined (eg not defined in rump)
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
if S.__rump or abi.xen then
  test_largefile = nil
end

-- note at present we check for uid 0, but could check capabilities instead.
if S.geteuid() == 0 then
  if S.unshare then
    -- cut out this section if you want to (careful!) debug on real interfaces
    local ok, err = S.unshare("newnet, newns, newuts")
    if not ok then removeroottests() -- remove if you like, but may interfere with networking
    else
      local nl = S.nl
      local i = assert(nl.interfaces())
      local lo = assert(i.lo)
      assert(lo:up())
      -- Do not destroy "/sys" if it is mounted
      assert(S.statfs("/sys/kernel") or S.mount("none", "/sys", "sysfs"))
    end
  else -- not Linux
    -- run all tests, no namespaces available
  end
else -- remove tests that need root
  removeroottests()
end

local f
if arg[1] then f = luaunit:run(unpack(arg)) else f = luaunit:run() end

clean()

debug.sethook()

if f ~= 0 then
  os.exit(1)
end

collectgarbage("collect")

os.exit(0)


