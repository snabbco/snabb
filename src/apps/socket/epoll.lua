
--unix socket app: transmit and receive packets through a named socket.
--can be used in server (listening) or client (connecting) mode.

module(...,package.seeall)

local ffi    = require("ffi")
local link   = require("core.link")
local packet = require("core.packet")
local S      = require("syscall")

EPollSocket = {}
EPollSocket.__index = EPollSocket

local modes = {stream = "stream", packet = "dgram"}

function EPollSocket:new (arg)

   --process args
   --args, interface, port
   --args, port
   --args, interface, with default port 8080

   assert(arg, "interface or port expected")
   local interface, port, listen

   interface = "127.0.0.1"
   listen = true
   port = 8080

   if type(arg) == "table" then
      port = arg[2] or port
      interface = arg[1]
   elseif type(arg) == "string" then
      interface = arg
   elseif type(arg) == "number" then
      port = arg
   end

   local t, c = S.t, S.c

   local function assert(cond, s, ...)
      if cond == nil then error(tostring(s)) end -- annoyingly, assert does not call tostring!
      return cond, s, ...
   end
   local function nilf() return nil end

   local maxevents = 1024;
   local mode = "stream"
   --[[
   mode = assert(modes[mode or "stream"], "invalid mode")
   assert(file, "filename expected")
   --]]
   --open/close socket

   --currently only epoll supported.
   assert(S.epoll_create, "no epoll support")

   local poll
   if S.epoll_create then
      poll = {
         init = function(this)
            return setmetatable({fd = assert(S.epoll_create())}, {__index = this})
         end,
         event = t.epoll_event(),
         add = function(this, s)
            local event = this.event
            event.events = c.EPOLL.IN
            event.data.fd = s:getfd()
            assert(this.fd:epoll_ctl("add", s, event))
         end,
         del = function(this, s)
            -- will not running on linux 2.6.9 or lower
            assert(this.fd:epoll_ctl("del", s, nil))
         end,
         events = t.epoll_events(maxevents),
         get = function(this)
            local f, a, r = this.fd:epoll_wait(this.events)
            if not f then
               print("error on fd", a)
               return nilf
            else
               return f, a, r
            end
         end,
         eof = function(ev) return ev.HUP or ev.ERR or ev.RDHUP end,
      }
   end

   local ep, s
   local open, close -- function pointer
   if listen then --server mode
      s = assert(S.socket("inet", mode..", nonblock"))
      s:setsockopt("socket", "reuseaddr", true)

      local sa = assert(t.sockaddr_in(port, interface))

      assert(s:bind(sa))

      if mode == "stream" then
         assert(s:listen(128))      -- 128 is the backlog of accept queue
      end

      ep = poll:init()
      ep:add(s)


      function close()
         sock:close()
         S.unlink(file)
      end

      function open()
         if mode == "dgram" then
            return sock
         end

         local sa = S.t.sockaddr_un()
         local csock, err = sock:accept(sa)
         if not csock then
            if err.AGAIN then return end
            assert(nil, err)
         end
         local close0 = close
         function close()
            csock:close()
            close0()
         end
         return csock
      end
   else
      -- do client mode ?
      assert(nil, "fixme: add socket client support")
   end

   --send/receive packets
   local w = {}

   local sock
   local function connect()
      sock = sock or open()
      return sock
   end

   local function can_send()
      -- do nothing now
      if not connect() then return end
      local t, err = S.select({writefds = {sock}}, 0)
      while not t and (err.AGAIN or err.INTR) do
         t, err = S.select({writefds = {sock}}, 0)
      end
      assert(t, err)
      return t.count == 1
   end

   local function send(p)
      -- do nothing now
      local sz, err = S.write(sock, p.data, p.length)
      assert(sz, err)
      assert(sz == p.length)
   end

   --app object

   local self = setmetatable({ss = t.sockaddr_storage()}, self)

   function self:pull()
      local l = self.output.tx
      if l == nil then return end
      local limit = engine.pull_npackets
      for i, ev in ep:get() do
         if ep.eof(ev) then
            ev.fd:close()
            ep:del(w[ev.fd])
            w[ev.fd] = nil
         end

         if limit == 0 then break end
         limit = limit - 1

         if ev.fd == s:getfd() then
            -- do connect, accept as needed.
            repeat
               local a, err = s:accept(self.ss, nil, "nonblock")
               if a then
                  ep:add(a)
                  w[a:getfd()] = a
               end
            until not a
         else
            local fd = w[ev.fd]
            -- do data receive, make packet
            local p = packet.allocate()
            local maxsz = ffi.sizeof(p.data)
            local len, err = fd:read(p.data, maxsz)
            if len == 0 then return end
            if not len then
               assert(nil, err)
            end
            p.length = len

            -- debug only, make a response
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

            local n = fd:write(reply)
            assert(fd:close())
            w[ev.fd] = nil
            -- debug end.

            if p then
               link.transmit(l, p) --link owns p now so we mustn't free it
            end
         end   -- end if s:getfd
      end   --end for
   end

   function self:push()
      local l = self.input.rx
      if l == nil then return end
      while not link.empty(l) and can_send() do
         local p = link.receive(l) --we own p now so we must free it
         send(p)
         packet.free(p)
      end
   end

   function self:stop()
      local function close_w(i, ev)
         ev.fd:close()
         ep:del(w[ev.fd])
         -- w[ev.fd] = nil    -- no needs manual free ?
      end
      table.foreach(w, close_w)
      w = {}
   end

   return self
end

--[[

function selftest ()

   local printapp = {}
   function printapp:new (name)
      return {
         push = function(self)
            local l = self.input.rx
            if l == nil then return end
            while not link.empty(l) do
               local p = link.receive(l)
               print(name..': ', p.length, ffi.string(p.data, p.length))
               packet.free(p)
            end
         end
      }
   end

   local echoapp = {}
   function echoapp:new (text)
      return {
         pull = function(self)
            local l = self.output.tx
            if l == nil then return end
            for i=1,engine.pull_npackets do
               local p = packet.allocate()
               ffi.copy(p.data, text)
               p.length = #text
               link.transmit(l, p)
            end
         end
      }
   end

   local file = "/var/tmp/selftest.sock"
   local c = config.new()
   config.app(c,  "server", UnixSocket, {filename = file, listen = true})
   config.app(c,  "client", UnixSocket, file)
   config.app(c,  "print_client_tx", printapp, "client tx")
   config.app(c,  "say_hello", echoapp, "hello ")
   config.link(c, "client.tx -> print_client_tx.rx")
   config.link(c, "say_hello.tx -> client.rx")
   config.link(c, "server.tx -> server.rx")

   engine.configure(c)
   engine.main({duration=0.1, report = {showlinks=true}})
end
]]--

