-- simple epoll-based socket example. Serves up http responses, but is of course not a proper server
-- you can test performance iwth ab -n 100000 -c 100 http://localhost:8000/ although ab may be the limiting factor

local S = require "syscall"

local t, c = S.t, S.c

local oldassert = assert
function assert(c, s)
  return oldassert(c, tostring(s)) -- annoyingly, assert does not call tostring!
end

local s = assert(S.socket("inet", "stream, nonblock"))

s:setsockopt("socket", "reuseaddr", true)

local sa = assert(t.sockaddr_in(8000, "127.0.0.1"))

assert(s:bind(sa))

assert(s:listen(128))

local ep = assert(S.epoll_create())

assert(ep:epoll_ctl("add", s, "in"))

local w = {}

local msg = [[
<html>
<head>
<title>performance test</title>
</head>
<body>
test
</body>
</html>
]]

local reply = table.concat({
"HTTP/1.0 200 OK",
"Content-type: text/html",
"Connection: close",
"Content-Length: " .. #msg,
"",
"",
}, "\r\n") .. msg

local maxevents = 1024
local events = t.epoll_events(maxevents)

local bufsize = 4096
local buffer = t.buffer(bufsize)

local ss = t.sockaddr_storage()
local addrlen = t.socklen1(#ss)

local event = t.epoll_event()

while true do

local r = assert(ep:epoll_wait(events, maxevents))

for i = 1, #r do
  local ev = r[i]
  if ev.fd == s.filenum then -- server socket, accept
    repeat
      local a, err = s:accept("nonblock", ss, addrlen)
      if a then
        event.events = c.EPOLL.IN
        event.data.fd = a.fd:getfd()
        assert(ep:epoll_ctl("add", a.fd, event))
        w[a.fd:getfd()] = a.fd
      end
    until not a
  else
    local fd = w[ev.fd]
    if ev.HUP or ev.ERR then -- closed or error
      fd:close()
      w[ev.fileno] = nil
    else
      if ev.IN then
        local n
        fd:read(buffer, bufsize)
        n = fd:write(reply)
        assert(n == #reply)
        assert(fd:close())
        w[ev.fd] = nil
      end
    end
  end
end


end


