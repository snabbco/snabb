module(..., package.seeall)

local S = require("syscall")
local link = require("core.link")
local packet = require("core.packet")
local ffi = require("ffi")
local C = ffi.C
local const = require("syscall.linux.constants")
local os = require("os")

local t = S.types.t

Tap = { }

function Tap:new (name)
   assert(name, "missing tap interface name")
   
   local sock, err = S.open("/dev/net/tun", "rdwr, nonblock");
   assert(sock, "Error opening /dev/net/tun: " .. tostring(err))
   local ifr = t.ifreq()
   ifr.flags = "tap, no_pi"
   ifr.name = name
   local ok, err = sock:ioctl("TUNSETIFF", ifr)
   if not ok then
      S.close(sock)
      error("Error opening /dev/net/tun: " .. tostring(err))
   end
   
   return setmetatable({sock = sock, name = name}, {__index = Tap})
end

function Tap:pull ()
   local l = self.output.output
   if l == nil then return end
   while not link.full(l) do
      local p = packet.allocate()
      local len, err = S.read(self.sock, p.data, C.PACKET_PAYLOAD_SIZE)
      -- errno == EAGAIN indicates that the read would of blocked as there is no 
      -- packet waiting. It is not a failure.
      if not len and err.errno == const.E.AGAIN then 
         packet.free(p)
         return
      end
      if not len then
         packet.free(p)
         error("Failed read on " .. self.name .. ": " .. tostring(err))
      end
      p.length = len
      link.transmit(l, p)
   end
end

function Tap:push ()
   local l = self.input.input
   while not link.empty(l) do
      -- The socket write might of blocked so don't dequeue the packet from the link
      -- until the write has completed.
      local p = link.front(l)
      local len, err = S.write(self.sock, p.data, p.length)
      -- errno == EAGAIN indicates that the write would of blocked
      if not len and err.errno ~= const.E.AGAIN or len and len ~= p.length then
         error("Failed write on " .. self.name .. tostring(err))
      end
      if len ~= p.length and err.errno == const.E.AGAIN then
         return
      end
      -- The write completed so dequeue it from the link and free the packet
      link.receive(l)
      packet.free(p)
   end
end

function Tap:stop()
   S.close(self.sock)
end

function selftest()
   -- tapsrc and tapdst are bridged together in linux. Packets are sent out of tapsrc and they are expected
   -- to arrive back on tapdst. Linux may create other control-plane packets so to avoid races if a packet doesn't
   -- match the one we just sent keep looking until it does match. 

   -- The linux bridge does mac address learning so some care must be taken with the preparation of selftest.cap
   -- A mac address should appear only as the source address or destination address

   -- This test should only be run from inside apps/tap/selftest.sh
   if not os.getenv("SNABB_TAPTEST") then os.exit(engine.test_skipped_code) end
   local pcap = require("lib.pcap.pcap")
   local tapsrc = Tap:new("tapsrc")
   local tapdst = Tap:new("tapdst")
   local linksrc = link.new("linksrc")
   local linkreturn = link.new("linkreturn")
   tapsrc.input = { input = linksrc }
   tapdst.output = { output = linkreturn }
   local records = pcap.records("apps/tap/selftest.cap")
   local i = 0
   repeat
         i = i + 1
         local data, record, extra = records()
         if data then
            local p = packet.from_string(data)
            link.transmit(linksrc, packet.clone(p))
            tapsrc:push()
            while true do
               local ok, err = S.select({readfds = {tapdst.sock}}, 10)
               if err then error("Select error: " .. tostring(err)) end
               if ok.count == 0 then error("select timed out or packet " .. tostring(i) .. " didn't match") end

               tapdst:pull()
               local pret = link.receive(linkreturn)
               if packet.length(pret) == packet.length(p) and C.memcmp(packet.data(pret), packet.data(p), packet.length(pret)) then
                  packet.free(pret)
                  break
               end
               packet.free(pret)
            end
            packet.free(p)
         end
   until not data
end
