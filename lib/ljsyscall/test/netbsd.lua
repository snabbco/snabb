-- BSD specific tests

local function init(S)

local helpers = require "test.helpers"
local types = S.types
local c = S.c
local abi = S.abi
local features = S.features
local util = S.util

local bit = require "syscall.bit"
local ffi = require "ffi"

local t, pt, s = types.t, types.pt, types.s

local assert = helpers.assert

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

test.mount_netbsd_root = {
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

test.network_utils_netbsd_root = {
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
  test_ifaddr_inet4 = function()
    local ifname = "lo8" .. tostring(S.getpid())
    assert(util.ifcreate(ifname))
    assert(util.ifup(ifname))
    assert(util.ifaddr_inet4(ifname, "127.1.0.1/24")) -- TODO fail gracefully if no ipv4 support
    -- TODO need read functionality to test it worked correctly
    assert(util.ifdown(ifname))
    assert(util.ifdestroy(ifname))
  end,
  test_ifaddr_inet6 = function()
    local ifname = "lo8" .. tostring(S.getpid())
    assert(util.ifcreate(ifname))
    assert(util.ifup(ifname))
    assert(util.ifaddr_inet6(ifname, "fd97:fab9:44c2::1/48")) -- TODO this is my private registration (SIXXS), should be random
    -- TODO need read functionality to test it worked correctly
    assert(util.ifdown(ifname))
    assert(util.ifdestroy(ifname))
  end,
}

test.sockets_pipes_netbsd = {
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

test.misc_netbsd = {
  teardown = clean,
--[[ -- should not be using major, minor as not defined over 32 bit, plus also ffs does not support
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
]]
  test_fsync_range = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(fd:sync_range("data", 0, 4096))
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_pollts = function()
    local a, b = assert(S.socketpair("unix", "stream"))
    local pev = t.pollfds{{fd = a, events = c.POLL.IN}}
    local p = assert(S.pollts(pev, 0, nil))
    assert_equal(p, 0) -- no events yet
    for k, v in ipairs(pev) do
      assert_equal(v.fd, a:getfd())
      assert_equal(v.revents, 0)
    end
    assert(b:write(teststring))
    local p = assert(S.pollts(pev, nil, "alrm"))
    assert_equal(p, 1) -- 1 event
    for k, v in ipairs(pev) do
      assert_equal(v.fd, a:getfd())
      assert(v.IN, "IN event now")
    end
    assert(a:read())
    assert(b:close())
    assert(a:close())
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
    collectgarbage()
    collectgarbage("stop")
    assert(S.ktrace(tmpfile, "set", "syscall, sysret", pid))
    -- now do something that should be in trace
    assert_equal(pid, S.getpid())
    assert(S.ktrace(tmpfile, "clear", "syscall, sysret", pid))
    S.nanosleep(0.05) -- can be flaky and only get one event otherwise, TODO not clear needed?
    assert(kfd:kevent(nil, kevs)) -- block until extend
    collectgarbage("restart")
    local buf = t.buffer(4096)
    local n = assert(fd:read(buf, 4096))
    local syscall, sysret = {}, {} -- on real OS luajit may do some memory allocations so may be extra calls occasionally
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
    S.nanosleep(0.01) -- can be flaky and only get one event otherwise
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

test.ksem = {
  test_ksem_init = function()
    local sem = assert(S.ksem_init(3))
    assert(S.ksem_destroy(sem))
  end,
}

return test

end

return {init = init}

