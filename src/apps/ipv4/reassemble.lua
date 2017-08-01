module(..., package.seeall)

local bit = require("bit")
local constants = require("apps.lwaftr.constants")
local ctable = require('lib.ctable')
local ctablew = require('apps.lwaftr.ctable_wrapper')
local ffi = require('ffi')
local lwutil = require("apps.lwaftr.lwutil")
local C = ffi.C
local packet = require("core.packet")
local lib = require("core.lib")
local ipsum = require("lib.checksum").ipsum

REASSEMBLY_OK = 1
FRAGMENT_MISSING = 2
REASSEMBLY_INVALID = 3

-- IPv4 reassembly with RFC 5722's recommended exclusion of overlapping packets.
-- Defined in RFC 791.

-- Possible TODOs:
-- TODO: implement a timeout, and associated ICMP iff the fragment
-- with offset 0 was received
-- TODO: handle silently discarding fragments that arrive later if
-- an overlapping fragment was detected (keep a list for a few minutes?)
-- TODO: handle packets of > 10240 octets correctly...
-- TODO: test every branch of this

local ehs, o_ipv4_identification, o_ipv4_flags,
o_ipv4_checksum, o_ipv4_total_length, o_ipv4_src_addr, o_ipv4_dst_addr =
constants.ethernet_header_size, constants.o_ipv4_identification,
constants.o_ipv4_flags, constants.o_ipv4_checksum,
constants.o_ipv4_total_length, constants.o_ipv4_src_addr,
constants.o_ipv4_dst_addr

local rd16, wr16, wr32 = lwutil.rd16, lwutil.wr16, lwutil.wr32
local get_ihl_from_offset = lwutil.get_ihl_from_offset
local uint16_ptr_t = ffi.typeof("uint16_t*")
local bxor, band = bit.bxor, bit.band
local packet_payload_size = C.PACKET_PAYLOAD_SIZE
local ntohs, htons = lib.ntohs, lib.htons

local ipv4_fragment_key_t = ffi.typeof[[
   struct {
      uint8_t src_addr[4];
      uint8_t dst_addr[4];
      uint32_t fragment_id;
   } __attribute__((packed))
]]

-- The fragment_starts and fragment_ends buffers are big enough for
-- non-malicious input. If a fragment requires more slots, refuse to
-- reassemble it.
local max_frags_per_packet
local ipv4_reassembly_buffer_t
local scratch_rbuf
local scratch_fragkey = ipv4_fragment_key_t()

local function get_frag_len(frag)
   return ntohs(rd16(frag.data + ehs + o_ipv4_total_length))
end

local function get_frag_id(frag)
   local o_id = ehs + o_ipv4_identification
   return ntohs(rd16(frag.data + o_id))
end

-- The most significant three bits are other information, and the
-- offset is expressed in 8-octet units, so just mask them off and * 8 it.
local function get_frag_start(frag)
   local o_fstart = ehs + o_ipv4_flags
   local raw_start = ntohs(rd16(frag.data + o_fstart))
   return band(raw_start, 0x1fff) * 8
end

-- This is the 'MF' bit of the IPv4 fragment header; it's the 3rd bit
-- of the flags.
local function is_last_fragment(frag)
   local o_flag = ehs + o_ipv4_flags
   return band(frag.data[o_flag], 0x20) == 0
end

local function get_key(fragment)
   local key = scratch_fragkey
   local o_src = ehs + o_ipv4_src_addr
   local o_dst = ehs + o_ipv4_dst_addr
   local o_id = ehs + o_ipv4_identification
   ffi.copy(key.src_addr, fragment.data + o_src, 4)
   ffi.copy(key.dst_addr, fragment.data + o_dst, 4)
   key.fragment_id = ntohs(rd16(fragment.data + o_id))
   return key
end

local function free_reassembly_buf_and_pkt(pkt, frags_table)
   local key = get_key(pkt)
   frags_table:remove(key, false)
   packet.free(pkt)
end

local function swap(array, i, j)
   local tmp = array[j]
   array[j] = array[i]
   array[i] = tmp
end

-- This is an insertion sort, and only called on 2+ element arrays
local function sort_array(array, last_index)
   for i=0,last_index do
      local j = i
      while j > 0 and array[j-1] > array[j] do
         swap(array, j, j-1)
         j = j - 1
      end
   end
end

local function verify_valid_offsets(reassembly_buf)
   if reassembly_buf.fragment_starts[0] ~= 0 then
      return false
   end
   for i=1,reassembly_buf.fragment_count-1 do
      if reassembly_buf.fragment_starts[i] ~= reassembly_buf.fragment_ends[i-1] then
         return false
      end
   end
   return true
