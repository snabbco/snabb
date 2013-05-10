-- test suite for ljsyscall.

local strict = require "test.strict"

local S = require "syscall"
local helpers = require "syscall.helpers"
local types = require "syscall.types"
local c = require "syscall.constants"
local abi = require "syscall.abi"

local bit = require "bit"
local ffi = require "ffi"

require("test." .. abi.os) -- OS specific tests

local t, pt, s = types.t, types.pt, types.s

setmetatable(S, {__index = function(i, k) error("bad index access on S: " .. k) end})

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
    assert(tostring(err) == "No error information (error 0)", "should get missing error message")
  end,
  test_no_missing_error_strings = function()
    local noerr = "No error information"
    for k, v in pairs(c.E) do
      local msg = assert(tostring(t.error(v)))
      assert(msg:sub(1, #noerr) ~= noerr, "no error message for " .. k)
    end
  end,
  test_booltoc = function()
    assert_equal(helpers.booltoc(true), 1)
    assert_equal(helpers.booltoc[true], 1)
    assert_equal(helpers.booltoc[0], 0)
  end,
  test_constants = function()
    assert_equal(c.F.GETFD, c.F.getfd) -- test can use upper and lower case
    assert_equal(c.F.GETFD, c.F.getFD) -- test can use mixed case
    assert(rawget(c.F, "GETFD"))
    assert(not rawget(c.F, "getfd"))
    assert(rawget(getmetatable(c.F).__index, "getfd")) -- a little implementation dependent
  end,
  test_at_flags = function()
    assert_equal(c.AT_FDCWD[nil], c.AT_FDCWD.FDCWD) -- nil returns current dir
    assert_equal(c.AT_FDCWD.fdcwd, c.AT_FDCWD.FDCWD)
    local fd = t.fd(-1)
    assert_equal(c.AT_FDCWD[fd], -1)
    assert_equal(c.AT_FDCWD[33], 33)
  end,
}

-- note at present we check for uid 0, but could check capabilities instead.
if S.geteuid() == 0 then
  if abi.os == "linux" then
  -- some tests are causing issues, eg one of my servers reboots on pivot_root
  if not arg[1] and arg[1] ~= "all" then
    test_misc_root.test_pivot_root = nil
  elseif arg[1] == "all" then
    arg[1] = nil
  end

  -- cut out this section if you want to (careful!) debug on real interfaces
  -- TODO add to features as may not be supported
  assert(S.unshare("newnet, newns, newuts"), "tests as root require kernel namespaces") -- do not interfere with anything on host during tests
  local nl = require "linux.nl"
  local i = assert(nl.interfaces())
  local lo = assert(i.lo)
  assert(lo:up())
  assert(S.mount("none", "/sys", "sysfs"))
  else -- not Linux
    -- run all tests, no namespaces available
  end
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
-- TODO add more files, this is not very applicable since code made modular

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



