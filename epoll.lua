local S = require "syscall"

local t = S.t

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

assert(ep:epoll_ctl("add", s, "in")) -- actually dont need to set err, hup

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

local reply = [[
HTTP/1.0 200 OK
Content-type: text/html
Connection: close
Content-Length: ]] .. #msg .. [[


]] .. msg

local maxevents = 1024
local events = t.epoll_events(maxevents)

local bufsize = 4096
local buffer = t.buffer(bufsize)

local ss = t.sockaddr_storage()
local addrlen = t.socklen1(S.s.sockaddr_storage)

local event = t.epoll_event()

while true do

local r = assert(ep:epoll_wait(events, maxevents))

for i = 1, #r do
  local ev = r[i]
  if ev.fileno == s.filenum then -- server socket, accept
    repeat
      local a, err = s:accept("nonblock", ss, addrlen)
      if a then
        event.events = S.EPOLLIN
        event.data.fd = a.fd.filenum
        assert(ep:epoll_ctl("add", a.fd, event))
        w[a.fd.filenum] = a.fd
      end
    until not a
  else
    local fd = w[ev.fileno]
    if ev.EPOLLHUP or ev.EPOLLERR then -- closed or error
      fd:close()
      w[ev.fileno] = nil
    else
      if ev.EPOLLIN then
        local n
        fd:read(buffer, bufsize)
        n = fd:write(reply)
        assert(n == #reply)
        assert(fd:close())
        w[ev.fileno] = nil
      end
    end
  end
end


end


