module(...,package.seeall)

local app    = require("core.app")
local link   = require("core.link")
local packet = require("core.packet")
local dev    = require("apps.socket.dev").dev

RawSocket = {}

function RawSocket:new (ifname)
   assert(ifname)
   local dev, err = dev:new(ifname)
   if err then return nil, err end
   self.__index = self
   return setmetatable({dev = dev}, self)
end

function RawSocket:pull ()
   local l = self.output.tx
   if l == nil then return end
   while not link.full(l) and self.dev:can_receive() do
      link.transmit(l, self.dev:receive())
   end
end

function RawSocket:push ()
   local l = self.input.rx
   if l == nil then return end
   while not link.empty(l) and self.dev:can_transmit() do
      local p = link.receive(l)
      self.dev:transmit(p)
      packet.free(p)
   end
end

function RawSocket:stop ()
   assert(self.dev)
   return self.dev:stop()
end

function selftest ()
   -- Send a packet over the loopback device and check
   -- that it is received correctly.
   -- XXX beware of a race condition with unrelated traffic over the
   -- loopback device
   local datagram = require("lib.protocol.datagram")
   local ethernet = require("lib.protocol.ethernet")
   local ipv6 = require("lib.protocol.ipv6")
   local dg_tx = datagram:new()
   local src = ethernet:pton("00:00:00:00:00:01")
   local dst = ethernet:pton("00:00:00:00:00:02")
   local localhost = ipv6:pton("0:0:0:0:0:0:0:1")
   dg_tx:push(ipv6:new({src = localhost,
                        dst = localhost,
                        next_header = 59, -- no next header
                        hop_limit = 1}))
   dg_tx:push(ethernet:new({src = src, dst = dst, type = 0x86dd}))

   local link = require("core.link")
   local lo, err = RawSocket:new("lo")
   assert(not err, "Cannot create RawSocket on loopback devicex")
   lo.input, lo.output = {}, {}
   lo.input.rx, lo.output.tx = link.new("test1"), link.new("test2")
   link.transmit(lo.input.rx, dg_tx:packet())
   lo:push()
   lo:pull()
   local dg_rx = datagram:new(link.receive(lo.output.tx), ethernet)
   assert(dg_rx:parse({ { ethernet, function(eth)
                                       return(eth:src_eq(src) and eth:dst_eq(dst)
                                        and eth:type() == 0x86dd)
                                    end },
                        { ipv6, function(ipv6)
                                   return(ipv6:src_eq(localhost) and
                                       ipv6:dst_eq(localhost))
                                end } }), "loopback test failed")
   lo:stop()

   -- Another useful test would be to feed a pcap file with
   -- pings to 127.0.0.1 and ::1 into lo and capture/compare
   -- the responses with a pre-recorded pcap.
end
