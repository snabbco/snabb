module(..., package.seeall)

local bit        = require("bit")
local ffi        = require("ffi")
local lib        = require("core.lib")
local packet     = require("core.packet")
local counter    = require("core.counter")
local link       = require("core.link")
local ipsum      = require("lib.checksum").ipsum
local ctable     = require('lib.ctable')
local ctablew    = require('apps.lwaftr.ctable_wrapper')
local lwutil     = require("apps.lwaftr.lwutil")
local lwcounter  = require("apps.lwaftr.lwcounter")

local REASSEMBLY_OK = 1
local FRAGMENT_MISSING = 2
local REASSEMBLY_INVALID = 3

-- IPv4 reassembly with RFC 5722's recommended exclusion of overlapping packets.
-- Defined in RFC 791.

-- Possible TODOs:
-- TODO: implement a timeout, and associated ICMP iff the fragment
-- with offset 0 was received
-- TODO: handle silently discarding fragments that arrive later if
-- an overlapping fragment was detected (keep a list for a few minutes?)
-- TODO: handle packets of > 10240 octets correctly...
-- TODO: test every branch of this

local receive, transmit = link.receive, link.transmit
local ntohs, htons = lib.ntohs, lib.htons

local function bit_mask(bits) return bit.lshift(1, bits) - 1 end

local ipv4_fragment_key_t = ffi.typeof[[
   struct {
      uint8_t src_addr[4];
      uint8_t dst_addr[4];
      uint32_t fragment_id;
   } __attribute__((packed))
]]

local ether_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint8_t  dhost[6];
   uint8_t  shost[6];
   uint16_t type;
} __attribute__((packed))
]]
local ipv4_header_t = ffi.typeof[[
struct {
   uint8_t version_and_ihl;               // version:4, ihl:4
   uint8_t dscp_and_ecn;                  // dscp:6, ecn:2
   uint16_t total_length;
   uint16_t id;
   uint16_t flags_and_fragment_offset;    // flags:3, fragment_offset:13
   uint8_t  ttl;
   uint8_t  protocol;
   uint16_t checksum;
   uint8_t  src_ip[4];
   uint8_t  dst_ip[4];
} __attribute__((packed))
]]
local ether_header_len = ffi.sizeof(ether_header_t)
local ipv4_fragment_offset_bits = 13
local ipv4_fragment_offset_mask = bit_mask(ipv4_fragment_offset_bits)
local ipv4_flag_more_fragments = 0x1
local ipv4_ihl_bits = 4
local ipv4_ihl_mask = bit_mask(ipv4_ihl_bits)

local ether_ipv4_header_t = ffi.typeof(
   'struct { $ ether; $ ipv4; } __attribute__((packed))',
   ether_header_t, ipv4_header_t)
local ether_ipv4_header_ptr_t = ffi.typeof('$*', ether_ipv4_header_t)

local function get_frag_len(frag)
   local h = ffi.cast(ether_ipv4_header_ptr_t, frag.data)
   return ntohs(h.ipv4.total_length)
end

local function get_frag_id(frag)
   local h = ffi.cast(ether_ipv4_header_ptr_t, frag.data)
   return ntohs(h.ipv4.id)
end

local function get_frag_start(frag)
   local h = ffi.cast(ether_ipv4_header_ptr_t, frag.data)
   local flags_and_fragment_offset = ntohs(h.ipv4.flags_and_fragment_offset)
   -- Fragment offset is expressed in 8-octet units.
   return bit.band(flags_and_fragment_offset, ipv4_fragment_offset_mask) * 8
end

local function is_last_fragment(frag)
   local h = ffi.cast(ether_ipv4_header_ptr_t, frag.data)
   local flags = bit.rshift(ntohs(h.ipv4.flags_and_fragment_offset),
                            ipv4_fragment_offset_bits)
   return bit.band(flags, ipv4_flag_more_fragments) == 0
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
local function fix_ipv4_checksum(h)
   local ihl = bit.band(h.version_and_ihl, ipv4_ihl_mask)
   h.checksum = 0
   h.checksum = htons(ipsum(ffi.cast('char*', h), ihl * 4, 0))
end

