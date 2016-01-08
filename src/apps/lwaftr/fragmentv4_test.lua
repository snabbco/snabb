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
local function make_ipv4_packet(payload_size, vlan_id)
   local eth_size = eth_proto:sizeof()
   if vlan_id then
      eth_size = eth_size + 4  -- VLAN tag takes 4 extra bytes
   end
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

   if vlan_id then
      eth_header:type(constants.dotq_tpid)
      wr16(pkt.data + eth_proto:sizeof(), vlan_id)
      wr16(pkt.data + eth_proto:sizeof() + 2, constants.ethertype_ipv4)
   else
      eth_header:type(constants.ethertype_ipv4)
   end

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


local function eth_header_size(pkt)
   local eth_size = eth_proto:sizeof()
   local eth_header = eth_proto:new_from_mem(pkt.data, pkt.length)
   if eth_header:type() == constants.dotq_tpid then
      return eth_size + 4  -- Packet has VLAN tagging
   else
      return eth_size
   end
end


local function pkt_payload_size(pkt)
   assert(pkt.length >= (eth_proto:sizeof() + ip4_proto:sizeof()))
   local eth_size = eth_header_size(pkt)
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
   local eth_size = eth_header_size(pkt)
   local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_size,
                                             pkt.length - eth_size)
   return ip4_header:frag_off() * 8
end


