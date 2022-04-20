-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- IPv4 reassembly (RFC 791)
--
-- This reassembly implementation will abort ongoing reassemblies if
-- it sees overlapping fragments.  This follows the recommendation of
-- RFC 5722, which although it is given specifically for IPv6, it
-- applies just as well to IPv4.
--
-- Reassembly failures are currently silent.  We could implement
-- timeouts and then we could issue "timeout exceeded" ICMP errors if
-- needed.

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
local alarms     = require('lib.yang.alarms')
local S          = require('syscall')

local CounterAlarm = alarms.CounterAlarm
local ntohs, htons = lib.ntohs, lib.htons

local function bit_mask(bits) return bit.lshift(1, bits) - 1 end

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
local ether_type_ipv4 = 0x0800
local ipv4_fragment_offset_bits = 13
local ipv4_fragment_offset_mask = bit_mask(ipv4_fragment_offset_bits)
local ipv4_flag_more_fragments = 0x1
-- If a packet has the "more fragments" flag set, or the fragment
-- offset is non-zero, it is a fragment.
local ipv4_is_fragment_mask = bit.bor(
   ipv4_fragment_offset_mask,
   bit.lshift(ipv4_flag_more_fragments, ipv4_fragment_offset_bits))
local ipv4_ihl_bits = 4
local ipv4_ihl_mask = bit_mask(ipv4_ihl_bits)

local ether_ipv4_header_t = ffi.typeof(
   'struct { $ ether; $ ipv4; } __attribute__((packed))',
   ether_header_t, ipv4_header_t)
local ether_ipv4_header_ptr_t = ffi.typeof('$*', ether_ipv4_header_t)

-- Precondition: packet already has IPv4 ethertype.
local function ipv4_packet_has_valid_length(h, len)
   if len < ffi.sizeof(ether_ipv4_header_t) then return false end
   local ihl = bit.band(h.ipv4.version_and_ihl, ipv4_ihl_mask)
   if ihl < 5 then return false end
   return ntohs(h.ipv4.total_length) <= len - ether_header_len
end

-- IPv4 requires recalculating an embedded checksum.
local function fix_ipv4_checksum(h)
   local ihl = bit.band(h.version_and_ihl, ipv4_ihl_mask)
   h.checksum = 0
   h.checksum = htons(ipsum(ffi.cast('char*', h), ihl * 4, 0))
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

local function verify_valid_offsets(reassembly)
   if reassembly.fragment_starts[0] ~= 0 then
      return false
   end
   for i=1,reassembly.fragment_count-1 do
      if reassembly.fragment_starts[i] ~= reassembly.fragment_ends[i-1] then
         return false
      end
   end
   return true
end

Reassembler = {}
Reassembler.shm = {
   ["in-ipv4-frag-needs-reassembly"]      = {counter},
   ["in-ipv4-frag-reassembled"]           = {counter},
   ["in-ipv4-frag-reassembly-unneeded"]   = {counter},
   ["drop-ipv4-frag-invalid-reassembly"]  = {counter},
   ["drop-ipv4-frag-random-evicted"]      = {counter},
   ["memuse-ipv4-frag-reassembly-buffer"] = {counter}
}
local reassembler_config_params = {
   -- Maximum number of in-progress reassemblies.  Each one uses about
   -- 11 kB of memory.
   max_concurrent_reassemblies = { default=20000 },
   -- Maximum number of fragments to reassemble.
   max_fragments_per_reassembly = { default=40 },
}