local function initialize_fragment_key(key, pkt)
   local h = ffi.cast(ether_ipv4_header_ptr_t, pkt.data)
   key.src_addr, key.dst_addr = h.ipv4.src_ip, h.ipv4.dst_ip
   key.fragment_id = ntohs(h.ipv4.id)
end

local function initialize_reassembly_buffer(buf, pkt)
   local h = ffi.cast(ether_ipv4_header_ptr_t, pkt.data)
   local ihl = bit.band(h.ipv4.version_and_ihl, ipv4_ihl_mask)
   local headers_len = ether_header_len + ihl * 4

   ffi.C.memset(buf, 0, ffi.sizeof(buf))
   buf.fragment_id = ntohs(h.ipv4.id)
   buf.reassembly_base = headers_len
   buf.running_length = headers_len

   ffi.copy(buf.reassembly_data, pkt.data, headers_len)
   -- Clear fragmentation data.
   local data_header = ffi.cast(ether_ipv4_header_ptr_t, buf.reassembly_data)
   data_header.ipv4.id, data_header.ipv4.flags_and_fragment_offset = 0, 0
end

Reassembler = {}
local reassembler_config_params = {
   -- Maximum number of in-progress reassemblies.  Each one uses about
   -- 11 kB of memory.
   max_ipv4_reassembly_packets = { default=20000 },
   -- Maximum number of fragments to reassemble.
   max_fragments_per_reassembly_packet = { default=40 },
}

function Reassembler:new(conf)
   local o = lib.parse(conf, reassembler_config_params)
   o.counters = lwcounter.init_counters()

   local max_occupy = 0.9
   local params = {
      key_type = ipv4_fragment_key_t,
      value_type = ffi.typeof([[
         struct {
             uint16_t fragment_starts[$];
             uint16_t fragment_ends[$];
             uint16_t fragment_count;
             uint16_t final_start;
             uint16_t reassembly_base;
             uint16_t fragment_id;
             uint32_t running_length; // bytes copied so far
             uint16_t reassembly_length; // analog to packet.length
             uint8_t reassembly_data[PACKET_PAYLOAD_SIZE];
         } __attribute((packed))]],
         o.max_fragments_per_reassembly_packet,
         o.max_fragments_per_reassembly_packet),
      initial_size = math.ceil(o.max_ipv4_reassembly_packets / max_occupy),
      max_occupancy_rate = max_occupy,
   }
   o.ctab = ctablew.new(params)
   o.scratch_fragment_key = params.key_type()
   o.scratch_reassembly_buffer = params.value_type()

   counter.set(o.counters["memuse-ipv4-frag-reassembly-buffer"],
               o.ctab:get_backing_size())
   return setmetatable(o, {__index=Reassembler})
end

function Reassembler:free_reassembly_buf_and_pkt(pkt)
   local key = self.scratch_fragment_key
   initialize_fragment_key(key, pkt)
   self.ctab:remove(key, false)
   packet.free(pkt)
end

function Reassembler:attempt_reassembly(reassembly_buf, fragment)
   local h = ffi.cast(ether_ipv4_header_ptr_t, fragment.data)
   local ihl = bit.band(h.ipv4.version_and_ihl, ipv4_ihl_mask)
   local headers_len = ether_header_len + ihl * 4
   local frags_table = self.ctab
   local frag_id = ntohs(h.ipv4.id)
   if frag_id ~= reassembly_buf.fragment_id then -- unreachable
      error("Impossible case reached in v4 reassembly") --REASSEMBLY_INVALID
   end

   local frag_start = get_frag_start(fragment)
   local frag_size = get_frag_len(fragment) - ihl * 4
   local fcount = reassembly_buf.fragment_count
   if fcount + 1 > self.max_fragments_per_reassembly_packet then
      -- too many fragments to reassembly this packet, assume malice
      self:free_reassembly_buf_and_pkt(fragment, frags_table)
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
         self:free_reassembly_buf_and_pkt(fragment, frags_table)
         return REASSEMBLY_INVALID
      else
         reassembly_buf.final_start = frag_start
      end
   end

   -- This is a massive layering violation. :/
   -- Specifically, it requires this file to know the details of struct packet.
   local skip_headers = reassembly_buf.reassembly_base
   local dst_offset = skip_headers + frag_start
   local last_ok = ffi.C.PACKET_PAYLOAD_SIZE
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
      local out = packet.from_pointer(
         reassembly_data, reassembly_buf.reassembly_length)
      local header = ffi.cast(ether_ipv4_header_ptr_t, out.data)
      header.ipv4.total_length = htons(out.length - ether_header_len)
      fix_ipv4_checksum(header.ipv4)
      self:free_reassembly_buf_and_pkt(fragment, frags_table)
      return REASSEMBLY_OK, out
   else
      packet.free(fragment)
      return restatus
   end
