-- rump specific tests
-- in particular testing the threading, as that is rather different; you can map them to host threads how you like

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
  if cond == nil then error(tostring(err)) end -- annoyingly, assert does not call tostring!
  if type(cond) == "function" then return cond, err, ... end
  if cond == true then return ... end
  return cond, ...
end

local function assert_equal(...)
  collectgarbage("collect") -- force gc, to test for bugs
  return assert_equals(...)
end

local test = {}

test.rump_threads = {
  test_create_thread = function()
    local pid = assert(S.getpid())
    assert(S.rump.newlwp(pid))
    local lwp1 = assert(S.rump.curlwp(), "should get a pointer back")
    S.rump.releaselwp()
  end,
  test_switch_threads = function()
    local pid = S.getpid()
    assert(S.rump.newlwp(pid))
    local lwp1 = assert(S.rump.curlwp(), "should get a pointer back")
    assert(S.rump.newlwp(pid))
    local lwp2 = assert(S.rump.curlwp(), "should get a pointer back")
    S.rump.switchlwp(lwp1)
    S.rump.switchlwp(lwp2)
    S.rump.switchlwp(lwp1)
    S.rump.releaselwp()
    lwp1 = nil
    S.rump.switchlwp(lwp2)
    S.rump.releaselwp()
    lwp2 = nil
  end,
  test_rfork = function()
    local pid1 = S.getpid()
    local origlwp = S.rump.curlwp() -- will probably be null as we are initially running in implicit context
    local fd = assert(S.open("/dev/zero", "rdonly"))
    assert(fd:read()) -- readable
    assert(S.rump.rfork("CFDG")) -- no shared fds
    local pid2 = S.getpid()
    assert(pid1 ~= pid2, "should have new pid")
    local n, err = fd:read() -- should not be able to read this fd
    assert(not n and err, "should not be able to access an fd")
    S._exit() -- exit this process
    S.rump.switchlwp(origlwp) -- probably back to implicit context
    assert_equal(pid1, S.getpid())
    assert(fd:read()) -- should be able to read /dev/zero now
  end,
}

return test

end

return {init = init}

