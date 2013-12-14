-- BSD specific tests

local function init(S)

local helpers = require "syscall.helpers"
local types = S.types
local c = S.c
local abi = S.abi
local features = S.features
local util = S.util

local bit = require "syscall.bit"
local ffi = require "ffi"

local t, pt, s = types.t, types.pt, types.s

local function assert(cond, err, ...)
  collectgarbage("collect") -- force gc, to test for bugs
  if not cond then error(tostring(err)) end -- annoyingly, assert does not call tostring!
  if type(cond) == "function" then return cond, err, ... end
  if cond == true then return ... end
  return cond, ...
end

local function fork_assert(cond, err, ...) -- if we have forked we need to fail in main thread not fork
  if not cond then
    print(tostring(err))
    print(debug.traceback())
    S.exit("failure")
  end
  if cond == true then return ... end
  return cond, ...
end

local function assert_equal(...)
  collectgarbage("collect") -- force gc, to test for bugs
  return assert_equals(...)
end

local teststring = "this is a test string"
local size = 512
local buf = t.buffer(size)
local tmpfile = "XXXXYYYYZZZ4521" .. S.getpid()
local tmpfile2 = "./666666DDDDDFFFF" .. S.getpid()
local tmpfile3 = "MMMMMTTTTGGG" .. S.getpid()
local longfile = "1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890" .. S.getpid()
local efile = "./tmpexXXYYY" .. S.getpid() .. ".sh"
local largeval = math.pow(2, 33) -- larger than 2^32 for testing
local mqname = "ljsyscallXXYYZZ" .. S.getpid()

local clean = function()
  S.rmdir(tmpfile)
  S.unlink(tmpfile)
  S.unlink(tmpfile2)
  S.unlink(tmpfile3)
  S.unlink(longfile)
  S.unlink(efile)
end

local test = {}

test.mount_bsd_root = {
  test_mount_kernfs = function()
    assert(S.mkdir(tmpfile))
    assert(S.mount("kernfs", tmpfile))
    assert(S.unmount(tmpfile))
    assert(S.rmdir(tmpfile))
  end,
  test_util_mount_kernfs = function()
    assert(S.mkdir(tmpfile))
    assert(util.mount{type = "kernfs", dir = tmpfile})
    assert(S.unmount(tmpfile))
    assert(S.rmdir(tmpfile))
  end,
  test_mount_tmpfs = function()
    assert(S.mkdir(tmpfile))
    local data = {ta_version = 1, ta_nodes_max=100, ta_size_max=1048576, ta_root_mode=helpers.octal("0700")}
    assert(S.mount("tmpfs", tmpfile, 0, data))
    assert(S.unmount(tmpfile))
    assert(S.rmdir(tmpfile))
  end,
}

test.filesystem_bsd = {
-- BSD utimensat as same specification as Linux, but some functionality missing, so test simpler
  test_utimensat = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    local dfd = assert(S.open("."))
    assert(S.utimensat(nil, tmpfile))
    local st1 = fd:stat()
    assert(S.utimensat("fdcwd", tmpfile, {"omit", "omit"}))
    local st2 = fd:stat()
    assert(st1.atime == st2.atime and st1.mtime == st2.mtime, "atime and mtime unchanged")
    assert(S.unlink(tmpfile))
    assert(fd:close())
    assert(dfd:close())
  end,
  test_revoke = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(S.revoke(tmpfile))
    local n, err = fd:read()
    assert(not n and err.BADF, "access should be revoked")
    assert(fd:close())
  end,
  test_chflags = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(fd:write("append"))
    assert(S.chflags(tmpfile, "append"))
    assert(fd:write("append"))
    assert(fd:seek(0, "set"))
    local n, err = fd:write("not append")
    if not (S.__rump or abi.xen) then assert(err and err.PERM, "non append write should fail") end -- TODO I think this is due to tmpfs mount??
    assert(S.chflags(tmpfile)) -- clear flags
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_lchflags = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(fd:write("append"))
    assert(S.lchflags(tmpfile, "append"))
    assert(fd:write("append"))
    assert(fd:seek(0, "set"))
    local n, err = fd:write("not append")
    if not (S.__rump or abi.xen) then assert(err and err.PERM, "non append write should fail") end -- TODO I think this is due to tmpfs mount??
    assert(S.lchflags(tmpfile)) -- clear flags
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_fchflags = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(fd:write("append"))
    assert(fd:chflags("append"))
    assert(fd:write("append"))
    assert(fd:seek(0, "set"))
    local n, err = fd:write("not append")
    if not (S.__rump or abi.xen) then assert(err and err.PERM, "non append write should fail") end -- TODO I think this is due to tmpfs mount??
    assert(fd:chflags()) -- clear flags
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_fsync_range = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(fd:sync_range("data", 0, 4096))
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_lchmod = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(S.lchmod(tmpfile, "RUSR, WUSR"))
    assert(S.access(tmpfile, "rw"))
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
}

