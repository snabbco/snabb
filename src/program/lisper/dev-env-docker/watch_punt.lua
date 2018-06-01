#!snabb/src/snabb snsh
io.stdout:setvbuf'no'
io.stderr:setvbuf'no'

local function assert(v, ...)
   if v then return v, ... end
   error(tostring((...)), 2)
end

local ffi = require("ffi")
local S   = require("syscall")
local _   = string.format

local file = "lispers.net-itr"

S.signal('pipe', 'ign') --I 💔 Linux

local sock = assert(S.socket("unix", "dgram, nonblock"))
S.unlink(file)
local sa = S.t.sockaddr_un(file)
assert(sock:bind(sa))

local bufsz = 10240
local buf = ffi.new('uint8_t[?]', bufsz)
while true do
   if assert(S.select({readfds = {sock}}, 0)).count == 1 then
      local len, err = S.read(sock, buf, bufsz)
      if len then
         if len > 0 then
            print(ffi.string(buf, len))
         end
      else
         print(err)
      end
   end
   S.sleep(1/1000)
end
