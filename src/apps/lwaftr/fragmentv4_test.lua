-- Allow both importing this script as a module and running as a script
if type((...)) == "string" then module(..., package.seeall) end

local constants = require("apps.lwaftr.constants")
local fragmentv4 = require("apps.lwaftr.fragmentv4")
local eth_proto = require("lib.protocol.ethernet")
local ip4_proto = require("lib.protocol.ipv4")
local lwutil = require("apps.lwaftr.lwutil")
local packet = require("core.packet")
local band = require("bit").band
local ffi = require("ffi")

local rd16, wr16, get_ihl_from_offset = lwutil.rd16, lwutil.wr16, lwutil.get_ihl_from_offset

--
-- Returns a new packet, which contains an Ethernet frame, with an IPv4 header,
-- followed by a payload of "payload_size" random bytes.
--
local function make_ipv4_packet(payload_size)
   local eth_size = eth_proto:sizeof()
   local pkt = packet.allocate()
   pkt.length = eth_size + ip4_proto:sizeof() + payload_size
   local eth_header = eth_proto:new_from_mem(pkt.data, pkt.length)
   local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_size,
                                             pkt.length - eth_size)
   assert(pkt.length == eth_size + ip4_header:sizeof() + payload_size)

   -- Ethernet header. The leading bits of the MAC addresses are those for
   -- "Intel Corp" devices, the rest are arbitrary.
   eth_header:src(eth_proto:pton("5c:51:4f:8f:aa:ee"))
   eth_header:dst(eth_proto:pton("5c:51:4f:8f:aa:ef"))
   eth_header:type(constants.ethertype_ipv4)

   -- IPv4 header
   ip4_header:ihl(ip4_header:sizeof() / 4)
   ip4_header:dscp(0)
   ip4_header:ecn(0)
   ip4_header:total_length(ip4_header:sizeof() + payload_size)
   ip4_header:id(0)
   ip4_header:flags(0)
   ip4_header:frag_off(0)
   ip4_header:ttl(15)
   ip4_header:protocol(0xFF)
   ip4_header:src(ip4_proto:pton("192.168.10.10"))
   ip4_header:dst(ip4_proto:pton("192.168.10.20"))
   ip4_header:checksum()

   -- We do not fill up the rest of the packet: random contents works fine
   -- because we are testing IP fragmentation, so there's no need to care
   -- about upper layers.
   return pkt
end

local function pkt_payload_size(pkt)
   assert(pkt.length >= (eth_proto:sizeof() + ip4_proto:sizeof()))
   local eth_size = eth_proto:sizeof()
   local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_size,
                                             pkt.length - eth_size)
   local total_length = ip4_header:total_length()
   local ihl = ip4_header:ihl() * 4
   assert(ihl == get_ihl_from_offset(pkt, eth_size))
   assert(ihl == ip4_header:sizeof())
   assert(total_length - ihl >= 0)
   assert(total_length == pkt.length - eth_size)
   return total_length - ihl
end

local function pkt_frag_offset(pkt)
   assert(pkt.length >= (eth_proto:sizeof() + ip4_proto:sizeof()))
   local eth_size = eth_proto:sizeof()
   local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_size,
                                             pkt.length - eth_size)
   return ip4_header:frag_off() * 8
end

local function pkt_total_length(pkt)
   assert(pkt.length >= (eth_proto:sizeof() + ip4_proto:sizeof()))
   local eth_size = eth_proto:sizeof()
   local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_size,
                                             pkt.length - eth_size)
   return ip4_header:total_length()
end

