module(..., package.seeall)

local fragmentv4 = require("apps.lwaftr.fragmentv4")
local reassemble = require("apps.ipv4.reassemble")
local eth_proto = require("lib.protocol.ethernet")
local ip4_proto = require("lib.protocol.ipv4")
local packet = require("core.packet")
local band = require("bit").band
local ffi = require("ffi")

local ethertype_ipv4 = 0x0800

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
   eth_header:type(ethertype_ipv4)

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


local function test_reassemble_pattern_fragments()
   print("test:   length=1046 mtu=520 + reassembly")

   local pkt = make_ipv4_packet(1046 - ip4_proto:sizeof() - eth_proto:sizeof())
   pattern_fill(pkt.data + ip4_proto:sizeof() + eth_proto:sizeof(),
                pkt.length - ip4_proto:sizeof() - eth_proto:sizeof())

   local code, result = fragmentv4.fragment(pkt, 520)
   assert(code == fragmentv4.FRAGMENT_OK)
   assert(#result == 3)

   assert(pkt_payload_size(result[1]) + pkt_payload_size(result[2]) +
          pkt_payload_size(result[3]) == 1046 - ip4_proto:sizeof() - eth_proto:sizeof())

   local size = pkt_payload_size(result[1]) + pkt_payload_size(result[2]) + pkt_payload_size(result[3])
   local data = ffi.new("uint8_t[?]", size)

   for i = 1, #result do
      local pkt = result[i]
      local eth_size = eth_proto:sizeof()
      local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_size,
                                                pkt.length - eth_size)
      local ihl = ip4_header:ihl() * 4
      ffi.copy(data + pkt_frag_offset(result[i]),
               result[i].data + eth_proto:sizeof() + ihl,
               pkt_payload_size(result[i]))
   end
   pattern_check(data, size)
end

local function test_reassemble_two_missing_fragments()
   print("test:   two fragments (one missing)")
   local pkt = make_ipv4_packet(1200)
   local code, fragments = fragmentv4.fragment(pkt, 1000)
   assert(code == fragmentv4.FRAGMENT_OK)
   assert(#fragments == 2)

   local frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[1])))
   frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[2])))
end

local function test_reassemble_three_missing_fragments()
   print("test:   three fragments (one/two missing)")
   local pkt = make_ipv4_packet(1000)
   local code, fragments = fragmentv4.fragment(packet.clone(pkt), 400)
   assert(code == fragmentv4.FRAGMENT_OK)
   assert(#fragments == 3)

   local frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[1])))
   _, fragments = fragmentv4.fragment(packet.clone(pkt), 400)
   frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[2])))
   _, fragments = fragmentv4.fragment(packet.clone(pkt), 400)
   frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[3])))

   _, fragments = fragmentv4.fragment(packet.clone(pkt), 400)
   frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[1])))
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[2])))
   _, fragments = fragmentv4.fragment(packet.clone(pkt), 400)
   frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[1])))
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[3])))
   _, fragments = fragmentv4.fragment(packet.clone(pkt), 400)
   frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[2])))
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[3])))

   _, fragments = fragmentv4.fragment(packet.clone(pkt), 400)
   frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[2])))
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[1])))
   _, fragments = fragmentv4.fragment(packet.clone(pkt), 400)
   frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[3])))
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[1])))
   _, fragments = fragmentv4.fragment(packet.clone(pkt), 400)
   frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[2])))
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[3])))
end


function test_reassemble_two()
   print("test:   payload=1200 mtu=1000")
   local pkt = make_ipv4_packet(1200)
   assert(pkt.length > 1200, "packet shorter than payload size")

   -- Keep a copy of the packet, for comparisons
   local orig_pkt = packet.clone(pkt)
   -- A single error above this can lead to packets being on the freelist twice...
   assert(pkt ~= orig_pkt, "packets must be different")

   local code, fragments = fragmentv4.fragment(packet.clone(orig_pkt), 1000)
   assert(code == fragmentv4.FRAGMENT_OK)
   assert(#fragments == 2)
   assert(fragments[1].length ~= 0, "fragment[1] length must not be 0")
   assert(fragments[2].length ~= 0, "fragment[2] length must not be 0")

   local function try(f)
      local frag_table = reassemble.initialize_frag_table(20, 5)
      local code, pkt
      for i=1,#f do
         code, pkt = reassemble.cache_fragment(frag_table, f[i])
      end
      assert(code == reassemble.REASSEMBLY_OK, "returned: " .. code)
      assert(pkt.length == orig_pkt.length)

      for i = 1, pkt.length do
         if i ~= 24 and i ~= 25 then
            assert(pkt.data[i] == orig_pkt.data[i],
                   "byte["..i.."] expected="..orig_pkt.data[i].." got="..pkt.data[i])
         end
      end
   end

   try { fragments[1], fragments[2] }
   _, fragments = fragmentv4.fragment(packet.clone(orig_pkt), 1000)
   assert(fragments[1].length ~= 0, "fragment[1] length must not be 0")
   assert(fragments[2].length ~= 0, "fragment[2] length must not be 0")
   try { fragments[2], fragments[1] }
end


function test_reassemble_three()
   print("test:   payload=1000 mtu=400")
   local pkt = make_ipv4_packet(1000)

   -- Keep a copy of the packet, for comparisons
   local orig_pkt = packet.clone(pkt)

   local code, fragments = fragmentv4.fragment(packet.clone(pkt), 400)
   assert(code == fragmentv4.FRAGMENT_OK)
   assert(#fragments == 3)
   assert(orig_pkt.length == 1034, "wtf")

   local function try(f)
      local frag_table = reassemble.initialize_frag_table(20, 5)
      local code, pkt
      for i=1,#f do
         code, pkt = reassemble.cache_fragment(frag_table, f[i])
      end
      assert(code == reassemble.REASSEMBLY_OK, "returned: " .. code)
      assert(pkt.length == orig_pkt.length)

      for i = 1, pkt.length do
         if i ~= 24 and i ~= 25 then
            assert(pkt.data[i] == orig_pkt.data[i],
                   "byte["..i.."] expected="..orig_pkt.data[i].." got="..pkt.data[i])
         end
      end
   end

   try { fragments[1], fragments[2], fragments[3] }
   _, fragments = fragmentv4.fragment(packet.clone(pkt), 400)
   try { fragments[2], fragments[3], fragments[1] }
   _, fragments = fragmentv4.fragment(packet.clone(pkt), 400)
   try { fragments[3], fragments[1], fragments[2] }

   _, fragments = fragmentv4.fragment(packet.clone(pkt), 400)
   try { fragments[3], fragments[2], fragments[1] }
   _, fragments = fragmentv4.fragment(packet.clone(pkt), 400)
   try { fragments[2], fragments[1], fragments[3] }
   _, fragments = fragmentv4.fragment(packet.clone(pkt), 400)
   try { fragments[1], fragments[3], fragments[2] }
end


function selftest()
   print("selftest: apps.ipv4.reassemble_test")
   test_reassemble_pattern_fragments()
   test_reassemble_two_missing_fragments()
   test_reassemble_three_missing_fragments()
   test_reassemble_two()
   test_reassemble_three()
   print("selftest: ok")
end
