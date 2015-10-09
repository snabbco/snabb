-- Allow both importing this script as a module and running as a script
if type((...)) == "string" then module(..., package.seeall) end

local fragmentv4 = require("apps.lwaftr.fragmentv4")
local eth_proto = require("lib.protocol.ethernet")
local ip4_proto = require("lib.protocol.ipv4")
local get_ihl = require("apps.lwaftr.lwutil").get_ihl
local packet = require("core.packet")
local band = require("bit").band
local ffi = require("ffi")

--
-- Returns a new packet, which contains an Ethernet frame, with an IPv4 header,
-- followed by a payload of "payload_size" random bytes.
--
local function make_ipv4_packet(payload_size)
   local pkt = packet.allocate()
   pkt.length = eth_proto:sizeof() + ip4_proto:sizeof() + payload_size
   local eth_header = eth_proto:new_from_mem(pkt.data, pkt.length)
   local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_header:sizeof(),
                                             pkt.length - eth_header:sizeof())
   assert(pkt.length == eth_header:sizeof() + ip4_header:sizeof() + payload_size)

   -- Ethernet header. The leading bits of the MAC addresses are those for
   -- "Intel Corp" devices, the rest are arbitrary.
   eth_header:src(eth_proto:pton("5c:51:4f:8f:aa:ee"))
   eth_header:dst(eth_proto:pton("5c:51:4f:8f:aa:ef"))
   eth_header:type(0x0800) -- IPv4

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
   local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_proto:sizeof(),
                                             pkt.length - eth_proto:sizeof())
   local total_length = ip4_header:total_length()
   local ihl = ip4_header:ihl() * 4
   assert(ihl == get_ihl(pkt))
   assert(ihl == ip4_header:sizeof())
   assert(total_length - ihl >= 0)
   assert(total_length == pkt.length - eth_proto:sizeof())
   return total_length - ihl
end


local function pkt_frag_offset(pkt)
   assert(pkt.length >= (eth_proto:sizeof() + ip4_proto:sizeof()))
   local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_proto:sizeof(),
                                             pkt.length - eth_proto:sizeof())
   return ip4_header:frag_off() * 8
end


local function pkt_total_length(pkt)
   assert(pkt.length >= (eth_proto:sizeof() + ip4_proto:sizeof()))
   local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_proto:sizeof(),
                                             pkt.length - eth_proto:sizeof())
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
   orig_hdr = ip4_proto:new_from_mem(orig_pkt.data + eth_proto:sizeof(),
                                     orig_pkt.length - eth_proto:sizeof())
   frag_hdr = ip4_proto:new_from_mem(frag_pkt.data + eth_proto:sizeof(),
                                     frag_pkt.length - eth_proto:sizeof())
   assert(orig_hdr:ihl() == frag_hdr:ihl())
   assert(orig_hdr:dscp() == frag_hdr:dscp())
   assert(orig_hdr:ecn() == frag_hdr:ecn())
   assert(orig_hdr:ttl() == frag_hdr:ttl())
   assert(orig_hdr:protocol() == frag_hdr:protocol())
   assert(orig_hdr:src_eq(frag_hdr:src()))
   assert(orig_hdr:dst_eq(frag_hdr:dst()))

   assert(pkt_payload_size(frag_pkt) == frag_pkt.length - eth_proto:sizeof() - ip4_proto:sizeof())

   if is_last_fragment then
      assert(band(frag_hdr:flags(), 0x1) == 0x0)
   else
      assert(band(frag_hdr:flags(), 0x1) == 0x1)
   end
end


function test_payload_1200_mtu_1500()
   print("test:   payload=1200 mtu=1500")

   local pkt = assert(make_ipv4_packet(1200))
   local code, result = fragmentv4.fragment_ipv4(pkt, 1500)
   assert(code == fragmentv4.FRAGMENT_UNNEEDED)
   assert(pkt == result)
end


function test_payload_1200_mtu_1000()
   print("test:   payload=1200 mtu=1000")
   local pkt = assert(make_ipv4_packet(1200))

   -- Keep a copy of the packet, for comparisons
   local orig_pkt = packet.allocate()
   orig_pkt.length = pkt.length
   ffi.copy(orig_pkt.data, pkt.data, pkt.length)

   assert(pkt.length > 1200, "packet short than payload size")

   local code, result = fragmentv4.fragment_ipv4(pkt, 1000)
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
   local pkt = assert(make_ipv4_packet(1200))

   -- Keep a copy of the packet, for comparisons
   local orig_pkt = packet.allocate()
   orig_pkt.length = pkt.length
   ffi.copy(orig_pkt.data, pkt.data, pkt.length)

   local code, result = fragmentv4.fragment_ipv4(pkt, 400)
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
   local pkt = assert(make_ipv4_packet(1200))
   local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_proto:sizeof(),
                                             pkt.length - eth_proto:sizeof())
   ip4_header:flags(0x2) -- Set "don't fragment"
   local code, result = fragmentv4.fragment_ipv4(pkt, 500)
   assert(code == fragmentv4.FRAGMENT_FORBIDDEN)
   assert(type(result) == "nil")
end


local pattern_fill, pattern_check = (function ()
   local pattern = { 0xCC, 0xAA, 0xFF, 0xEE, 0xBB, 0x11, 0xDD }
   local function fill(array, length)
      for i = 0, length-1 do
         array[i] = pattern[(i % #pattern) + 1]
      end
   end
   local function check(array, length)
      for i = 0, length-1 do
         assert(array[i], pattern[(i % #pattern) + 1], "pos: " .. i)
      end
   end
   return fill, check
end)()


function test_reassemble_pattern_fragments()
   print("test:   length=1046 mtu=520 + reassembly")

   local pkt = make_ipv4_packet(1046 - ip4_proto:sizeof() - eth_proto:sizeof())
   pattern_fill(pkt.data + ip4_proto:sizeof() + eth_proto:sizeof(),
                pkt.length - ip4_proto:sizeof() - eth_proto:sizeof())
   local orig_pkt = packet.allocate()
   ffi.copy(orig_pkt.data, pkt.data, pkt.length)

   local code, result = fragmentv4.fragment_ipv4(pkt, 520)
   assert(code == fragmentv4.FRAGMENT_OK)
   assert(#result == 3)

   assert(pkt_payload_size(result[1]) + pkt_payload_size(result[2]) +
          pkt_payload_size(result[3]) == 1046 - ip4_proto:sizeof() - eth_proto:sizeof())

   local size = pkt_payload_size(result[1]) + pkt_payload_size(result[2]) + pkt_payload_size(result[3])
   local data = ffi.new("uint8_t[?]", size)

   for i = 1, #result do
      ffi.copy(data + pkt_frag_offset(result[i]),
               result[i].data + eth_proto:sizeof() + get_ihl(result[i]),
               pkt_payload_size(result[i]))
   end
   pattern_check(data, size)
end


function selftest()
   print("test: lwaftr.fragmentv4.fragment_ipv4")
   test_payload_1200_mtu_1500()
   test_payload_1200_mtu_1000()
   test_payload_1200_mtu_400()
   test_dont_fragment_flag()
   test_reassemble_pattern_fragments()
end

-- Run tests when being invoked as a script from the command line.
if type((...)) == "nil" then selftest() end
