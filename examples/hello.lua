-- this is a hello world example

package.path = "" -- never load from file system
package.cpath = "" -- never load from file system

local S = require "syscall"

S.stdout:write("Hello world from " .. S.abi.os .. "\n")

local jit = require "jit"
jit.on()

-- run some tests
local oldassert = assert
local function assert(cond, s)
  collectgarbage("collect") -- force gc, to test for bugs
  return oldassert(cond, tostring(s)) -- annoyingly, assert does not call tostring!
end

local fd, err = S.open("/tmp/file/does/not/exist", "rdonly")
assert(err, "expected open to fail on file not found")
assert(err.NOENT, "expect NOENT from open non existent file")
print("file not exists test OK")

assert(S.access("/dev/null", "r"), "expect access to say can read /dev/null")
assert(S.access("/dev/null", S.c.OK.R), "expect access to say can read /dev/null")
assert(S.access("/dev/null", "w"), "expect access to say can write /dev/null")
assert(not S.access("/dev/null", "x"), "expect access to say cannot execute /dev/null")
print("access test OK")

S.stderr:write("So long and thanks for all the fish\n")

