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
-- Returns a new packet containing an Ethernet frame with an IPv4
-- header followed by PAYLOAD_SIZE random bytes.
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
   test_reassemble_two_missing_fragments()
   test_reassemble_three_missing_fragments()
   test_reassemble_two()
   test_reassemble_three()
   print("selftest: ok")
end
