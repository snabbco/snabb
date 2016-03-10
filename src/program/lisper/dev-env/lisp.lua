#!snabb/src/snabb snsh
io.stdout:setvbuf'no'
io.stderr:setvbuf'no'

--LISP controller mock-up program for testing.

local function assert(v, ...)
   if v then return v, ... end
   error(tostring((...)), 2)
end

local ffi = require("ffi")
local S   = require("syscall")
local _   = string.format

local LISP_N       = os.getenv("LISP_N") or ""
local CONTROL_SOCK = "/var/tmp/lisp-ipc-map-cache"..LISP_N
local PUNT_SOCK    = "/var/tmp/lispers.net-itr"..LISP_N

S.signal('pipe', 'ign') --I 💔 Linux

local sock
::retry::
sock = sock or assert(S.socket("unix", "dgram, nonblock"))
local sa = S.t.sockaddr_un(CONTROL_SOCK)
local ok, err = sock:connect(sa)
if not ok then
   if err.CONNREFUSED or err.AGAIN or err.NOENT then
      S.sleep(1)
      print'retrying...'
      goto retry
   end
   assert(nil, err)
end
print'connected'

while true do
   if assert(S.select({writefds = {sock}}, 0)).count == 1 then

      local t = {}
      for s in io.lines('lisp'..LISP_N..'.fib') do
         table.insert(t, s)
      end

      print'sending...'
      for i,s in ipairs(t) do
         if not S.write(sock, s, #s) then
            print'write error'
            sock:close()
            sock = nil
            goto retry
         end
      end
   end
   S.sleep(10)
end
