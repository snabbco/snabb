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

local function assert(cond, s, ...)
  collectgarbage("collect") -- force gc, to test for bugs
  if cond == nil then error(tostring(s)) end -- annoyingly, assert does not call tostring!
  return cond, s, ...
end

local function fork_assert(cond, str) -- if we have forked we need to fail in main thread not fork
  if not cond then
    print(tostring(str))
    print(debug.traceback())
    S.exit("failure")
  end
  return cond, str
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
    if not (abi.rump or abi.xen) then assert(err and err.PERM, "non append write should fail") end -- TODO I think this is due to tmpfs mount??
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
    if not (abi.rump or abi.xen) then assert(err and err.PERM, "non append write should fail") end -- TODO I think this is due to tmpfs mount??
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
    if not (abi.rump or abi.xen) then assert(err and err.PERM, "non append write should fail") end -- TODO I think this is due to tmpfs mount??
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
    local p = assert(S.pipe("nosigpipe"))
    assert(p[1]:close())
    local ok, err = p[2]:write("other end closed")
    assert(not ok and err.PIPE, "should get EPIPE")
    assert(p:close())
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
    local pipe = S.pipe()
    local kevs = t.kevents{{fd = pipe[1], filter = "read", flags = "add"}}
    assert(kfd:kevent(kevs, nil))
    local a, b, n = assert(kfd:kevent(nil, kevs, 0))
    assert_equal(n, 0) -- no events yet
    local str = "test"
    pipe:write(str)
    local count = 0
    for k, v in assert(kfd:kevent(nil, kevs, 0)) do
      assert_equal(v.size, #str) -- size will be amount available to read
      count = count + 1
    end
    assert_equal(count, 1) -- 1 event readable now
    local r, err = pipe:read()
    local _, _, n = assert(kfd:kevent(nil, kevs, 0))
    assert_equal(n, 0) -- no events any more
    assert(pipe[2]:close())
    local count = 0
    for k, v in assert(kfd:kevent(nil, kevs, 0)) do
      assert(v.EOF, "expect EOF event")
      count = count + 1
    end
    assert_equal(count, 1)
    assert(pipe:close())
    assert(kfd:close())
  end,
  test_kqueue_write = function()
    local kfd = assert(S.kqueue("cloexec, nosigpipe"))
    local pipe = S.pipe()
    local kevs = t.kevents{{fd = pipe[2], filter = "write", flags = "add"}}
    assert(kfd:kevent(kevs, nil))
    local count = 0
    for k, v in assert(kfd:kevent(nil, kevs, 0)) do
      assert(v.size > 0) -- size will be amount free in buffer
      count = count + 1
    end
    assert_equal(count, 1) -- one event
    assert(pipe[1]:close()) -- close read end
    count = 0
    for k, v in assert(kfd:kevent(nil, kevs, 0)) do
      assert(v.EOF, "expect EOF event")
      count = count + 1
    end
    assert_equal(count, 1)
    assert(pipe:close())
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
    assert_equal(S.issetugid(), 0) -- assume luajit not suid
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

return test

end

return {init = init}

