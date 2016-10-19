module(..., package.seeall)

local bit = require("bit")
local constants = require("apps.lwaftr.constants")
local ctablew = require('apps.lwaftr.ctable_wrapper')
local ctable = require('lib.ctable')
local ffi = require('ffi')
local lwutil = require("apps.lwaftr.lwutil")
local C = ffi.C
local packet = require("core.packet")
local lib = require("core.lib")

REASSEMBLY_OK = 1
FRAGMENT_MISSING = 2
REASSEMBLY_INVALID = 3

-- IPv6 reassembly, as per https://tools.ietf.org/html/rfc2460#section-4.5
-- with RFC 5722's recommended exclusion of overlapping packets.

-- Possible TODOs:
-- TODO: handle the 60-second timeout, and associated ICMP iff the fragment
-- with offset 0 was received
-- TODO: handle silently discarding fragments that arrive later if
-- an overlapping fragment was detected (keep a list for a few minutes?)
-- TODO: send ICMP parameter problem code 0 if needed, as per RFC2460
-- (if the fragment's data isn't a multiple of 8 octets and M=1, or
-- if the length of the reassembled packet would exceed 65535 octets)
-- TODO: handle packets of > 10240 octets correctly...
-- TODO: test every branch of this

local ehs, ipv6_fixed_header_size, o_ipv6_src_addr, o_ipv6_dst_addr,
o_ipv6_frag_offset, o_ipv6_frag_id, o_ipv6_payload_len, ipv6_frag_header_size,
o_ipv6_next_header =
constants.ethernet_header_size, constants.ipv6_fixed_header_size,
constants.o_ipv6_src_addr, constants.o_ipv6_dst_addr,
constants.o_ipv6_frag_offset, constants.o_ipv6_frag_id,
constants.o_ipv6_payload_len, constants.ipv6_frag_header_size,
constants.o_ipv6_next_header

local hash_32 = ctable.hash_32
local rd16, rd32 = lwutil.rd16, lwutil.rd32
local uint32_ptr_t = ffi.typeof("uint32_t*")
local bxor, band = bit.bxor, bit.band
local packet_payload_size = C.PACKET_PAYLOAD_SIZE
local ntohs, ntohl = lib.ntohs, lib.ntohl

local ipv6_fragment_key_t = ffi.typeof[[
   struct {
      uint8_t src_addr[16];
      uint8_t dst_addr[16];
      uint32_t fragment_id;
   } __attribute__((packed))
]]

-- The fragment_starts and fragment_ends buffers are big enough for
-- non-malicious input. If a fragment requires more slots, refuse to
-- reassemble it.
local max_frags_per_packet
local ipv6_reassembly_buffer_t
local scratch_rbuf
local scratch_fragkey = ipv6_fragment_key_t()

local function get_frag_len(frag)
   local ipv6_payload_len = ehs + o_ipv6_payload_len
   return ntohs(rd16(frag.data + ipv6_payload_len)) - ipv6_frag_header_size
end

local function get_frag_id(frag)
   local o_id = ehs + ipv6_fixed_header_size + o_ipv6_frag_id
   return ntohl(rd32(frag.data + o_id))
end

-- The least significant three bits are other information, but the
-- offset is expressed in 8-octet units, so just mask them off.
local function get_frag_start(frag)
   local o_fstart = ehs + ipv6_fixed_header_size + o_ipv6_frag_offset
   local raw_start = ntohs(rd16(frag.data + o_fstart))
   local start = band(raw_start, 0xfff8)
   return start
end

-- This is the 'M' bit of the IPv6 fragment header, in the
-- least significant bit of the 4th byte
local function is_last_fragment(frag)
   local ipv6_frag_more_offset = ehs + ipv6_fixed_header_size + 3
   return band(frag.data[ipv6_frag_more_offset], 1) == 0
end

local function get_key(fragment)
   local key = scratch_fragkey
   local o_src = ehs + o_ipv6_src_addr
   local o_dst = ehs + o_ipv6_dst_addr
   local o_id = ehs + ipv6_fixed_header_size + o_ipv6_frag_id
   ffi.copy(key.src_addr, fragment.data + o_src, 16)
   ffi.copy(key.dst_addr, fragment.data + o_dst, 16)
   key.fragment_id = ntohl(rd32(fragment.data + o_id))
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