end

local function reassembly_status(reassembly_buf)
   if reassembly_buf.final_start == 0 then
      return FRAGMENT_MISSING
   end
   if reassembly_buf.running_length ~= reassembly_buf.reassembly_length then
      return FRAGMENT_MISSING
   end
   if not verify_valid_offsets(reassembly_buf) then
      return REASSEMBLY_INVALID
   end
   return REASSEMBLY_OK
end

-- IPv4 requires recalculating an embedded checksum.
local function fix_pkt_checksum(pkt)
   local ihl = get_ihl_from_offset(pkt, ehs)
   local checksum_offset = ehs + o_ipv4_checksum
   wr16(pkt.data + checksum_offset, 0)
   wr16(pkt.data + checksum_offset,
        htons(ipsum(pkt.data + ehs, ihl, 0)))
end

local function attempt_reassembly(frags_table, reassembly_buf, fragment)
   local ihl = get_ihl_from_offset(fragment, ehs)
   local frag_id = get_frag_id(fragment)
   if frag_id ~= reassembly_buf.fragment_id then -- unreachable
      error("Impossible case reached in v4 reassembly") --REASSEMBLY_INVALID
   end

   local frag_start = get_frag_start(fragment)
   local frag_size = get_frag_len(fragment) - ihl
   local fcount = reassembly_buf.fragment_count
   if fcount + 1 > max_frags_per_packet then
      -- too many fragments to reassembly this packet, assume malice
      free_reassembly_buf_and_pkt(fragment, frags_table)
      return REASSEMBLY_INVALID
   end
   reassembly_buf.fragment_starts[fcount] = frag_start
   reassembly_buf.fragment_ends[fcount] = frag_start + frag_size
   if reassembly_buf.fragment_starts[fcount] <
      reassembly_buf.fragment_starts[fcount - 1] then
      sort_array(reassembly_buf.fragment_starts, fcount)
      sort_array(reassembly_buf.fragment_ends, fcount)
   end
   reassembly_buf.fragment_count = fcount + 1
   if is_last_fragment(fragment) then
      if reassembly_buf.final_start ~= 0 then
         -- There cannot be 2+ final fragments
         free_reassembly_buf_and_pkt(fragment, frags_table)
         return REASSEMBLY_INVALID
      else
         reassembly_buf.final_start = frag_start
      end
   end

   -- This is a massive layering violation. :/
   -- Specifically, it requires this file to know the details of struct packet.
   local skip_headers = reassembly_buf.reassembly_base
   local dst_offset = skip_headers + frag_start
   local last_ok = packet_payload_size
   if dst_offset + frag_size > last_ok then
      -- Prevent a buffer overflow. The relevant RFC allows hosts to silently discard
      -- reassemblies above a certain rather small size, smaller than this.
      return REASSEMBLY_INVALID
   end
   local reassembly_data = reassembly_buf.reassembly_data
   ffi.copy(reassembly_data + dst_offset,
            fragment.data + skip_headers,
            frag_size)
   local max_data_offset = skip_headers + frag_start + frag_size
   reassembly_buf.reassembly_length = math.max(reassembly_buf.reassembly_length,
                                               max_data_offset)
   reassembly_buf.running_length = reassembly_buf.running_length + frag_size

   local restatus = reassembly_status(reassembly_buf)
   if restatus == REASSEMBLY_OK then
      local pkt_len = htons(reassembly_buf.reassembly_length - ehs)
      local o_len = ehs + o_ipv4_total_length
      wr16(reassembly_data + o_len, pkt_len)
      local reassembled_packet = packet.from_pointer(
	 reassembly_buf.reassembly_data, reassembly_buf.reassembly_length)
      fix_pkt_checksum(reassembled_packet)
      free_reassembly_buf_and_pkt(fragment, frags_table)
      return REASSEMBLY_OK, reassembled_packet
   else
      packet.free(fragment)
      return restatus
   end
end

local function packet_to_reassembly_buffer(pkt)
   local reassembly_buf = scratch_rbuf
   C.memset(reassembly_buf, 0, ffi.sizeof(ipv4_reassembly_buffer_t))
   local ihl = get_ihl_from_offset(pkt, ehs)
   reassembly_buf.fragment_id = get_frag_id(pkt)
   reassembly_buf.reassembly_base = ehs + ihl

   local headers_len = ehs + ihl
   local re_data = reassembly_buf.reassembly_data
   ffi.copy(re_data, pkt.data, headers_len)
   wr32(re_data + ehs + o_ipv4_identification, 0) -- Clear fragmentation data
   reassembly_buf.running_length = headers_len
   return reassembly_buf