local function pkt_total_length(pkt)
   assert(pkt.length >= (eth_proto:sizeof() + ip4_proto:sizeof()))
   local eth_size = eth_header_size(pkt)
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

   -- Check for VLAN tagging and check the additional fields
   local eth_size = eth_proto:sizeof()
   if orig_hdr:type() == constants.dotq_tpid then
      assert(rd16(orig_pkt.data + eth_size) == rd16(frag_pkt.data + eth_size)) -- VLAN id
      assert(rd16(orig_pkt.data + eth_size + 2) == rd16(frag_pkt.data + eth_size + 2)) -- Protocol
      eth_size = eth_size + 4
   end

   -- IPv4 fields
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

   local pkt = assert(make_ipv4_packet(1200))
   local code, result = fragmentv4.fragment(pkt, constants.ethernet_header_size, 1500)
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
   local ehs = constants.ethernet_header_size
   local code, result = fragmentv4.fragment(pkt, ehs, 1000 - ehs)
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

   local ehs = constants.ethernet_header_size
   local code, result = fragmentv4.fragment(pkt, ehs, 400 - ehs)
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
   local code, result = fragmentv4.fragment(pkt, constants.ethernet_header_size, 500)
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

   local code, result = fragmentv4.fragment(pkt, constants.ethernet_header_size, 520)
   assert(code == fragmentv4.FRAGMENT_OK)
   assert(#result == 3)

   assert(pkt_payload_size(result[1]) + pkt_payload_size(result[2]) +
          pkt_payload_size(result[3]) == 1046 - ip4_proto:sizeof() - eth_proto:sizeof())

   local size = pkt_payload_size(result[1]) + pkt_payload_size(result[2]) + pkt_payload_size(result[3])
   local data = ffi.new("uint8_t[?]", size)

   for i = 1, #result do
      local ih = get_ihl_from_offset(result[i], constants.ethernet_header_size)
      ffi.copy(data + pkt_frag_offset(result[i]),
               result[i].data + eth_proto:sizeof() + ih,
               pkt_payload_size(result[i]))
   end
   pattern_check(data, size)
end


function test_vlan_tagging()
   print("test:   vlan tagging")

   local pkt = assert(make_ipv4_packet(1200, 42))
   assert(eth_header_size(pkt) == constants.ethernet_header_size + 4)

   -- Keep a copy of the packet, for comparisons
   local orig_pkt = packet.allocate()
   orig_pkt.length = pkt.length
   ffi.copy(orig_pkt.data, pkt.data, pkt.length)

   local vehs = constants.ethernet_header_size + 4
   local code, result = fragmentv4.fragment(pkt, vehs, 1000 - vehs)
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


function test_reassemble_unneeded(vlan_id)
   print("test:   no reassembly needed (single packet)")

   local eth_size = eth_proto:sizeof()
   if vlan_id then
      eth_size = eth_size + 4
   end
   local pkt = make_ipv4_packet(500 - ip4_proto:sizeof() - eth_size, vlan_id)
   assert(pkt.length == 500)
   pattern_fill(pkt.data + ip4_proto:sizeof() + eth_size,
                pkt.length - ip4_proto:sizeof() - eth_size)

   local code, r = fragmentv4.reassemble({ pkt }, eth_size)
   assert(code == fragmentv4.REASSEMBLE_OK)
   assert(r.length == pkt.length)
   pattern_check(r.data + ip4_proto:sizeof() + eth_size,
                 r.length - ip4_proto:sizeof() - eth_size)
end


function test_reassemble_two_missing_fragments(vlan_id)
   print("test:   two fragments (one missing)")
   local pkt = assert(make_ipv4_packet(1200), vlan_id)
   local eth_size = eth_header_size(pkt)
   local code, fragments = fragmentv4.fragment(pkt, eth_size, 1000)
   assert(code == fragmentv4.FRAGMENT_OK)
   assert(#fragments == 2)

   assert(fragmentv4.REASSEMBLE_MISSING_FRAGMENT ==
          (fragmentv4.reassemble({ fragments[1] }, eth_size)))
   assert(fragmentv4.REASSEMBLE_MISSING_FRAGMENT ==
          (fragmentv4.reassemble({ fragments[2] }, eth_size)))
end


function test_reassemble_three_missing_fragments(vlan_id)
   print("test:   three fragments (one/two missing)")
   local pkt = assert(make_ipv4_packet(1000))
   local eth_size = eth_header_size(pkt)
   local code, fragments = fragmentv4.fragment(pkt, eth_size, 400)
   assert(code == fragmentv4.FRAGMENT_OK)
   assert(#fragments == 3)

   assert(fragmentv4.REASSEMBLE_MISSING_FRAGMENT ==
          (fragmentv4.reassemble({ fragments[1] }, eth_size)))
   assert(fragmentv4.REASSEMBLE_MISSING_FRAGMENT ==
          (fragmentv4.reassemble({ fragments[2] }, eth_size)))
   assert(fragmentv4.REASSEMBLE_MISSING_FRAGMENT ==
          (fragmentv4.reassemble({ fragments[3] }, eth_size)))

   assert(fragmentv4.REASSEMBLE_MISSING_FRAGMENT ==
          (fragmentv4.reassemble({ fragments[1], fragments[2] }, eth_size)))
   assert(fragmentv4.REASSEMBLE_MISSING_FRAGMENT ==
          (fragmentv4.reassemble({ fragments[1], fragments[3] }, eth_size)))
   assert(fragmentv4.REASSEMBLE_MISSING_FRAGMENT ==
          (fragmentv4.reassemble({ fragments[3], fragments[3] }, eth_size)))

   assert(fragmentv4.REASSEMBLE_MISSING_FRAGMENT ==
          (fragmentv4.reassemble({ fragments[2], fragments[1] }, eth_size)))
   assert(fragmentv4.REASSEMBLE_MISSING_FRAGMENT ==
          (fragmentv4.reassemble({ fragments[3], fragments[1] }, eth_size)))
   assert(fragmentv4.REASSEMBLE_MISSING_FRAGMENT ==
          (fragmentv4.reassemble({ fragments[2], fragments[3] }, eth_size)))
end


function test_reassemble_two(vlan_id)
   print("test:   payload=1200 mtu=1000")
   local pkt = assert(make_ipv4_packet(1200), vlan_id)
   assert(pkt.length > 1200, "packet shorter than payload size")
   local eth_size = eth_header_size(pkt)

   -- Keep a copy of the packet, for comparisons
   local orig_pkt = packet.allocate()
   orig_pkt.length = pkt.length
   ffi.copy(orig_pkt.data, pkt.data, pkt.length)

   local code, fragments = fragmentv4.fragment(pkt, eth_size, 1000)
   assert(code == fragmentv4.FRAGMENT_OK)
   assert(#fragments == 2)

   local function try(f)
      local code, pkt = fragmentv4.reassemble(f, eth_size)
      assert(code == fragmentv4.REASSEMBLE_OK, "returned: " .. code)
      assert(pkt.length == orig_pkt.length)

      for i = 1, pkt.length do
         assert(pkt.data[i] == orig_pkt.data[i],
                "byte["..i.."] expected="..orig_pkt.data[i].." got="..pkt.data[i])
      end
   end

   try { fragments[1], fragments[2] }
   try { fragments[2], fragments[1] }
end


function test_reassemble_three(vlan_id)
   print("test:   payload=1000 mtu=400")
   local pkt = assert(make_ipv4_packet(1000), vlan_id)
   local eth_size = eth_header_size(pkt)

   -- Keep a copy of the packet, for comparisons
   local orig_pkt = packet.allocate()
   orig_pkt.length = pkt.length
   ffi.copy(orig_pkt.data, pkt.data, pkt.length)

   local code, fragments = fragmentv4.fragment(pkt, eth_size, 400)
   assert(code == fragmentv4.FRAGMENT_OK)
   assert(#fragments == 3)

   local function try(f)
      local code, pkt = fragmentv4.reassemble(f, eth_size)
      assert(code == fragmentv4.REASSEMBLE_OK, "returned: " .. code)
      assert(pkt.length == orig_pkt.length)

      for i = 1, pkt.length do
         assert(pkt.data[i] == orig_pkt.data[i],
                "byte["..i.."] expected="..orig_pkt.data[i].." got="..pkt.data[i])
      end
   end

   try { fragments[1], fragments[2], fragments[3] }
   try { fragments[2], fragments[3], fragments[1] }
   try { fragments[3], fragments[1], fragments[2] }

   try { fragments[3], fragments[2], fragments[1] }
   try { fragments[2], fragments[1], fragments[3] }
   try { fragments[1], fragments[3], fragments[2] }
end


function selftest()
   print("test: lwaftr.fragmentv4.fragment_ipv4")
   test_payload_1200_mtu_1500()
   test_payload_1200_mtu_1000()
   test_payload_1200_mtu_400()
   test_dont_fragment_flag()
   test_reassemble_pattern_fragments()
   test_vlan_tagging()

   local function testall(vlan_id)
      local suffix = " (no vlan tag)"
      if vlan_id then
         suffix = " (vlan id=" .. vlan_id .. ")"
      end
      print("test: lwaftr.fragmentv4.reassemble_ipv4" .. suffix)
      test_reassemble_unneeded(vlan_id)
      test_reassemble_two_missing_fragments(vlan_id)
      test_reassemble_three_missing_fragments(vlan_id)
      test_reassemble_two(vlan_id)
      test_reassemble_three(vlan_id)
   end
   testall(nil)
   testall(42)
end

-- Run tests when being invoked as a script from the command line.
if type((...)) == "nil" then selftest() end