function Reassembler:new(conf)
   local o = lib.parse(conf, reassembler_config_params)

   local max_occupy = 0.9
   local params = {
      key_type = ffi.typeof[[
         struct {
            uint8_t src_addr[4];
            uint8_t dst_addr[4];
            uint32_t fragment_id;
         } __attribute__((packed))]],
      value_type = ffi.typeof([[
         struct {
            uint16_t fragment_starts[$];
            uint16_t fragment_ends[$];
            uint16_t fragment_count;
            uint16_t final_start;
            uint16_t reassembly_base;
            uint32_t running_length; // bytes copied so far
            struct packet packet;
         } __attribute((packed))]],
         o.max_fragments_per_reassembly,
         o.max_fragments_per_reassembly),
      initial_size = math.ceil(o.max_concurrent_reassemblies / max_occupy),
      max_occupancy_rate = max_occupy,
   }
   o.ctab = ctablew.new(params)
   o.scratch_fragment_key = params.key_type()
   o.scratch_reassembly = params.value_type()
   o.next_counter_update = -1

   alarms.add_to_inventory(
      {alarm_type_id='incoming-ipv4-fragments'},
      {resource=tostring(S.getpid()), has_clear=true,
       description='Incoming IPv4 fragments over N fragments/s'})
   local incoming_fragments_alarm = alarms.declare_alarm(
      {resource=tostring(S.getpid()),alarm_type_id='incoming-ipv4-fragments'},
      {perceived_severity='warning',
       alarm_text='More than 10,000 IPv4 fragments per second'})
   o.incoming_ipv4_fragments_alarm = CounterAlarm.new(incoming_fragments_alarm,
      1, 1e4, o, "in-ipv4-frag-needs-reassembly")

   return setmetatable(o, {__index=Reassembler})
end

function Reassembler:update_counters()
   counter.set(self.shm["memuse-ipv4-frag-reassembly-buffer"],
               self.ctab:get_backing_size())
end

function Reassembler:record_eviction()
   counter.add(self.shm["drop-ipv4-frag-random-evicted"])
end

function Reassembler:reassembly_success(entry, pkt)
   self.ctab:remove_ptr(entry)
   counter.add(self.shm["in-ipv4-frag-reassembled"])
   link.transmit(self.output.output, pkt)
end

function Reassembler:reassembly_error(entry, icmp_error)
   self.ctab:remove_ptr(entry)
   counter.add(self.shm["drop-ipv4-frag-invalid-reassembly"])
   if icmp_error then -- This is an ICMP packet
      link.transmit(self.output.errors, icmp_error)
   end
end

function Reassembler:lookup_reassembly(h, pkt)
   local key = self.scratch_fragment_key
   key.src_addr, key.dst_addr = h.ipv4.src_ip, h.ipv4.dst_ip
   key.fragment_id = ntohs(h.ipv4.id)

   local entry = self.ctab:lookup_ptr(key)
   if entry then return entry end

   local reassembly = self.scratch_reassembly
   local ihl = bit.band(h.ipv4.version_and_ihl, ipv4_ihl_mask)
   local headers_len = ether_header_len + ihl * 4

   ffi.fill(reassembly, ffi.sizeof(reassembly))
   reassembly.reassembly_base = headers_len
   reassembly.running_length = headers_len
   packet.append(reassembly.packet, pkt.data, headers_len)

   local did_evict = false
   entry, did_evict = self.ctab:add(key, reassembly, false)
   if did_evict then self:record_eviction() end
   return entry
end

function Reassembler:handle_fragment(h, fragment)
   local ihl = bit.band(h.ipv4.version_and_ihl, ipv4_ihl_mask)
   local headers_len = ether_header_len + ihl * 4
   local flags_and_fragment_offset = ntohs(h.ipv4.flags_and_fragment_offset)
   local flags = bit.rshift(
      flags_and_fragment_offset, ipv4_fragment_offset_bits)
   local fragment_offset = bit.band(
      flags_and_fragment_offset, ipv4_fragment_offset_mask)
   -- Fragment offset is expressed in 8-octet units.
   local frag_start = fragment_offset * 8
   local frag_size = ntohs(h.ipv4.total_length) - ihl * 4

   local entry = self:lookup_reassembly(h, fragment)
   local reassembly = entry.value

   local fcount = reassembly.fragment_count
   if fcount + 1 > self.max_fragments_per_reassembly then
      -- Too many fragments to reassembly this packet; fail.
      return self:reassembly_error(entry)
   end
   reassembly.fragment_starts[fcount] = frag_start
   reassembly.fragment_ends[fcount] = frag_start + frag_size
   if reassembly.fragment_starts[fcount] <
      reassembly.fragment_starts[fcount - 1] then
      sort_array(reassembly.fragment_starts, fcount)
      sort_array(reassembly.fragment_ends, fcount)
   end
   reassembly.fragment_count = fcount + 1
   if bit.band(flags, ipv4_flag_more_fragments) == 0 then
      if reassembly.final_start ~= 0 then
         -- There cannot be more than one final fragment.
         return self:reassembly_error(entry)
      else
         reassembly.final_start = frag_start
      end
   end

   local skip_headers = reassembly.reassembly_base
   local dst_offset = skip_headers + frag_start
   if dst_offset + frag_size > ffi.sizeof(reassembly.packet.data) then
      -- Prevent a buffer overflow.  The relevant RFC allows hosts to
      -- silently discard reassemblies above a certain rather small
      -- size, smaller than this.
      return self:reassembly_error()
   end
   ffi.copy(reassembly.packet.data + dst_offset, fragment.data + skip_headers,
            frag_size)
   local max_data_offset = skip_headers + frag_start + frag_size
   reassembly.packet.length = math.max(reassembly.packet.length,
                                       max_data_offset)
   reassembly.running_length = reassembly.running_length + frag_size

   if reassembly.final_start == 0 then
      -- Still reassembling.
      return
   elseif reassembly.running_length ~= reassembly.packet.length then
      -- Still reassembling.
      return
   elseif not verify_valid_offsets(reassembly) then
      return self:reassembly_error(entry)
   else
      local out = packet.clone(reassembly.packet)
      local header = ffi.cast(ether_ipv4_header_ptr_t, out.data)
      header.ipv4.id, header.ipv4.flags_and_fragment_offset = 0, 0
      header.ipv4.total_length = htons(out.length - ether_header_len)
      fix_ipv4_checksum(header.ipv4)
      return self:reassembly_success(entry, out)
   end