test.network_utils_bsd_root = {
  test_ifcreate_lo = function()
    local ifname = "lo9" .. tostring(S.getpid())
    assert(util.ifcreate(ifname))
    assert(util.ifdestroy(ifname))
  end,
  test_ifupdown_lo = function()
    local ifname = "lo9" .. tostring(S.getpid())
    assert(util.ifcreate(ifname))
    local flags = assert(util.ifgetflags(ifname))
    assert(bit.band(flags, c.IFF.UP) == 0)
    assert(util.ifup(ifname))
    local flags = assert(util.ifgetflags(ifname))
    assert(bit.band(flags, c.IFF.UP) ~= 0)
    assert(util.ifdown(ifname))
    local flags = assert(util.ifgetflags(ifname))
    assert(bit.band(flags, c.IFF.UP) == 0)
    assert(util.ifdestroy(ifname))
  end,
}

test.sockets_pipes_bsd = {
  test_nosigpipe = function()
    local p1, p2 = assert(S.pipe2("nosigpipe"))
    assert(p1:close())
    local ok, err = p2:write("other end closed")
    assert(not ok and err.PIPE, "should get EPIPE")
    assert(p2:close())
  end,
  test_paccept = function()
    local s = S.socket("unix", "seqpacket, nonblock, nosigpipe")
    local sa = t.sockaddr_un(tmpfile)
    assert(s:bind(sa))
    assert(s:listen())
    local sa = t.sockaddr_un()
    local a, err = s:paccept(sa, nil, "alrm", "nonblock, nosigpipe")
    assert(not a and err.AGAIN, "expect again: " .. tostring(err))
    assert(s:close())
    assert(S.unlink(tmpfile))
  end,
--[[
  test_inet_socket_read_paccept = function() -- triggers PR/48292
    local ss = assert(S.socket("inet", "stream, nonblock"))
    local sa = t.sockaddr_in(0, "loopback")
    assert(ss:bind(sa))
    local ba = assert(ss:getsockname())
    assert(ss:listen())
    local cs = assert(S.socket("inet", "stream")) -- client socket
    local ok, err = cs:connect(ba)
    local as = ss:paccept()
    local ok, err = cs:connect(ba)
    assert(ok or err.ISCONN);
    assert(ss:block()) -- force accept to wait
    as = as or assert(ss:paccept())
    local fl = assert(as:fcntl("getfl"))
    assert_equal(bit.band(fl, c.O.NONBLOCK), 0)
-- TODO commenting out next two lines is issue only with paccept not accept
    local n = assert(cs:write("testing"))
    assert(n == 7, "expect writev to write 7 bytes")
--
    n = assert(as:read())
    assert_equal(n, "testing")
    assert(cs:close())
    assert(as:close())
    assert(ss:close())
  end,
]]
}

