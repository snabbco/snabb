-- rump specific tests
-- in particular testing the threading, as that is rather different

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
}

return test

end

return {init = init}