end

function Reassembler:push ()
   local input, output = self.input.input, self.output.output

   for _ = 1, link.nreadable(input) do
      local pkt = link.receive(input)
      local h = ffi.cast(ether_ipv4_header_ptr_t, pkt.data)
      if ntohs(h.ether.type) ~= ether_type_ipv4 then
         -- Not IPv4; forward it on.  FIXME: should make a different
         -- counter here.
         counter.add(self.shm["in-ipv4-frag-reassembly-unneeded"])
         link.transmit(output, pkt)
      elseif not ipv4_packet_has_valid_length(h, pkt.length) then
         -- IPv4 packet has invalid length; drop.  FIXME: Should add a
         -- counter here.
         packet.free(pkt)
      elseif bit.band(ntohs(h.ipv4.flags_and_fragment_offset),
                      ipv4_is_fragment_mask) == 0 then
         -- Not fragmented; forward it on.
         counter.add(self.shm["in-ipv4-frag-reassembly-unneeded"])
         link.transmit(output, pkt)
      else
         -- A fragment; try to reassemble.
         counter.add(self.shm["in-ipv4-frag-needs-reassembly"])
         self:handle_fragment(h, pkt)
         packet.free(pkt)
      end
   end
end

function Reassembler:tick ()
   self.incoming_ipv4_fragments_alarm:check()

   if self.next_counter_update < engine.now() then
      -- Update counters every second, but add a bit of jitter to smooth
      -- things out.
      self:update_counters()
      self.next_counter_update = engine.now() + math.random(0.9, 1.1)
   end
end

function selftest()
   print("selftest: apps.ipv4.reassemble")

   local shm        = require("core.shm")
   local datagram   = require("lib.protocol.datagram")
   local ether      = require("lib.protocol.ethernet")
   local ipv4       = require("lib.protocol.ipv4")
   local Fragmenter = require("apps.ipv4.fragment").Fragmenter

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
      local fragment = Fragmenter:new({mtu=mtu})
      fragment.shm = shm.create_frame("apps/fragmenter", fragment.shm)
      fragment.input = { input = link.new('fragment input') }
      fragment.output = { output = link.new('fragment output') }
      link.transmit(fragment.input.input, packet.clone(pkt))
      fragment:push()
      local ret = {}
      while not link.empty(fragment.output.output) do
         table.insert(ret, link.receive(fragment.output.output))
      end
      shm.delete_frame(fragment.shm)
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
               max_concurrent_reassemblies = 100,
               max_fragments_per_reassembly = 20
            }
            reassembler.shm = shm.create_frame(
               "apps/reassembler", reassembler.shm)
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
            link.free(reassembler.input.input, 'reassembly input')
            link.free(reassembler.output.output, 'reassembly output')
            shm.delete_frame(reassembler.shm)
         end
         for _, p in ipairs(fragments) do packet.free(p) end
      end
      packet.free(pkt)
   end

   print("selftest: ok")
end
