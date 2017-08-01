module(..., package.seeall)

local bit        = require("bit")
local ffi        = require("ffi")
local lib        = require("core.lib")
local packet     = require("core.packet")
local datagram   = require("lib.protocol.datagram")
local ether      = require("lib.protocol.ethernet")
local ipv4       = require("lib.protocol.ipv4")
local ipv4_apps  = require("apps.lwaftr.ipv4_apps")
local reassemble = require("apps.ipv4.reassemble")

local ethertype_ipv4 = 0x0800

local function random_ipv4() return lib.random_bytes(4) end
local function random_mac() return lib.random_bytes(6) end

--
-- Returns a new packet, which contains an Ethernet frame, with an IPv4 header,
-- followed by a payload of "payload_size" random bytes.
--
local function make_ipv4_packet(payload_size)
   local pkt = packet.from_pointer(lib.random_bytes(payload_size),
                                   payload_size)
   local eth_h = ether:new({ src = random_mac(), dst = random_mac(),
                             type = ethertype_ipv4 })
   local ip_h  = ipv4:new({ src = random_ipv4(), dst = random_ipv4(),
                            protocol = 0xff, ttl = 64 })
   ip_h:total_length(ip_h:sizeof() + pkt.length)
   ip_h:checksum()

   local dgram = datagram:new(pkt)
   dgram:push(ip_h)
   dgram:push(eth_h)
   return dgram:packet()
end

local function payload_size(pkt)
   return pkt.length - ether:sizeof() - ipv4:sizeof()
end

local function pkt_frag_offset(pkt)
   assert(pkt.length >= (ether:sizeof() + ipv4:sizeof()))
   local eth_size = ether:sizeof()
   local ip4_header = ipv4:new_from_mem(pkt.data + eth_size,
                                        pkt.length - eth_size)
   return ip4_header:frag_off() * 8
end

--
-- Checks that "frag_pkt" is a valid fragment of the "orig_pkt" packet.
--
local function check_packet_fragment(orig_pkt, frag_pkt, is_last_fragment)
   -- Ethernet fields
   local orig_hdr = ether:new_from_mem(orig_pkt.data, orig_pkt.length)
   local frag_hdr = ether:new_from_mem(frag_pkt.data, frag_pkt.length)
   assert(orig_hdr:src_eq(frag_hdr:src()))
   assert(orig_hdr:dst_eq(frag_hdr:dst()))
   assert(orig_hdr:type() == frag_hdr:type())

   -- IPv4 fields
   local eth_size = ether:sizeof()
   orig_hdr = ipv4:new_from_mem(orig_pkt.data + eth_size,
                                orig_pkt.length - eth_size)
   frag_hdr = ipv4:new_from_mem(frag_pkt.data + eth_size,
                                frag_pkt.length - eth_size)
   assert(orig_hdr:ihl() == frag_hdr:ihl())
   assert(orig_hdr:dscp() == frag_hdr:dscp())
   assert(orig_hdr:ecn() == frag_hdr:ecn())
   assert(orig_hdr:ttl() == frag_hdr:ttl())
   assert(orig_hdr:protocol() == frag_hdr:protocol())
   assert(orig_hdr:src_eq(frag_hdr:src()))
   assert(orig_hdr:dst_eq(frag_hdr:dst()))

   assert(payload_size(frag_pkt) == frag_pkt.length - eth_size - ipv4:sizeof())

   if is_last_fragment then
      assert(bit.band(frag_hdr:flags(), 0x1) == 0x0)
   else
      assert(bit.band(frag_hdr:flags(), 0x1) == 0x1)
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


local function fragment(pkt, mtu)
   local fragment = ipv4_apps.Fragmenter:new({mtu=mtu})
   fragment.input = { input = link.new('fragment input') }
   fragment.output = { output = link.new('fragment output') }
   link.transmit(fragment.input.input, packet.clone(pkt))
   fragment:push()
   local ret = {}
   while not link.empty(fragment.output.output) do
      table.insert(ret, link.receive(fragment.output.output))
   end
   link.free(fragment.input.input, 'fragment input')
   link.free(fragment.output.output, 'fragment output')
   return ret
end

