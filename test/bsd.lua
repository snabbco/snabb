-- General BSD tests

local function init(S)

local helpers = require "syscall.helpers"
local types = S.types
local c = S.c
local abi = S.abi

local bit = require "syscall.bit"
local ffi = require "ffi"

local t, pt, s = types.t, types.pt, types.s

local function assert(cond, err, ...)
  collectgarbage("collect") -- force gc, to test for bugs
  if cond == nil then error(tostring(err)) end -- annoyingly, assert does not call tostring!
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

test.bsd_ids = {
  test_issetugid = function()
    if not S.issetugid then error "skipped" end
    local res = assert(S.issetugid())
    assert(res == 0 or res == 1) -- some tests call setuid so might be tainted
  end,
}

test.filesystem_bsd = {
  test_revoke = function()
    local fd = assert(S.posix_openpt("rdwr, noctty"))
    assert(fd:grantpt())
    assert(fd:unlockpt())
    local pts_name = assert(fd:ptsname())
    local pts = assert(S.open(pts_name, "rdwr, noctty"))
    assert(S.revoke(pts_name))
    local n, err = pts:read()
    assert(not n and err.BADF, "access should be revoked")
    assert(pts:close())
    assert(fd:close())
  end,
  test_chflags = function()
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(fd:write("append"))
    assert(S.chflags(tmpfile, "uf_append"))
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
    assert(S.lchflags(tmpfile, "uf_append"))
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
    assert(fd:chflags("uf_append"))
    assert(fd:write("append"))
    assert(fd:seek(0, "set"))
    local n, err = fd:write("not append")
    if not (S.__rump or abi.xen) then assert(err and err.PERM, "non append write should fail") end -- TODO I think this is due to tmpfs mount??
    assert(fd:chflags()) -- clear flags
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_chflagsat = function()
    if not S.chflagsat then error "skipped" end
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(fd:write("append"))
    assert(S.chflagsat("fdcwd", tmpfile, "uf_append", "symlink_nofollow"))
    assert(fd:write("append"))
    assert(fd:seek(0, "set"))
    local n, err = fd:write("not append")
    assert(err and err.PERM, "non append write should fail")
    assert(S.chflagsat("fdcwd", tmpfile)) -- clear flags
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
  test_lchmod = function()
    if not S.lchmod then error "skipped" end
    local fd = assert(S.creat(tmpfile, "RWXU"))
    assert(S.lchmod(tmpfile, "RUSR, WUSR"))
    assert(S.access(tmpfile, "rw"))
    assert(S.unlink(tmpfile))
    assert(fd:close())
  end,
}