end

function initialize_frag_table(max_fragmented_packets, max_pkt_frag)
   -- Initialize module-scoped variables
   max_frags_per_packet = max_pkt_frag
   ipv4_reassembly_buffer_t = ffi.typeof([[
   struct {
       uint16_t fragment_starts[$];
       uint16_t fragment_ends[$];
       uint16_t fragment_count;
       uint16_t final_start;
       uint16_t reassembly_base;
       uint16_t fragment_id;
       uint32_t running_length; // bytes copied so far
       uint16_t reassembly_length; // analog to packet.length
       uint8_t reassembly_data[$];
   } __attribute((packed))]],
   max_frags_per_packet, max_frags_per_packet, packet.max_payload)
   scratch_rbuf = ipv4_reassembly_buffer_t()

   local max_occupy = 0.9
   local params = {
      key_type = ffi.typeof(ipv4_fragment_key_t),
      value_type = ffi.typeof(ipv4_reassembly_buffer_t),
      initial_size = math.ceil(max_fragmented_packets / max_occupy),
      max_occupancy_rate = max_occupy,
   }
   return ctablew.new(params)
end

function cache_fragment(frags_table, fragment)
   local key = get_key(fragment)
   local ptr = frags_table:lookup_ptr(key)
   local ej = false
   if not ptr then
      local reassembly_buf = packet_to_reassembly_buffer(fragment)
      _, ej = frags_table:add_with_random_ejection(key, reassembly_buf, false)
      ptr = frags_table:lookup_ptr(key)
   end
   local status, maybe_pkt = attempt_reassembly(frags_table, ptr.value, fragment)
   return status, maybe_pkt, ej
end

Reassembler = {}

function Reassembler:new(conf)
   local max_ipv4_reassembly_packets = assert(conf.max_ipv4_reassembly_packets)
   local max_fragments_per_reassembly_packet = assert(conf.max_fragments_per_reassembly_packet)
   local o = {
      counters = lwcounter.init_counters(),
      ctab = fragv4_h.initialize_frag_table(max_ipv4_reassembly_packets,
         max_fragments_per_reassembly_packet),
   }
   counter.set(o.counters["memuse-ipv4-frag-reassembly-buffer"],
               o.ctab:get_backing_size())
   return setmetatable(o, {__index=Reassembler})
end

function Reassembler:cache_fragment(fragment)
   return fragv4_h.cache_fragment(self.ctab, fragment)
end

function Reassembler:push ()
   local input, output = self.input.input, self.output.output
   local errors = self.output.errors

   for _ = 1, link.nreadable(input) do
      local pkt = receive(input)
      if is_ipv4_fragment(pkt) then
         counter.add(self.counters["in-ipv4-frag-needs-reassembly"])
         local status, maybe_pkt, ejected = self:cache_fragment(pkt)
         if ejected then
            counter.add(self.counters["drop-ipv4-frag-random-evicted"])
         end

         if status == fragv4_h.REASSEMBLY_OK then -- Reassembly was successful
            counter.add(self.counters["in-ipv4-frag-reassembled"])
            transmit(output, maybe_pkt)
         elseif status == fragv4_h.FRAGMENT_MISSING then -- Nothing to do, wait.
         elseif status == fragv4_h.REASSEMBLY_INVALID then
            counter.add(self.counters["drop-ipv4-frag-invalid-reassembly"])
            if maybe_pkt then -- This is an ICMP packet
               transmit(errors, maybe_pkt)
            end
         else -- unreachable
            packet.free(pkt)
         end
      else
         -- Forward all packets that aren't IPv4 fragments.
         counter.add(self.counters["in-ipv4-frag-reassembly-unneeded"])
         transmit(output, pkt)
      end
   end
end

