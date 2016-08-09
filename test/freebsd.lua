-- BSD specific tests

local function init(S)

local helpers = require "test.helpers"
local types = S.types
local c = S.c
local abi = S.abi

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

test.freebsd_unix_at = {
  teardown = clean,
  test_bindat = function()
    if not S.bindat then error "skipped" end
    local s = assert(S.socket("unix", "stream"))
    local sa = t.sockaddr_un(tmpfile)
    assert(s:bindat("fdcwd", sa))
    assert(s:close())
    assert(S.unlink(tmpfile))
  end,
  test_connectat = function()
    if not S.connectat then error "skipped" end
    local s1 = assert(S.socket("unix", "stream"))
    local sa = t.sockaddr_un(tmpfile)
    assert(s1:bindat("fdcwd", sa))
    assert(s1:listen())
    local s2 = assert(S.socket("unix", "stream"))
    assert(s2:connectat("fdcwd", sa))
    assert(s1:close())
    assert(S.unlink(tmpfile))
  end,
}

test.freebsd_shm = {
  test_shm_anon = function()
    local fd = assert(S.shm_open(c.SHM.ANON, "rdwr, creat"))
    assert(fd:truncate(4096))
    assert(fd:close())
  end,
}

test.freebsd_procdesc = {
  test_procdesc = function()
    if not S.pdfork then error "skipped" end
    local pid, err, pfd = S.pdfork()
    if not pid and err.NOSYS then error "skipped" end -- seems to fail on freebsd9
    assert(pid, err)
    if pid == 0 then -- child
      S.pause()
      S.exit()
    else -- parent
      assert_equal(assert(pfd:pdgetpid()), pid)
      assert(pfd:pdkill("term"))
      local pev = t.pollfds{{fd = pfd, events = "hup"}} -- HUP is process termination
      local p = assert(S.poll(pev, -1))
      assert_equal(p, 1)
      pfd:close()
    end
  end,
}

-- this is available as a patch for Linux, so these tests could be ported
test.capsicum = {
  test_cap_sandboxed_not = function()
    if not S.cap_sandboxed then error "skipped" end
    assert(not S.cap_sandboxed())
  end,
  test_cap_enter = function()
    if not S.cap_sandboxed then error "skipped" end
    assert(not S.cap_sandboxed())
    local pid = assert(S.fork())
    if pid == 0 then -- child
      fork_assert(S.cap_enter())
      fork_assert(S.cap_sandboxed())
      local ok, err = S.open("/dev/null", "rdwr") -- all filesystem access should be disallowed
      fork_assert(not ok and err.CAPMODE)
      S.exit(23)
    else -- parent
      local rpid, status = assert(S.waitpid(pid))
      assert(status.WIFEXITED, "process should have exited normally")
      assert(status.EXITSTATUS == 23, "exit should be 23")
    end
    assert(not S.cap_sandboxed())
  end,
}

return test

end

return {init = init}

