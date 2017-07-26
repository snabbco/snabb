-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- ARP address resolution (RFC 826)
-- Note: all incoming configurations are assumed to be in network byte order.

-- Given a remote IPv4 address, try to find out its MAC address.
-- If resolution succeeds:
-- All packets coming through the 'south' interface (ie, via the network card)
-- are silently forwarded (unless dropped by the network card).
-- All packets coming through the 'north' interface (the lwaftr) will have
-- their Ethernet headers rewritten.

-- Expected configuration:
-- lwaftr <-> ipv4 fragmentation app <-> lw_eth_resolve <-> vlan tag handler
-- That is, neither fragmentation nor vlan tagging are within the scope of this app.

--[[ Packet format (IPv4/Ethernet), as described on Wikipedia.
Internet Protocol (IPv4) over Ethernet ARP packet
octet offset 	0 	1
0 	Hardware type (HTYPE)
2 	Protocol type (PTYPE)
4 	Hardware address length (HLEN) 	Protocol address length (PLEN)
6 	Operation (OPER)
8 	Sender hardware address (SHA) (first 2 bytes)
10 	(next 2 bytes)
12 	(last 2 bytes)
14 	Sender protocol address (SPA) (first 2 bytes)
16 	(last 2 bytes)
18 	Target hardware address (THA) (first 2 bytes)
20 	(next 2 bytes)
22 	(last 2 bytes)
24 	Target protocol address (TPA) (first 2 bytes)
26 	(last 2 bytes)
--]]

module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local packet = require("core.packet")
local link   = require("core.link")
local lib    = require("core.lib")

local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv4     = require("lib.protocol.ipv4")

local constants = require("apps.lwaftr.constants")
local lwutil = require("apps.lwaftr.lwutil")

local receive, transmit = link.receive, link.transmit
local rd16, wr16 = lwutil.rd16, lwutil.wr16

local ethernet_header_size = constants.ethernet_header_size
local o_ethernet_ethertype = constants.o_ethernet_ethertype

-- local onstants
local arp_request = C.htons(1)
local arp_reply = C.htons(2)

local unknown_eth = ethernet:pton("00:00:00:00:00:00")
local ethernet_broadcast = ethernet:pton("ff:ff:ff:ff:ff:ff")

local ethernet_htype = C.htons(1)
local ipv4_ptype = C.htons(0x0800)
local ethernet_hlen = 6
local ipv4_plen = 4
local arp_eth_ipv4_size = 28
local ethertype_arp = 0x0806
local n_ethertype_arp = C.htons(ethertype_arp)

local o_htype = 0
local o_ptype = 2
local o_hlen = 4
local o_plen = 5
local o_oper = 6
local o_sha = 8
local o_spa = 14
local o_tha = 18
local o_tpa = 24

local function write_arp(pkt, oper, local_eth, local_ipv4, remote_eth, remote_ipv4)
   wr16(pkt.data + o_htype, ethernet_htype)
   wr16(pkt.data + o_ptype, ipv4_ptype)
   pkt.data[o_hlen] = ethernet_hlen
   pkt.data[o_plen] = ipv4_plen
   wr16(pkt.data + o_oper,  oper)
   ffi.copy(pkt.data + o_sha, local_eth, ethernet_hlen)
   ffi.copy(pkt.data + o_spa, local_ipv4, ipv4_plen)
   ffi.copy(pkt.data + o_tha, remote_eth, ethernet_hlen)
   ffi.copy(pkt.data + o_tpa, remote_ipv4, ipv4_plen)

   pkt.length = arp_eth_ipv4_size
end

function form_request(src_eth, src_ipv4, dst_ipv4)
   local req_pkt = packet.allocate()
   write_arp(req_pkt, arp_request, src_eth, src_ipv4, unknown_eth, dst_ipv4)
   local dgram = datagram:new(req_pkt)
   dgram:push(ethernet:new({ src = src_eth, dst = ethernet_broadcast,
                             type = ethertype_arp }))
   req_pkt = dgram:packet()
   dgram:free()
   return req_pkt
end

function form_reply(local_eth, local_ipv4, arp_request_pkt)
   local reply_pkt = packet.allocate()
   local base = arp_request_pkt.data + ethernet_header_size
   local dst_eth = base + o_sha
   local dst_ipv4 = base + o_spa
   write_arp(reply_pkt, arp_reply, local_eth, local_ipv4, dst_eth, dst_ipv4)
   local dgram = datagram:new(reply_pkt)
   dgram:push(ethernet:new({ src = local_eth, dst = dst_eth,
                             type = ethertype_arp }))
   reply_pkt = dgram:packet()
   dgram:free()
   return reply_pkt
end

function is_arp(p)
   if p.length < ethernet_header_size + arp_eth_ipv4_size then return false end
   return rd16(p.data + o_ethernet_ethertype) == n_ethertype_arp
end

function is_arp_reply(p)
   if not is_arp(p) then return false end
   return rd16(p.data + ethernet_header_size + o_oper) == arp_reply
end

function is_arp_request(p)
   if not is_arp(p) then return false end
   return rd16(p.data + ethernet_header_size + o_oper) == arp_request
end

-- ARP does a 'who has' request, and the reply is in the *source* fields
function get_isat_ethernet(arp_p)
   if not is_arp_reply(arp_p) then return nil end
   local eth_addr = ffi.new("uint8_t[?]", 6)
   ffi.copy(eth_addr, arp_p.data + ethernet_header_size + o_sha, 6)
   return eth_addr