test.kqueue = {
  test_kqueue_vnode = function()
    local kfd = assert(S.kqueue("cloexec, nosigpipe"))
    local fd = assert(S.creat(tmpfile, "rwxu"))
    local kevs = t.kevents{{fd = fd, filter = "vnode",
      flags = "add, enable, clear", fflags = "delete, write, extend, attrib, link, rename, revoke"}}
    assert(kfd:kevent(kevs, nil))
    local _, _, n = assert(kfd:kevent(nil, kevs, 0))
    assert_equal(n, 0) -- no events yet
    assert(S.unlink(tmpfile))
    local count = 0
    for k, v in assert(kfd:kevent(nil, kevs, 1)) do
      assert(v.DELETE, "expect delete event")
      count = count + 1
    end
    assert_equal(count, 1)
    assert(fd:write("something"))
    local count = 0
    for k, v in assert(kfd:kevent(nil, kevs, 1)) do
      assert(v.WRITE, "expect write event")
      assert(v.EXTEND, "expect extend event")
    count = count + 1
    end
    assert_equal(count, 1)
    assert(fd:close())
    assert(kfd:close())
  end,
  test_kqueue_read = function()
    local kfd = assert(S.kqueue("cloexec, nosigpipe"))
    local p1, p2 = assert(S.pipe())
    local kevs = t.kevents{{fd = p1, filter = "read", flags = "add"}}
    assert(kfd:kevent(kevs, nil))
    local a, b, n = assert(kfd:kevent(nil, kevs, 0))
    assert_equal(n, 0) -- no events yet
    local str = "test"
    p2:write(str)
    local count = 0
    for k, v in assert(kfd:kevent(nil, kevs, 0)) do
      assert_equal(v.size, #str) -- size will be amount available to read
      count = count + 1
    end
    assert_equal(count, 1) -- 1 event readable now
    local r, err = p1:read()
    local _, _, n = assert(kfd:kevent(nil, kevs, 0))
    assert_equal(n, 0) -- no events any more
    assert(p2:close())
    local count = 0
    for k, v in assert(kfd:kevent(nil, kevs, 0)) do
      assert(v.EOF, "expect EOF event")
      count = count + 1
    end
    assert_equal(count, 1)
    assert(p1:close())
    assert(kfd:close())
  end,
  test_kqueue_write = function()
    local kfd = assert(S.kqueue("cloexec, nosigpipe"))
    local p1, p2 = assert(S.pipe())
    local kevs = t.kevents{{fd = p2, filter = "write", flags = "add"}}
    assert(kfd:kevent(kevs, nil))
    local count = 0
    for k, v in assert(kfd:kevent(nil, kevs, 0)) do
      assert(v.size > 0) -- size will be amount free in buffer
      count = count + 1
    end
    assert_equal(count, 1) -- one event
    assert(p1:close()) -- close read end
    count = 0
    for k, v in assert(kfd:kevent(nil, kevs, 0)) do
      assert(v.EOF, "expect EOF event")
      count = count + 1
    end
    assert_equal(count, 1)
    assert(p2:close())
    assert(kfd:close())
  end,
  test_kqueue_timer = function()
    local kfd = assert(S.kqueue("cloexec, nosigpipe"))
    local kevs = t.kevents{{ident = 0, filter = "timer", flags = "add, oneshot", data = 10}}
    assert(kfd:kevent(kevs, nil))
    local count = 0
    for k, v in assert(kfd:kevent(nil, kevs, 1)) do -- 1s timeout, longer than 10ms timer interval
      assert_equal(v.size, 1) -- count of expiries is 1 as oneshot
      count = count + 1
    end
    assert_equal(count, 1) -- will have expired by now
    assert(kfd:close())
  end,
}

test.misc_bsd = {
  test_issetugid = function()
    local res = assert(S.issetugid())
    assert(res == 0 or res == 1) -- some tests call setuid so might be tainted
  end,
  test_mknod_64bit_root = function()
    local dev = t.device(1999875, 515)
    assert(dev.dev > t.dev(0xffffffff))
    assert(S.mknod(tmpfile, "fchr,0666", dev))
    local stat = assert(S.stat(tmpfile))
    assert(stat.ischr, "expect to be a character device")
    assert_equal(stat.rdev.major, dev.major)
    assert_equal(stat.rdev.minor, dev.minor)
    assert_equal(stat.rdev.device, dev.device)
    assert(S.unlink(tmpfile))
  end,
}

--[[ -- need to do in a thread as cannot exit
test.misc_bsd_root = {
  test_fchroot = function()
    local fd = assert(S.open("/", "rdonly"))
    assert(fd:chroot())
    assert(fd:close())
  end,
}
]]

test.ktrace = {
  teardown = clean,
  test_ktrace = function()
    local fd = assert(S.open(tmpfile, "creat, trunc, rdwr", "0666"))
    local pid = S.getpid()
    local kfd = assert(S.kqueue())
    local kevs = t.kevents{{fd = fd, filter = "vnode", flags = "add, enable, clear", fflags = "extend"}}
    assert(kfd:kevent(kevs, nil))
    assert(S.ktrace(tmpfile, "set", "syscall, sysret", pid))
    -- now do something that should be in trace
    assert_equal(pid, S.getpid())
    assert(S.ktrace(tmpfile, "clear", "syscall, sysret", pid))
    assert(kfd:kevent(nil, kevs, 1)) -- block until extend
    local buf = t.buffer(4096)
    local n = assert(fd:read(buf, 4096))
    local syscall, sysret = {}, {} -- on real OS luajit may do some meory allocations so may be extra calls occasionally
    for _, ktr in util.kdump(buf, n) do
      assert_equal(ktr.pid, pid)
      if ktr.typename == "SYSCALL" then
        syscall[ktr.values.name] = true
      elseif ktr.typename == "SYSRET" then
        sysret[ktr.values.name] = true
        if ktr.values.name == "getpid" then assert_equal(tonumber(ktr.values.retval), S.getpid()) end
      end
    end
    assert(syscall.getpid, "expect call getpid")
    assert(sysret.getpid, "expect return from getpid")
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_fktrace = function()
    local p1, p2 = assert(S.pipe())
    local pid = S.getpid()
    assert(p2:ktrace("set", "syscall, sysret", pid))
    -- now do something that should be in trace
    assert_equal(pid, S.getpid())
    local ok, err = S.open("/thisfiledoesnotexist", "rdonly")
    local ok, err = S.ioctl(-1, "TIOCMGET")
    assert(p2:ktrace("clear", "syscall, sysret", pid))
    local buf = t.buffer(4096)
    local n = assert(p1:read(buf, 4096))
    local syscall, sysret = {}, {}
    for _, ktr in util.kdump(buf, n) do
      assert_equal(ktr.pid, pid)      assert_equal(ktr.pid, pid)
      if ktr.typename == "SYSCALL" then
        syscall[ktr.values.name] = true
      elseif ktr.typename == "SYSRET" then
        sysret[ktr.values.name] = true
        if ktr.values.name == "open" then assert(ktr.values.error.NOENT) end
        if ktr.values.name == "ioctl" then assert(ktr.values.error.BADF) end
      end
    end
    assert(syscall.getpid and sysret.getpid, "expect getpid")
    assert(syscall.open and sysret.open, "expect open")
    assert(syscall.ioctl and sysret.ioctl, "expect open")
    assert(p1:close())
    assert(p2:close())
  end,
}

return test

end

return {init = init}

