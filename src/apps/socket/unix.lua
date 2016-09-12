
--unix socket app: transmit and receive packets through a named socket.
--can be used in server (listening) or client (connecting) mode.

module(...,package.seeall)

local ffi    = require("ffi")
local link   = require("core.link")
local packet = require("core.packet")
local S      = require("syscall")

UnixSocket = {}
UnixSocket.__index = UnixSocket

local modes = {stream = "stream", packet = "dgram"}

function UnixSocket:new (arg)

   --process args

   assert(arg, "filename or options expected")

   local file, listen, mode
   if type(arg) == "string" then
      file = arg
   else
      file = arg.filename
      listen = arg.listen
      mode = arg.mode
   end
   mode = assert(modes[mode or "stream"], "invalid mode")
   assert(file, "filename expected")

   --open/close socket

   local open, close

   if listen then --server mode

      local sock = assert(S.socket("unix", mode..", nonblock"))
      S.unlink(file) --unlink to avoid EINVAL on bind()
      local sa = S.t.sockaddr_un(file)
      assert(sock:bind(sa))
      if mode == "stream" then
         assert(sock:listen())
      end

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

   else --client mode

      local sock = assert(S.socket("unix", mode..", nonblock"))

      function open()
         local sa = S.t.sockaddr_un(file)
         local ok, err = sock:connect(sa)
         if not ok then
            if err.CONNREFUSED or err.AGAIN or err.NOENT then return end
            assert(nil, err)
         end
         return sock
      end

      function close()
         sock:close()
      end

   end

   --send/receive packets

   local sock
   local function connect()
      sock = sock or open()
      return sock
   end

   local function can_receive()
      if not connect() then return end
      local t, err = S.select({readfds = {sock}}, 0)
      while not t and (err.AGAIN or err.INTR) do
         t, err = S.select({readfds = {sock}}, 0)
      end
      assert(t, err)
      return t.count == 1
   end

   local function can_send()
      if not connect() then return end
      local t, err = S.select({writefds = {sock}}, 0)
      while not t and (err.AGAIN or err.INTR) do
         t, err = S.select({writefds = {sock}}, 0)
      end
      assert(t, err)
      return t.count == 1
   end

   local function receive()
      local p = packet.allocate()
      local maxsz = ffi.sizeof(p.data)
      local len, err = S.read(sock, p.data, maxsz)
      if len == 0 then return end
      if not len then
         assert(nil, err)
      end
      p.length = len
      return p
   end

   local function send(p)
      local sz, err = S.write(sock, p.data, p.length)
      assert(sz, err)
      assert(sz == p.length)
   end

   --app object

   local self = setmetatable({}, self)

   function self:pull()
      local l = self.output.tx
      if l == nil then return end
      local limit = engine.pull_npackets
      while limit > 0 and can_receive() do
         limit = limit - 1
         local p = receive()
         if p then
            link.transmit(l, p) --link owns p now so we mustn't free it
         end
      end
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
      close()
   end

   return self
end


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