function selftest()
   print("selftest: apps.ipv4.reassemble")

   local datagram   = require("lib.protocol.datagram")
   local ether      = require("lib.protocol.ethernet")
   local ipv4       = require("lib.protocol.ipv4")
   local ipv4_apps  = require("apps.lwaftr.ipv4_apps")

   local ethertype_ipv4 = 0x0800

   local function random_ipv4() return lib.random_bytes(4) end
   local function random_mac() return lib.random_bytes(6) end

   -- Returns a new packet containing an Ethernet frame with an IPv4
   -- header followed by PAYLOAD_SIZE random bytes.
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

      local frag_table = initialize_frag_table(20, 5)
      assert(FRAGMENT_MISSING ==
             (cache_fragment(frag_table, fragments[1])))
      frag_table = initialize_frag_table(20, 5)
      assert(FRAGMENT_MISSING ==
             (cache_fragment(frag_table, fragments[2])))
   end

   local function test_reassemble_three_missing_fragments()
      print("test:   three fragments (one/two missing)")
      local pkt = make_ipv4_packet(1000)
      local fragments = fragment(pkt, 400)
      assert(#fragments == 3)

      local frag_table = initialize_frag_table(20, 5)
      assert(FRAGMENT_MISSING ==
             (cache_fragment(frag_table, fragments[1])))
      fragments = fragment(pkt, 400)
      frag_table = initialize_frag_table(20, 5)
      assert(FRAGMENT_MISSING ==
             (cache_fragment(frag_table, fragments[2])))
      fragments = fragment(pkt, 400)
      frag_table = initialize_frag_table(20, 5)
      assert(FRAGMENT_MISSING ==
             (cache_fragment(frag_table, fragments[3])))

      fragments = fragment(pkt, 400)
      frag_table = initialize_frag_table(20, 5)
      assert(FRAGMENT_MISSING ==
             (cache_fragment(frag_table, fragments[1])))
      assert(FRAGMENT_MISSING ==
             (cache_fragment(frag_table, fragments[2])))
      fragments = fragment(pkt, 400)
      frag_table = initialize_frag_table(20, 5)
      assert(FRAGMENT_MISSING ==
             (cache_fragment(frag_table, fragments[1])))
      assert(FRAGMENT_MISSING ==
             (cache_fragment(frag_table, fragments[3])))
      fragments = fragment(pkt, 400)
      frag_table = initialize_frag_table(20, 5)
      assert(FRAGMENT_MISSING ==
             (cache_fragment(frag_table, fragments[2])))
      assert(FRAGMENT_MISSING ==
             (cache_fragment(frag_table, fragments[3])))

      fragments = fragment(pkt, 400)
      frag_table = initialize_frag_table(20, 5)
      assert(FRAGMENT_MISSING ==
             (cache_fragment(frag_table, fragments[2])))
      assert(FRAGMENT_MISSING ==
             (cache_fragment(frag_table, fragments[1])))
      fragments = fragment(pkt, 400)
      frag_table = initialize_frag_table(20, 5)
      assert(FRAGMENT_MISSING ==
             (cache_fragment(frag_table, fragments[3])))
      assert(FRAGMENT_MISSING ==
             (cache_fragment(frag_table, fragments[1])))
      fragments = fragment(pkt, 400)
      frag_table = initialize_frag_table(20, 5)
      assert(FRAGMENT_MISSING ==
             (cache_fragment(frag_table, fragments[2])))
      assert(FRAGMENT_MISSING ==
             (cache_fragment(frag_table, fragments[3])))
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
         local frag_table = initialize_frag_table(20, 5)
         local code, p
         for i=1,#f do
            code, p = cache_fragment(frag_table, f[i])
         end
         assert(code == REASSEMBLY_OK, "returned: " .. code)
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
         local frag_table = initialize_frag_table(20, 5)
         local code, p
         for i=1,#f do
            code, p = cache_fragment(frag_table, f[i])
         end
         assert(code == REASSEMBLY_OK, "returned: " .. code)
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
   test_reassemble_two_missing_fragments()
   test_reassemble_three_missing_fragments()
   test_reassemble_two()
   test_reassemble_three()

   print("selftest: bis")
   initialize_frag_table(20, 20)
   local rbuf1 = ffi.new(ipv4_reassembly_buffer_t)
   local rbuf2 = ffi.new(ipv4_reassembly_buffer_t)
   rbuf1.fragment_starts[0] = 10
   rbuf1.fragment_starts[1] = 100
   rbuf2.fragment_starts[0] = 100
   rbuf2.fragment_starts[1] = 10
   sort_array(rbuf1.fragment_starts, 1)
   sort_array(rbuf2.fragment_starts, 1)
   assert(0 == C.memcmp(rbuf1.fragment_starts, rbuf2.fragment_starts, 4))

   local rbuf3 = ffi.new(ipv4_reassembly_buffer_t)
   rbuf3.fragment_starts[0] = 5
   rbuf3.fragment_starts[1] = 10
   rbuf3.fragment_starts[2] = 100
   rbuf1.fragment_starts[2] = 5
   sort_array(rbuf1.fragment_starts, 2)
   assert(0 == C.memcmp(rbuf1.fragment_starts, rbuf3.fragment_starts, 6))
   print("selftest: ok")
end