local function test_reassemble_fragments()
   print("test:   length=1046 mtu=520 + reassembly")
   local pkt = make_ipv4_packet(1046 - ipv4:sizeof() - ether:sizeof())
   pattern_fill(pkt.data + ipv4:sizeof() + ether:sizeof(),
                pkt.length - ipv4:sizeof() - ether:sizeof())

   local result = fragment(pkt, 520)
   packet.free(pkt)
   assert(#result == 3)

   assert(payload_size(result[1]) + payload_size(result[2]) +
          payload_size(result[3]) == 1046 - ipv4:sizeof() - ether:sizeof())

   local size = payload_size(result[1]) + payload_size(result[2]) + payload_size(result[3])
   local data = ffi.new("uint8_t[?]", size)

   for i = 1, #result do
      local pkt = result[i]
      local eth_size = ether:sizeof()
      local ip4_header = ipv4:new_from_mem(pkt.data + eth_size,
                                           pkt.length - eth_size)
      local ihl = ip4_header:ihl() * 4
      ffi.copy(data + pkt_frag_offset(result[i]),
               result[i].data + ether:sizeof() + ihl,
               payload_size(result[i]))
   end
   pattern_check(data, size)
end

local function test_reassemble_two_missing_fragments()
   print("test:   two fragments (one missing)")
   local pkt = make_ipv4_packet(1200)
   local fragments = fragment(pkt, 1000)
   packet.free(pkt)
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
   local fragments = fragment(pkt, 400)
   assert(#fragments == 3)

   local frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[1])))
   fragments = fragment(pkt, 400)
   frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[2])))
   fragments = fragment(pkt, 400)
   frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[3])))

   fragments = fragment(pkt, 400)
   frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[1])))
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[2])))
   fragments = fragment(pkt, 400)
   frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[1])))
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[3])))
   fragments = fragment(pkt, 400)
   frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[2])))
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[3])))

   fragments = fragment(pkt, 400)
   frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[2])))
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[1])))
   fragments = fragment(pkt, 400)
   frag_table = reassemble.initialize_frag_table(20, 5)
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[3])))
   assert(reassemble.FRAGMENT_MISSING ==
          (reassemble.cache_fragment(frag_table, fragments[1])))
   fragments = fragment(pkt, 400)
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

   local fragments = fragment(pkt, 1000)
   assert(#fragments == 2)
   assert(fragments[1].length ~= 0, "fragment[1] length must not be 0")
   assert(fragments[2].length ~= 0, "fragment[2] length must not be 0")

   local function try(f)
      local frag_table = reassemble.initialize_frag_table(20, 5)
      local code, p
      for i=1,#f do
         code, p = reassemble.cache_fragment(frag_table, f[i])
      end
      assert(code == reassemble.REASSEMBLY_OK, "returned: " .. code)
      assert(p.length == pkt.length)

      for i = 1, p.length do
         if i ~= 24 and i ~= 25 then
            assert(p.data[i] == pkt.data[i],
                   "byte["..i.."] expected="..pkt.data[i].." got="..p.data[i])
         end
      end
   end

   try { fragments[1], fragments[2] }
   fragments = fragment(pkt, 1000)
   assert(fragments[1].length ~= 0, "fragment[1] length must not be 0")
   assert(fragments[2].length ~= 0, "fragment[2] length must not be 0")
   try { fragments[2], fragments[1] }
end


function test_reassemble_three()
   print("test:   payload=1000 mtu=400")
   local pkt = make_ipv4_packet(1000)

   local fragments = fragment(pkt, 400)
   assert(#fragments == 3)
   assert(pkt.length == 1034, "wtf")

   local function try(f)
      local frag_table = reassemble.initialize_frag_table(20, 5)
      local code, p
      for i=1,#f do
         code, p = reassemble.cache_fragment(frag_table, f[i])
      end
      assert(code == reassemble.REASSEMBLY_OK, "returned: " .. code)
      assert(p.length == pkt.length)

      for i = 0, p.length-1 do
         if i ~= 24 and i ~= 25 then
            assert(p.data[i] == pkt.data[i],
                   "byte["..i.."] expected="..pkt.data[i].." got="..p.data[i])
         end
      end
   end

   try { fragments[1], fragments[2], fragments[3] }
   fragments = fragment(pkt, 400)
   try { fragments[2], fragments[3], fragments[1] }
   fragments = fragment(pkt, 400)
   try { fragments[3], fragments[1], fragments[2] }

   fragments = fragment(pkt, 400)
   try { fragments[3], fragments[2], fragments[1] }
   fragments = fragment(pkt, 400)
   try { fragments[2], fragments[1], fragments[3] }
   fragments = fragment(pkt, 400)
   try { fragments[1], fragments[3], fragments[2] }
end


function selftest()
   print("selftest: apps.ipv4.reassemble_test")
   test_reassemble_fragments()
   test_reassemble_two_missing_fragments()
   test_reassemble_three_missing_fragments()
   test_reassemble_two()
   test_reassemble_three()
   print("selftest: ok")
end
