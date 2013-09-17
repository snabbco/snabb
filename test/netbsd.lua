-- BSD specific tests

local function init(S)

local helpers = require "syscall.helpers"
local types = S.types
local c = S.c
local abi = S.abi
local features = S.features
local util = S.util

local bit = require "bit"
local ffi = require "ffi"

local t, pt, s = types.t, types.pt, types.s

local oldassert = assert
local function assert(cond, s)
  collectgarbage("collect") -- force gc, to test for bugs
  return oldassert(cond, tostring(s)) -- annoyingly, assert does not call tostring!
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
    assert(S.mount{dir=tmpfile, type="kernfs"})
    assert(S.unmount(tmpfile))
    assert(S.rmdir(tmpfile))
  end,
  test_mount_tmpfs = function()
    assert(S.mkdir(tmpfile))
    local data = {ta_version = 1, ta_nodes_max=100, ta_size_max=1048576, ta_root_mode=helpers.octal("0700")}
    assert(S.mount{dir=tmpfile, type="tmpfs", data=data})
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

test.pipes_bsd = {
  test_nosigpipe = function()
    local p = assert(S.pipe("nosigpipe"))
    assert(p[1]:close())
    local ok, err = p[2]:write("other end closed")
    assert(not ok and err.PIPE, "should get EPIPE")
    assert(p:close())
  end,
}

test.kqueue = {
  test_kqueue_vnode = function()
    local kfd = assert(S.kqueue("cloexec, nosigpipe"))
    local fd = assert(S.creat(tmpfile, "rwxu"))
    local kevs = t.kevents{{fd = fd, filter = "vnode",
      flags = "add, enable, clear", fflags = "delete, write, extend, attrib, link, rename, revoke"}}
    assert(kfd:kevent(kevs, nil, 0))
    local ret = assert(kfd:kevent(nil, kevs, 0))
    assert_equal(ret, 0) -- no events yet
    assert(S.unlink(tmpfile))
    local ret = assert(kfd:kevent(nil, kevs, 1))
    assert_equal(ret, 1)
    assert(kevs[1].DELETE, "expect delete event")
    assert(fd:write("something"))
    local ret = assert(kfd:kevent(nil, kevs, 1))
    assert_equal(ret, 1)
    assert(kevs[1].WRITE, "expect write event")
    assert(kevs[1].EXTEND, "expect extend event")
    assert(fd:close())
    assert(kfd:close())
  end,
  test_kqueue_read = function()
    local kfd = assert(S.kqueue("cloexec, nosigpipe"))
    local pipe = S.pipe()
    local kevs = t.kevents{{fd = pipe[1], filter = "read", flags = "add"}}
    assert(kfd:kevent(kevs, nil, 0))
    local ret = assert(kfd:kevent(nil, kevs, 0))
    assert_equal(ret, 0) -- no events yet
    local str = "test"
    pipe:write(str)
    local ret = assert(kfd:kevent(nil, kevs, 0))
    assert_equal(ret, 1) -- readable now
    assert_equal(kevs[1].size, #str) -- size will be amount available to read
    local r, err = pipe:read()
    local ret = assert(kfd:kevent(nil, kevs, 0))
    assert_equal(ret, 0) -- no events any more
    assert(pipe[2]:close())
    local ret = assert(kfd:kevent(nil, kevs, 0))
    assert_equal(ret, 1)
    assert(kevs[1].EOF, "expect EOF event")
    assert(pipe:close())
    assert(kfd:close())
  end,
  test_kqueue_write = function()
    local kfd = assert(S.kqueue("cloexec, nosigpipe"))
    local pipe = S.pipe()
    local kevs = t.kevents{{fd = pipe[2], filter = "write", flags = "add"}}
    assert(kfd:kevent(kevs, nil, 0))
    local ret = assert(kfd:kevent(nil, kevs, 0))
    assert_equal(ret, 1) -- writeable already
    assert(kevs[1].size > 0) -- size will be amount free in buffer
    assert(pipe[1]:close()) -- close read end
    local ret = assert(kfd:kevent(nil, kevs, 0))
    assert_equal(ret, 1)
    assert(kevs[1].EOF, "expect EOF event")
    assert(pipe:close())
    assert(kfd:close())
  end,
}

if not (abi.rump or abi.xen) then -- these interfaces not suited to rump
test.kqueue.test_kqueue_timer = function()
    local kfd = assert(S.kqueue("cloexec, nosigpipe"))
    local kevs = t.kevents{{ident = 0, filter = "timer", flags = "add", data = 10}}
    assert(kfd:kevent(kevs, nil, 0))
    local ret = assert(kfd:kevent(nil, kevs, 1)) -- 1s timeout, longer than 10ms timer interval
    assert_equal(ret, 1) -- will have expired by now
    assert(kevs[1].size >= 1, "expect at least one timer expiry, got " .. kevs[1].size)
    assert(kfd:close())
  end
end

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