test.kqueue = {
  test_kqueue_vnode = function()
    local kfd = assert(S.kqueue())
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
    local kfd = assert(S.kqueue())
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
    local kfd = assert(S.kqueue())
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
    local kfd = assert(S.kqueue())
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

test.bsd_extattr = {
  teardown = clean,
  test_extattr_empty_fd = function()
    if not S.extattr_get_fd then error "skipped" end
    local fd = assert(S.creat(tmpfile, "rwxu"))
    assert(S.unlink(tmpfile))
    local n, err = fd:extattr_get("user", "myattr", false) -- false does raw call with no buffer to return length
    assert(not n and err.NOATTR)
    assert(fd:close())
  end,
  test_extattr_getsetdel_fd = function()
    if not S.extattr_get_fd then error "skipped" end
    local fd = assert(S.creat(tmpfile, "rwxu"))
    assert(S.unlink(tmpfile))
    local n, err = fd:extattr_get("user", "myattr", false) -- false does raw call with no buffer to return length
    assert(not n and err.NOATTR)
    local n, err = fd:extattr_set("user", "myattr", "myvalue")
    if not n and err.OPNOTSUPP then error "skipped" end -- fs does not support setting extattr
    assert(n, err)
    assert_equal(n, #"myvalue")
    local str = assert(fd:extattr_get("user", "myattr"))
    assert_equal(str, "myvalue")
    local ok = assert(fd:extattr_delete("user", "myattr"))
    local str, err = fd:extattr_get("user", "myattr")
    assert(not str and err.NOATTR)
    assert(fd:close())
  end,
  test_extattr_getsetdel_file = function()
    if not S.extattr_get_fd then error "skipped" end
    local fd = assert(S.creat(tmpfile, "rwxu"))
    assert(fd:close())
    local n, err = S.extattr_get_file(tmpfile, "user", "myattr", false) -- false does raw call with no buffer to return length
    assert(not n and err.NOATTR)
    local n, err = S.extattr_set_file(tmpfile, "user", "myattr", "myvalue")
    if not n and err.OPNOTSUPP then error "skipped" end -- fs does not support setting extattr
    assert(n, err)
    assert_equal(n, #"myvalue")
    local str = assert(S.extattr_get_file(tmpfile, "user", "myattr"))
    assert_equal(str, "myvalue")
    local ok = assert(S.extattr_delete_file(tmpfile, "user", "myattr"))
    local str, err = S.extattr_get_file(tmpfile, "user", "myattr")
    assert(not str and err.NOATTR)
    assert(S.unlink(tmpfile))
  end,
  test_extattr_getsetdel_link = function()
    if not S.extattr_get_fd then error "skipped" end
    assert(S.symlink(tmpfile2, tmpfile))
    local n, err = S.extattr_get_link(tmpfile, "user", "myattr", false) -- false does raw call with no buffer to return length
    assert(not n and err.NOATTR)
    local n, err = S.extattr_set_link(tmpfile, "user", "myattr", "myvalue")
    if not n and err.OPNOTSUPP then error "skipped" end -- fs does not support setting extattr
    assert(n, err)
    assert_equal(n, #"myvalue")
    local str = assert(S.extattr_get_link(tmpfile, "user", "myattr"))
    assert_equal(str, "myvalue")
    local ok = assert(S.extattr_delete_link(tmpfile, "user", "myattr"))
    local str, err = S.extattr_get_link(tmpfile, "user", "myattr")
    assert(not str and err.NOATTR)
    assert(S.unlink(tmpfile))
  end,
  test_extattr_list_fd = function()
    if not S.extattr_list_fd then error "skipped" end
    local fd = assert(S.creat(tmpfile, "rwxu"))
    assert(S.unlink(tmpfile))
    local attrs, err = fd:extattr_list("user")
    if not attrs and err.OPNOTSUPP then error "skipped" end -- fs does not support extattr
    assert(attrs, err)
    assert_equal(#attrs, 0)
    assert(fd:extattr_set("user", "myattr", "myvalue"))
    local attrs = assert(fd:extattr_list("user"))
    assert_equal(#attrs, 1)
    assert_equal(attrs[1], "myattr")
    assert(fd:extattr_set("user", "newattr", "newvalue"))
    local attrs = assert(fd:extattr_list("user"))
    assert_equal(#attrs, 2)
    assert((attrs[1] == "myattr" and attrs[2] == "newattr") or (attrs[2] == "myattr" and attrs[1] == "newattr"))
    assert(fd:close())
  end,
  test_extattr_list_file = function()
    if not S.extattr_list_file then error "skipped" end
    local fd = assert(S.creat(tmpfile, "rwxu"))
    local attrs, err = S.extattr_list_file(tmpfile, "user")
    if not attrs and err.OPNOTSUPP then error "skipped" end -- fs does not support extattr
    assert(attrs, err)
    assert_equal(#attrs, 0)
    assert(S.extattr_set_file(tmpfile, "user", "myattr", "myvalue"))
    local attrs = assert(S.extattr_list_file(tmpfile, "user"))
    assert_equal(#attrs, 1)
    assert_equal(attrs[1], "myattr")
    assert(S.extattr_set_file(tmpfile, "user", "newattr", "newvalue"))
    local attrs = assert(S.extattr_list_file(tmpfile, "user"))
    assert_equal(#attrs, 2)
    assert((attrs[1] == "myattr" and attrs[2] == "newattr") or (attrs[2] == "myattr" and attrs[1] == "newattr"))
    assert(S.unlink(tmpfile))
  end,
  test_extattr_list_link = function()
    if not S.extattr_list_file then error "skipped" end
    assert(S.symlink(tmpfile2, tmpfile))
    local attrs, err = S.extattr_list_link(tmpfile, "user")
    if not attrs and err.OPNOTSUPP then error "skipped" end -- fs does not support extattr
    assert(attrs, err)
    assert_equal(#attrs, 0)
    assert(S.extattr_set_link(tmpfile, "user", "myattr", "myvalue"))
    local attrs = assert(S.extattr_list_link(tmpfile, "user"))
    assert_equal(#attrs, 1)
    assert_equal(attrs[1], "myattr")
    assert(S.extattr_set_link(tmpfile, "user", "newattr", "newvalue"))
    local attrs = assert(S.extattr_list_link(tmpfile, "user"))
    assert_equal(#attrs, 2)
    assert((attrs[1] == "myattr" and attrs[2] == "newattr") or (attrs[2] == "myattr" and attrs[1] == "newattr"))
    assert(S.unlink(tmpfile))
  end,
  test_extattr_list_long = function()
    if not S.extattr_list_fd then error "skipped" end
    local fd = assert(S.creat(tmpfile, "rwxu"))
    assert(S.unlink(tmpfile))
    local attrs, err = fd:extattr_list("user")
    if not attrs and err.OPNOTSUPP then error "skipped" end -- fs does not support extattr
    assert(attrs, err)
    assert_equal(#attrs, 0)
    local count = 100
    for i = 1, count do
      assert(fd:extattr_set("user", "myattr" .. i, "myvalue"))
    end
    local attrs = assert(fd:extattr_list("user"))
    assert_equal(#attrs, count)
    assert(fd:close())
  end,
}

-- skip as no processes in rump
if not S.__rump then
  test.kqueue.test_kqueue_proc = function()
    local pid = assert(S.fork())
    if pid == 0 then -- child
      S.pause()
      S.exit()
    else -- parent
      local kfd = assert(S.kqueue())
      local kevs = t.kevents{{ident = pid, filter = "proc", flags = "add", fflags = "exit, fork, exec"}}
      assert(kfd:kevent(kevs, nil))
      assert(S.kill(pid, "term"))
      local count = 0
      for k, v in assert(kfd:kevent(nil, kevs, 1)) do
        assert(v.EXIT)
        count = count + 1
      end
      assert_equal(count, 1)
      assert(kfd:close())
      assert(S.waitpid(pid))
    end
  end
--[[ -- TODO temporarily disabled until signal functions added to the BSDs
  test.kqueue.test_kqueue_signal = function()
    assert(S.signal("alrm", "ign"))
    local kfd = assert(S.kqueue())
    local kevs = t.kevents{{signal = "alrm", filter = "signal", flags = "add"}}
    assert(kfd:kevent(kevs, nil))
    assert(S.kill(0, "alrm"))
    assert(S.kill(0, "alrm"))
    local count = 0
    for k, v in assert(kfd:kevent(nil, kevs, 1)) do
      assert_equal(v.data, 2) -- event happened twice
      count = count + 1
    end
    assert_equal(count, 1)
    assert(S.signal("alrm", "dfl"))
  end
]]
end

return test

end

return {init = init}

