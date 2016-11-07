module(..., package.seeall)

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


local ffi = require("ffi")
local C = ffi.C
local packet = require("core.packet")

local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")

local constants = require("apps.lwaftr.constants")
local lwutil = require("apps.lwaftr.lwutil")

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

function selftest()
   local ipv4 = require("lib.protocol.ipv4")
   local tlocal_eth = ethernet:pton("01:02:03:04:05:06")
   local tlocal_ip = ipv4:pton("1.2.3.4")
   local tremote_eth = ethernet:pton("07:08:09:0a:0b:0c")
   local tremote_ip = ipv4:pton("6.7.8.9")
   local req = form_request(tlocal_eth, tlocal_ip, tremote_ip)
   assert(is_arp(req))
   assert(is_arp_request(req))
   local rep = form_reply(tremote_eth, tremote_ip, req)
   assert(is_arp(rep))
   assert(is_arp_reply(rep))
   local isat = get_isat_ethernet(rep, tlocal_ip)
   assert(C.memcmp(isat, tremote_eth, 6) == 0)
end