end

function Reassembler:cache_fragment(fragment)
   local frags_table = self.ctab
   local key = self.scratch_fragment_key
   initialize_fragment_key(key, fragment)
   local entry = frags_table:lookup_ptr(key)
   local did_evict = false
   if not entry then
      -- FIXME: Avoid the double lookup.
      local reassembly_buf = self.scratch_reassembly_buffer
      initialize_reassembly_buffer(reassembly_buf, fragment)
      local idx
      idx, did_evict = frags_table:add(key, reassembly_buf, false)
      entry = frags_table:lookup_ptr(key)
   end
   local status, maybe_pkt = self:attempt_reassembly(entry.value, fragment)
   return status, maybe_pkt, did_evict
end

function Reassembler:push ()
   local input, output = self.input.input, self.output.output
   local errors = self.output.errors

   for _ = 1, link.nreadable(input) do
      local pkt = link.receive(input)
      if lwutil.is_ipv4_fragment(pkt) then
         counter.add(self.counters["in-ipv4-frag-needs-reassembly"])
         local status, maybe_pkt, did_evict = self:cache_fragment(pkt)
         if did_evict then
            counter.add(self.counters["drop-ipv4-frag-random-evicted"])
         end

         if status == REASSEMBLY_OK then -- Reassembly was successful
            counter.add(self.counters["in-ipv4-frag-reassembled"])
            transmit(output, maybe_pkt)
         elseif status == FRAGMENT_MISSING then -- Nothing to do, wait.
         elseif status == REASSEMBLY_INVALID then
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
   local function make_test_packet(payload_size)
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

   local function permute_indices(lo, hi)
      if lo == hi then return {{hi}} end
      local ret = {}
      for _, tail in ipairs(permute_indices(lo + 1, hi)) do
         for pos = 1, #tail + 1 do
            local order = lib.deepcopy(tail)
            table.insert(order, pos, lo)
            table.insert(ret, order)
         end
      end
      return ret
   end

   for _, size in ipairs({100, 400, 1000, 1500, 2000}) do
      local pkt = make_test_packet(size)
      for _, mtu in ipairs({512, 1000, 1500}) do
         local fragments = fragment(pkt, mtu)
         for _, order in ipairs(permute_indices(1, #fragments)) do
            local reassembler = Reassembler:new {
               max_ipv4_reassembly_packets = 100,
               max_fragments_per_reassembly_packet = 20
            }
            reassembler.input = { input = link.new('reassembly input') }
            reassembler.output = { output = link.new('reassembly output') }
            local last = table.remove(order)
            for _, i in ipairs(order) do
               link.transmit(reassembler.input.input,
                             packet.clone(fragments[i]))
               reassembler:push()
               assert(link.empty(reassembler.output.output))
            end
            link.transmit(reassembler.input.input,
                          packet.clone(fragments[last]))
            reassembler:push()
            assert(link.nreadable(reassembler.output.output) == 1)
            local result = link.receive(reassembler.output.output)
            assert(pkt.length == result.length)
            for i = ether:sizeof(), result.length - 1 do
               local expected, actual = pkt.data[i], result.data[i]
               assert(expected == actual,
                      "pkt["..i.."] expected "..expected..", got "..actual)
            end
            packet.free(result)
            link.free(reassembler.input.output, 'reassembly input')
            link.free(reassembler.output.output, 'reassembly output')
         end
         for _, p in ipairs(fragments) do packet.free(p) end
      end
      packet.free(pkt)
   end

   print("selftest: ok")
end