end

ARP = {}
local arp_config_params = {
   src_eth =  { default=false },
   src_ipv4 = { default=false },
   dst_eth =  { default=false },
   dst_ipv4 = { default=false },
}

function ARP:new(conf)
   local o = lib.parse(conf, arp_config_params)
   -- TODO: verify that the src and dst ipv4 addresses and src mac address
   -- have been provided, in pton format.
   if not o.dst_eth then
      o.arp_request_pkt = form_request(o.src_eth, o.src_ipv4, o.dst_ipv4)
      self.arp_request_interval = 3 -- Send a new arp_request every three seconds.
   end
   return setmetatable(o, {__index=ARP})
end

function ARP:maybe_send_arp_request (output)
   if self.dst_eth then return end
   self.next_arp_request_time = self.next_arp_request_time or engine.now()
   if self.next_arp_request_time <= engine.now() then
      print(("ARP: Resolving '%s'"):format(ipv4:ntop(self.dst_ipv4)))
      self:send_arp_request(output)
      self.next_arp_request_time = engine.now() + self.arp_request_interval
   end
end

function ARP:send_arp_request (output)
   transmit(output, packet.clone(self.arp_request_pkt))
end

function ARP:push()
   local isouth, osouth = self.input.south, self.output.south
   local inorth, onorth = self.input.north, self.output.north

   self:maybe_send_arp_request(osouth)

   for _ = 1, link.nreadable(isouth) do
      local p = receive(isouth)
      if is_arp(p) then
         if not self.dst_eth and is_arp_reply(p) then
            local dst_ethernet = get_isat_ethernet(p)
            if dst_ethernet then
               print(("ARP: '%s' resolved (%s)"):format(ipv4:ntop(self.dst_ipv4),
                                                        ethernet:ntop(dst_ethernet)))
               self.dst_eth = dst_ethernet
            end
            packet.free(p)
         elseif is_arp_request(p, self.src_ipv4) then
            local arp_reply_pkt = form_reply(self.src_eth, self.src_ipv4, p)
            if arp_reply_pkt then
               transmit(osouth, arp_reply_pkt)
            end
            packet.free(p)
         else -- incoming ARP that isn't handled; drop it silently
            packet.free(p)
         end
      else
         transmit(onorth, p)
      end
   end

   for _ = 1, link.nreadable(inorth) do
      local p = receive(inorth)
      if not self.dst_eth then
         -- drop all southbound packets until the next hop's ethernet address is known
         packet.free(p)
      else
         lwutil.set_dst_ethernet(p, self.dst_eth)
         transmit(osouth, p)
      end
   end
end

function selftest()
   print('selftest: arp')

   local arp = ARP:new({ src_ipv4 = ipv4:pton('1.2.3.4'),
                         dst_ipv4 = ipv4:pton('5.6.7.8'), -- Static gateway.
                         src_eth  = ethernet:pton('01:02:03:04:05:06') })
   arp.input  = { south=link.new('south in'),  north=link.new('north in') }
   arp.output = { south=link.new('south out'), north=link.new('north out') }
   
   -- After first push, ARP should have sent out request.
   arp:push()
   assert(link.nreadable(arp.output.south) == 1)
   assert(link.nreadable(arp.output.north) == 0)
   local req = link.receive(arp.output.south)
   assert(is_arp(req))
   assert(is_arp_request(req))
   -- Send a response.
   local rep = form_reply(
      ethernet:pton('11:22:33:44:55:66'), ipv4:pton('5.6.7.8'), req)
   packet.free(req)
   assert(is_arp(rep))
   assert(is_arp_reply(rep))
   link.transmit(arp.input.south, rep)
   -- Process response.
   arp:push()
   assert(link.nreadable(arp.output.south) == 0)
   assert(link.nreadable(arp.output.north) == 0)

   -- Now push some payload.
   local payload = datagram:new()
   local udp = require("lib.protocol.udp")
   local IP_PROTO_UDP  = 17
   local udp_h = udp:new({ src_port = 1234,
                           dst_port = 5678 })
   local ipv4_h = ipv4:new({ src = ipv4:pton('1.1.1.1'),
                             dst = ipv4:pton('2.2.2.2'),
                             protocol = IP_PROTO_UDP,
                             ttl = 64 })
   payload:push(udp_h)
   payload:push(ipv4_h)
   payload:push(ethernet:new({ src = ethernet:pton("00:00:00:00:00:00"),
                               dst = ethernet:pton("00:00:00:00:00:00"),
                               type = constants.ethertype_ipv4 }))
   link.transmit(arp.input.north, payload:packet())
   arp:push()
   assert(link.nreadable(arp.output.south) == 1)
   assert(link.nreadable(arp.output.north) == 0)

   -- The packet should have the destination ethernet address set.
   local routed = link.receive(arp.output.south)
   local payload = datagram:new(routed, ethernet)
   local eth_h = payload:parse()
   assert(eth_h:src_eq(ethernet:pton('00:00:00:00:00:00')))
   assert(eth_h:dst_eq(ethernet:pton('11:22:33:44:55:66')))
   assert(ipv4_h:eq(payload:parse()))
   assert(udp_h:eq(payload:parse()))
   packet.free(payload:packet())
   print('selftest ok')
end
