
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

   -- Process args
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

   -- Open/close socket
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
         assert(csock:nonblock())
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

   -- Get connected socket
   local sock
   local function connect()
      sock = sock or open()
      return sock
   end

   -- App object
   local self = setmetatable({}, self)

   -- Preallocated buffer for the next packet.
   local rxp = packet.allocate()
   -- Try to read payload into rxp.
   -- Return true on success or false if no data is available.
   local function try_read ()
      local bytes = S.read(sock, rxp.data, packet.max_payload)
      if bytes then
         rxp.length = bytes
         return true
      else
         return false
      end
   end
   function self:pull()
      connect()
      local l = self.output.tx
      local limit = engine.pull_npackets
      if sock and l ~= nil then
         while limit > 0 and try_read() do
            link.transmit(l, rxp)
            rxp = packet.allocate()
            limit = limit - 1
         end
      end
   end

   function self:push()
      local l = self.input.rx
      if l ~= nil then
         -- Transmit all queued packets.
         -- Let the kernel drop them if it does not have capacity.
         while sock and not link.empty(l) do
            local p = link.receive(l)
            S.write(connect(), p.data, p.length)
            packet.free(p)
         end
      end
   end

   function self:stop()
      close()
   end

   return self
end


function selftest ()
   print("selftest: socket/unix")
   local checkapp = {}
   function checkapp:new (name)
      return {
         push = function(self)
            local l = self.input.rx
            if l == nil then return end
            while not link.empty(l) do
               local p = link.receive(l)
               assert(p, "No packet received")
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
   config.app(c,  "check_client_tx", checkapp, "client tx")
   config.app(c,  "say_hello", echoapp, "hello ")
   config.link(c, "client.tx -> check_client_tx.rx")
   config.link(c, "say_hello.tx -> client.rx")
   config.link(c, "server.tx -> server.rx")

   engine.configure(c)
   engine.main({duration=0.1, report = {showlinks=true}})
   print("selftest: done")
end
