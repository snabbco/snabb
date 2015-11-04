
--TAP I/O app: send and receive data through a TAP device.
--A TAP is a virtual ethernet device whose "wire" can be implemented 
--in userspace. On one hand, A TAP presents itself to the kernel as a normal 
--ethernet interface which can be assigned an IP address and connected to 
--via socket APIs. On the other hand it is assigned a device file which 
--can be written to and read from to implement its wire. This app opens up 
--that device file for I/O.

module(...,package.seeall)

local ffi    = require("ffi")
local link   = require("core.link")
local packet = require("core.packet")
local S      = require("syscall")
local C      = ffi.C

ffi.cdef'int open_tap(const char *name);'

TAP = {}
TAP.__index = TAP

function TAP:new (name)

   name = name or "" --empty string means create a temporary device
   assert(type(name) == "string", "interface name expected")

   local fd = C.open_tap(name) 
   assert(fd >= 0, "failed to openm TAP interface")
      
   local function can_receive()
      return assert(S.select({readfds = {fd}}, 0)).count == 1
   end

   local function can_send()
      return assert(S.select({writefds = {fd}}, 0)).count == 1
   end

   local function receive()
      local p = packet.allocate()
      local maxsz = ffi.sizeof(p.data)
      local len, err = S.read(fd, p.data, maxsz)
      if len == 0 then return end
      if not len then
         assert(nil, err)
      end
      p.length = len
      return p
   end

   local function send(p)
		assert(S.write(fd, p.data, p.length))
   end

   --app object

   local self = setmetatable({}, self)

   function self:pull()
      local l = self.output.tx
      if l == nil then return end
      while not link.full(l) and can_receive() do
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
      S.close(fd)
   end

   return self
end


function selftest ()

   local function hexdump(s)
      return (s:gsub(".", function(c) 
         return string.format("%02x ", c:byte())
      end))
   end

   local printapp = {}
   function printapp:new (name)
      return {
         push = function(self)
            local l = self.input.rx
            if l == nil then return end
            while not link.empty(l) do
               local p = link.receive(l)
               print(hexdump(ffi.string(p.data, p.length)))
               packet.free(p)
            end
         end
      }
   end

   local tap = "tap0"
   local c = config.new()
   config.app(c,  "tap", TAP, tap)
   config.app(c,  "print", printapp, tap)
   config.link(c, "tap.tx -> print.rx")
   engine.configure(c)
   print("type `tunctl & ifconfig tap0 up` to create and activate tap0")
   print("and then ping "..tap.." to see the ethernet frames rolling.")
   engine.main()
   
end

