-- BSD specific tests

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

test.freebsd_unix_at = {
  teardown = clean,
  test_bindat = function()
    local s = assert(S.socket("unix", "stream"))
    local sa = t.sockaddr_un(tmpfile)
    assert(S.bindat("fdcwd", sa))
    assert(s:close())
    assert(S.unlink(tmpfile))
  end,
  test_connectat = function()
    local s1 = assert(S.socket("unix", "stream"))
    local sa = t.sockaddr_un(tmpfile)
    assert(S.bindat("fdcwd", sa))
    local s2 = assert(S.socket("unix", "stream"))
    assert(S.connectat("fdcwd", s2, tmpfile))
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

return test

end

return {init = init}

