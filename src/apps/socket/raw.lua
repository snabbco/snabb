-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local S = require("syscall")
local h = require("syscall.helpers")
local bit = require("bit")
local link = require("core.link")
local packet = require("core.packet")
local ffi = require("ffi")
local C = ffi.C

local c, t = S.c, S.types.t

RawSocket = {}

function RawSocket:new (ifname)
   assert(ifname)
   local index, err = S.util.if_nametoindex(ifname)
   if not index then error(err) end

   local tp = h.htons(c.ETH_P["ALL"])
   local sock, err = S.socket(c.AF.PACKET, bit.bor(c.SOCK.RAW, c.SOCK.NONBLOCK), tp)
   if not sock then error(err) end

   local addr = t.sockaddr_ll{sll_family = c.AF.PACKET, sll_ifindex = index, sll_protocol = tp}
   local ok, err = S.bind(sock, addr)
   if not ok then
      S.close(sock)
      error(err)
   end
   return setmetatable({sock = sock}, {__index = RawSocket})
end

function RawSocket:pull ()
   local l = self.output.tx
   if l == nil then return end
   while not link.full(l) and self:can_receive() do
      link.transmit(l, self:receive())
   end
end

function RawSocket:can_receive ()
   local ok, err = S.select({readfds = {self.sock}}, 0)
   return not (err or ok.count == 0)
end

function RawSocket:receive ()
   local buffer = ffi.new("uint8_t[?]", C.PACKET_PAYLOAD_SIZE)
   local sz, err = S.read(self.sock, buffer, C.PACKET_PAYLOAD_SIZE)
   if not sz then return err end
   return packet.from_pointer(buffer, sz)
end

function RawSocket:push ()
   local l = self.input.rx
   if l == nil then return end
   while not link.empty(l) and self:can_transmit() do
      local p = link.receive(l)
      self:transmit(p)
      packet.free(p)
   end
end

function RawSocket:can_transmit ()
   local ok, err = S.select({writefds = {self.sock}}, 0)
   return not (err or ok.count == 0)
end

function RawSocket:transmit (p)
   local sz, err = S.write(self.sock, packet.data(p), packet.length(p))
   if not sz then return err end
   return sz
end

function RawSocket:stop()
   S.close(self.sock)
end

function selftest ()
   -- Send a packet over the loopback device and check
   -- that it is received correctly.
   local datagram = require("lib.protocol.datagram")
   local ethernet = require("lib.protocol.ethernet")
   local ipv6 = require("lib.protocol.ipv6")
   local Match = require("apps.test.match").Match

   -- Initialize RawSocket and Match.
   local c = config.new()
   config.app(c, "lo", RawSocket, "lo")
   config.app(c, "match", Match, {fuzzy=true})
   config.link(c, "lo.tx->match.rx")
   engine.configure(c)
   local link_in, link_cmp = link.new("test_in"), link.new("test_cmp")
   engine.app_table.lo.input.rx = link_in
   engine.app_table.match.input.comparator = link_cmp
   -- Construct packet.
   local dg_tx = datagram:new()
   local src = ethernet:pton("02:00:00:00:00:01")
   local dst = ethernet:pton("02:00:00:00:00:02")
   local localhost = ipv6:pton("0:0:0:0:0:0:0:1")
   dg_tx:push(ipv6:new({src = localhost,
                        dst = localhost,
                        next_header = 59, -- No next header.
                        hop_limit = 1}))
   dg_tx:push(ethernet:new({src = src,
                            dst = dst,
                            type = 0x86dd}))
   -- Transmit packets.
   link.transmit(link_in, dg_tx:packet())
   link.transmit(link_cmp, packet.clone(dg_tx:packet()))
   engine.app_table.lo:push()
   -- Run engine.
   engine.main({duration = 0.01, report = {showapps=true,showlinks=true}})
   assert(#engine.app_table.match:errors() == 0)
   print("selftest passed")

   -- XXX Another useful test would be to feed a pcap file with
   -- pings to 127.0.0.1 and ::1 into lo and capture/compare
   -- the responses with a pre-recorded pcap.
end