local function attempt_reassembly(frags_table, reassembly_buf, fragment)
   local frag_id = get_frag_id(fragment)
   if frag_id ~= reassembly_buf.fragment_id then -- unreachable
      error("Impossible case reached in v6 reassembly") --REASSEMBLY_INVALID
   end

   local frag_start = get_frag_start(fragment)
   local frag_size = get_frag_len(fragment)
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
   ffi.copy(reassembly_buf.reassembly_data + dst_offset,
            fragment.data + skip_headers + ipv6_frag_header_size,
            frag_size)
   local max_data_offset = skip_headers + frag_start + frag_size
   reassembly_buf.reassembly_length = math.max(reassembly_buf.reassembly_length,
                                               max_data_offset)
   reassembly_buf.running_length = reassembly_buf.running_length + frag_size

   local restatus = reassembly_status(reassembly_buf)
   if restatus == REASSEMBLY_OK then
      local reassembled_packet = packet.from_pointer(
	 reassembly_buf.reassembly_data, reassembly_buf.reassembly_length)
      free_reassembly_buf_and_pkt(fragment, frags_table)
      return REASSEMBLY_OK, reassembled_packet
   else
      packet.free(fragment)
      return restatus
   end
end

local function packet_to_reassembly_buffer(pkt)
   local reassembly_buf = scratch_rbuf
   C.memset(reassembly_buf, 0, ffi.sizeof(ipv6_reassembly_buffer_t))
   reassembly_buf.fragment_id = get_frag_id(pkt)
   reassembly_buf.reassembly_base = ehs + ipv6_fixed_header_size

   local reassembly_data = reassembly_buf.reassembly_data
   local headers_len = ehs + ipv6_fixed_header_size
   ffi.copy(reassembly_data, pkt.data, headers_len)
   reassembly_buf.running_length = headers_len

   --Take the next header information from the fragment
   local next_header_base_offset = ehs + o_ipv6_next_header
   local next_header_frag_offset = ehs + ipv6_fixed_header_size -- +0
   reassembly_data[next_header_base_offset] = pkt.data[next_header_frag_offset]

   return reassembly_buf
end

-- The key is 288 bits: source IPv6 address, destination IPv6 address, and
-- the identification field from the IPv6 fragmentation header.
local function hash_ipv6(key)
   local hash = 0
   local to_hash = ffi.cast(uint32_ptr_t, key)
   for i=0,8 do
      local current = to_hash[i]
      hash = hash_32(bxor(hash, hash_32(current)))
   end
   return hash
end

function initialize_frag_table(max_fragmented_packets, max_pkt_frag)
   -- Initialize module-scoped variables
   max_frags_per_packet = max_pkt_frag
   ipv6_reassembly_buffer_t = ffi.typeof([[
   struct {
       uint16_t fragment_starts[$];
       uint16_t fragment_ends[$];
       uint16_t fragment_count;
       uint16_t final_start;
       uint16_t reassembly_base;
       uint32_t fragment_id;
       uint32_t running_length; // bytes copied so far
       uint16_t reassembly_length; // analog to packet.length
       uint8_t reassembly_data[$];
   } __attribute((packed))]],
   max_frags_per_packet, max_frags_per_packet, packet.max_payload)
   scratch_rbuf = ipv6_reassembly_buffer_t()

   local max_occupy = 0.9
   local params = {
      key_type = ffi.typeof(ipv6_fragment_key_t),
      value_type = ffi.typeof(ipv6_reassembly_buffer_t),
      hash_fn = hash_ipv6,
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

function selftest()
   initialize_frag_table(20, 20)
   local rbuf1 = ffi.new(ipv6_reassembly_buffer_t)
   local rbuf2 = ffi.new(ipv6_reassembly_buffer_t)
   rbuf1.fragment_starts[0] = 10
   rbuf1.fragment_starts[1] = 100
   rbuf2.fragment_starts[0] = 100
   rbuf2.fragment_starts[1] = 10
   sort_array(rbuf1.fragment_starts, 1)
   sort_array(rbuf2.fragment_starts, 1)
   assert(0 == C.memcmp(rbuf1.fragment_starts, rbuf2.fragment_starts, 4))

   local rbuf3 = ffi.new(ipv6_reassembly_buffer_t)
   rbuf3.fragment_starts[0] = 5
   rbuf3.fragment_starts[1] = 10
   rbuf3.fragment_starts[2] = 100
   rbuf1.fragment_starts[2] = 5
   sort_array(rbuf1.fragment_starts, 2)
   assert(0 == C.memcmp(rbuf1.fragment_starts, rbuf3.fragment_starts, 6))
end