--
-- Checks that "frag_pkt" is a valid fragment of the "orig_pkt" packet.
--
local function check_packet_fragment(orig_pkt, frag_pkt, is_last_fragment)
   -- Ethernet fields
   local orig_hdr = eth_proto:new_from_mem(orig_pkt.data, orig_pkt.length)
   local frag_hdr = eth_proto:new_from_mem(frag_pkt.data, frag_pkt.length)
   assert(orig_hdr:src_eq(frag_hdr:src()))
   assert(orig_hdr:dst_eq(frag_hdr:dst()))
   assert(orig_hdr:type() == frag_hdr:type())

   -- IPv4 fields
   local eth_size = eth_proto:sizeof()
   orig_hdr = ip4_proto:new_from_mem(orig_pkt.data + eth_size,
                                     orig_pkt.length - eth_size)
   frag_hdr = ip4_proto:new_from_mem(frag_pkt.data + eth_size,
                                     frag_pkt.length - eth_size)
   assert(orig_hdr:ihl() == frag_hdr:ihl())
   assert(orig_hdr:dscp() == frag_hdr:dscp())
   assert(orig_hdr:ecn() == frag_hdr:ecn())
   assert(orig_hdr:ttl() == frag_hdr:ttl())
   assert(orig_hdr:protocol() == frag_hdr:protocol())
   assert(orig_hdr:src_eq(frag_hdr:src()))
   assert(orig_hdr:dst_eq(frag_hdr:dst()))

   assert(pkt_payload_size(frag_pkt) == frag_pkt.length - eth_size - ip4_proto:sizeof())

   if is_last_fragment then
      assert(band(frag_hdr:flags(), 0x1) == 0x0)
   else
      assert(band(frag_hdr:flags(), 0x1) == 0x1)
   end
end

function test_payload_1200_mtu_1500()
   print("test:   payload=1200 mtu=1500")

   local pkt = make_ipv4_packet(1200)
   local code, result = fragmentv4.fragment(pkt, 1500)
   assert(code == fragmentv4.FRAGMENT_UNNEEDED)
   assert(pkt == result)
end

function test_payload_1200_mtu_1000()
   print("test:   payload=1200 mtu=1000")
   local pkt = make_ipv4_packet(1200)

   -- Keep a copy of the packet, for comparisons
   local orig_pkt = packet.clone(pkt)

   assert(pkt.length > 1200, "packet short than payload size")
   local ehs = constants.ethernet_header_size
   local code, result = fragmentv4.fragment(pkt, 1000 - ehs)
   assert(code == fragmentv4.FRAGMENT_OK)
   assert(#result == 2, "fragmentation returned " .. #result .. " packets (2 expected)")

   for i = 1, #result do
      assert(result[i].length <= 1000, "packet " .. i .. " longer than MTU")
      local is_last = (i == #result)
      check_packet_fragment(orig_pkt, result[i], is_last)
   end

   assert(pkt_payload_size(result[1]) + pkt_payload_size(result[2]) == 1200)
   assert(pkt_payload_size(result[1]) == pkt_frag_offset(result[2]))
end

function test_payload_1200_mtu_400()
   print("test:   payload=1200 mtu=400")
   local pkt = make_ipv4_packet(1200)

   -- Keep a copy of the packet, for comparisons
   local orig_pkt = packet.clone(pkt)
   local ehs = constants.ethernet_header_size
   local code, result = fragmentv4.fragment(pkt, 400 - ehs)
   assert(code == fragmentv4.FRAGMENT_OK)
   assert(#result == 4,
          "fragmentation returned " .. #result .. " packets (4 expected)")
   for i = 1, #result do
      assert(result[i].length <= 1000, "packet " .. i .. " longer than MTU")
      local is_last = (i == #result)
      check_packet_fragment(orig_pkt, result[i], is_last)
   end

   assert(pkt_payload_size(result[1]) + pkt_payload_size(result[2]) +
          pkt_payload_size(result[3]) + pkt_payload_size(result[4]) == 1200)
   assert(pkt_payload_size(result[1]) == pkt_frag_offset(result[2]))
   assert(pkt_payload_size(result[1]) + pkt_payload_size(result[2]) ==
          pkt_frag_offset(result[3]))
   assert(pkt_payload_size(result[1]) + pkt_payload_size(result[2]) +
          pkt_payload_size(result[3]) == pkt_frag_offset(result[4]))
end

function test_dont_fragment_flag()
   print("test:   packet with \"don't fragment\" flag")
   -- Try to fragment a packet with the "don't fragment" flag set
   local pkt = make_ipv4_packet(1200)
   local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_proto:sizeof(),
                                             pkt.length - eth_proto:sizeof())
   ip4_header:flags(0x2) -- Set "don't fragment"
   local code, result = fragmentv4.fragment(pkt, 500)
   assert(code == fragmentv4.FRAGMENT_FORBIDDEN)
   assert(type(result) == "nil")
end

function selftest()
   print("test: lwaftr.fragmentv4.fragment_ipv4")
   test_payload_1200_mtu_1500()
   test_payload_1200_mtu_1000()
   test_payload_1200_mtu_400()
   test_dont_fragment_flag()
end

-- Run tests when being invoked as a script from the command line.
if type((...)) == "nil" then selftest() end
