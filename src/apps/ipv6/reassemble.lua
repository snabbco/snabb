-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- IPv6 reassembly (RFC 2460 §4.5)
--
-- This reassembly implementation will abort ongoing reassemblies if
-- it sees overlapping fragments, following the recommendation of
-- RFC 5722.
--
-- Reassembly failures are currently silent.  We could implement
-- timeouts and then we could issue "timeout exceeded" ICMP errors if 60
-- seconds go by without success; we'd need to have received the first
-- fragment though.  Additionally we should emit "parameter problem"
-- code 0 ICMP errors for non-terminal fragments whose sizes aren't a
-- multiple of 8 bytes, or for reassembled packets that are too big.

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
local token_bucket = require('lib.token_bucket')
local tsc        = require('lib.tsc')
local alarms     = require('lib.yang.alarms')
local S          = require('syscall')

local CounterAlarm = alarms.CounterAlarm
local ntohs, htons = lib.ntohs, lib.htons
local ntohl = lib.ntohl

local function bit_mask(bits) return bit.lshift(1, bits) - 1 end

local ether_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint8_t  dhost[6];
   uint8_t  shost[6];
   uint16_t type;
} __attribute__((packed))
]]
local ipv6_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint32_t v_tc_fl;               // version:4, traffic class:8, flow label:20
   uint16_t payload_length;
   uint8_t  next_header;
   uint8_t  hop_limit;
   uint8_t  src_ip[16];
   uint8_t  dst_ip[16];
   uint8_t  payload[0];
} __attribute__((packed))
]]
local fragment_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint8_t next_header;
   uint8_t reserved;
   uint16_t fragment_offset_and_flags;    // fragment_offset:13, flags:3
   uint32_t id;
   uint8_t payload[0];
} __attribute__((packed))
]]
local ether_type_ipv6 = 0x86dd
-- The fragment offset is in units of 2^3=8 bytes, and it's also shifted
-- by that many bits, so we can read its value in bytes just by masking
-- off the flags bits.
local fragment_offset_mask = bit_mask(16) - bit_mask(3)
local fragment_flag_more_fragments = 0x1
-- If a packet has the "more fragments" flag set, or the fragment
-- offset is non-zero, it is a fragment.
local fragment_proto = 44

local ether_ipv6_header_t = ffi.typeof(
   'struct { $ ether; $ ipv6; uint8_t payload[0]; } __attribute__((packed))',
   ether_header_t, ipv6_header_t)
local ether_ipv6_header_len = ffi.sizeof(ether_ipv6_header_t)
local ether_ipv6_header_ptr_t = ffi.typeof('$*', ether_ipv6_header_t)

local fragment_header_len = ffi.sizeof(fragment_header_t)
local fragment_header_ptr_t = ffi.typeof('$*', fragment_header_t)

-- Precondition: packet already has IPv6 ethertype.
local function ipv6_packet_has_valid_length(h, len)
   if len < ether_ipv6_header_len then return false end
   -- The minimum Ethernet frame size is 60 bytes (without FCS).  Those
   -- frames may contain padding bytes.
   local payload_length = ntohs(h.ipv6.payload_length)
   return payload_length <= len - ether_ipv6_header_len
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
   ["in-ipv6-frag-needs-reassembly"]      = {counter},
   ["in-ipv6-frag-reassembled"]           = {counter},
   ["in-ipv6-frag-reassembly-unneeded"]   = {counter},
   ["drop-ipv6-frag-invalid-reassembly"]  = {counter},
   ["drop-ipv6-frag-random-evicted"]      = {counter},
   ["memuse-ipv6-frag-reassembly-buffer"] = {counter}
}
local reassembler_config_params = {
   -- Maximum number of in-progress reassemblies.  Each one uses about
   -- 11 kB of memory.
   max_concurrent_reassemblies = { default=20000 },
   -- Maximum number of fragments to reassemble.
   max_fragments_per_reassembly = { default=40 },
   -- Maximum number of seconds to keep a partially reassembled packet
   reassembly_timeout = { default = 60 },
}

function Reassembler:new(conf)
   local o = lib.parse(conf, reassembler_config_params)

   local max_occupy = 0.9
   local params = {
      key_type = ffi.typeof[[
         struct {
            uint8_t src_addr[16];
            uint8_t dst_addr[16];
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
            uint64_t tstamp; // creation time in TSC ticks
            struct packet *packet;
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

   local scan_time = o.reassembly_timeout / 2
   local scan_chunks = 100
   o.scan_tb = token_bucket.new({ rate = math.ceil(o.ctab.size / scan_time),
                                  burst_size = o.ctab.size / scan_chunks})
   o.tsc = tsc.new()
   o.ticks_per_timeout = o.tsc:tps() * o.reassembly_timeout
   o.scan_cursor = 0
   o.scan_tstamp = o.tsc:stamp()
   o.scan_interval = o.tsc:tps() * scan_time / scan_chunks + 0ULL

   alarms.add_to_inventory(
      {alarm_type_id='incoming-ipv6-fragments'},
      {resource=tostring(S.getpid()), has_clear=true,
       description='Incoming IPv6 fragments over N fragments/s'})
   local incoming_fragments_alarm = alarms.declare_alarm(
      {resource=tostring(S.getpid()),alarm_type_id='incoming-ipv6-fragments'},
      {perceived_severity='warning',
       alarm_text='More than 10,000 IPv6 fragments per second'})
   o.incoming_ipv6_fragments_alarm = CounterAlarm.new(incoming_fragments_alarm,
      1, 1e4, o, "in-ipv6-frag-needs-reassembly")

   return setmetatable(o, {__index=Reassembler})
end

function Reassembler:update_counters()
   counter.set(self.shm["memuse-ipv6-frag-reassembly-buffer"],
               self.ctab:get_backing_size())
end

function Reassembler:record_eviction()
   counter.add(self.shm["drop-ipv6-frag-random-evicted"])
end

function Reassembler:reassembly_success(entry)
   counter.add(self.shm["in-ipv6-frag-reassembled"])
   link.transmit(self.output.output, entry.value.packet)
   self.ctab:remove_ptr(entry)
end

function Reassembler:reassembly_error(entry, icmp_error)
   packet.free(entry.value.packet)
   self.ctab:remove_ptr(entry)
   counter.add(self.shm["drop-ipv6-frag-invalid-reassembly"])
   if icmp_error then -- This is an ICMP packet
      link.transmit(self.output.errors, icmp_error)
   end
end

local function cleanup_evicted_entry (entry)
   packet.free(entry.value.packet)
end

function Reassembler:lookup_reassembly(h, fragment)
   local fragment_id = ntohl(fragment.id)
   local key = self.scratch_fragment_key
   key.src_addr, key.dst_addr, key.fragment_id =
      h.ipv6.src_ip, h.ipv6.dst_ip, fragment_id

   local entry = self.ctab:lookup_ptr(key)
   if entry then return entry end

   local reassembly = self.scratch_reassembly
   ffi.fill(reassembly, ffi.sizeof(reassembly))
   reassembly.reassembly_base = ether_ipv6_header_len
   reassembly.running_length = ether_ipv6_header_len
   reassembly.tstamp = self.tsc:stamp()
   reassembly.packet = packet.allocate()
   packet.append(reassembly.packet, ffi.cast("uint8_t *", h),
                 ether_ipv6_header_len)

   local did_evict = false
   entry, did_evict = self.ctab:add(key, reassembly, false,
                                    cleanup_evicted_entry)
   if did_evict then self:record_eviction() end
   return entry
end

function Reassembler:handle_fragment(pkt)
   local h = ffi.cast(ether_ipv6_header_ptr_t, pkt.data)
   local fragment = ffi.cast(fragment_header_ptr_t, h.ipv6.payload)
   -- Note: keep the number of local variables to a minimum when
   -- calling lookup_reassembly to avoid "register coalescing too
   -- complex" trace aborts in ctable.
   local entry = self:lookup_reassembly(h, fragment)
   local reassembly = entry.value
   local fragment_offset_and_flags = ntohs(fragment.fragment_offset_and_flags)
   local frag_start = bit.band(fragment_offset_and_flags, fragment_offset_mask)
   local frag_size = ntohs(h.ipv6.payload_length) - fragment_header_len

   local fcount = reassembly.fragment_count
   if fcount + 1 > self.max_fragments_per_reassembly then
      -- Too many fragments to reassembly this packet; fail.
      return self:reassembly_error(entry)
   end
   reassembly.fragment_starts[fcount] = frag_start
   reassembly.fragment_ends[fcount] = frag_start + frag_size
   if (fcount > 0 and reassembly.fragment_starts[fcount] <
       reassembly.fragment_starts[fcount - 1]) then
      sort_array(reassembly.fragment_starts, fcount)
      sort_array(reassembly.fragment_ends, fcount)
   end
   reassembly.fragment_count = fcount + 1
   if bit.band(fragment_offset_and_flags, fragment_flag_more_fragments) == 0 then
      if reassembly.final_start ~= 0 then
         -- There cannot be more than one final fragment.
         return self:reassembly_error(entry)
      else
         reassembly.final_start = frag_start
      end
   elseif frag_size % 8 ~= 0 then
      -- The size of all non-terminal fragments must be a multiple of 8.
      -- Here we should send "ICMP Parameter Problem, Code 0 to the
      -- source of the fragment, pointing to the Payload Length field of
      -- the fragment packet".
      return self:reassembly_error(entry)
   end

   -- Limit the scope of max_data_offset
   do
      local max_data_offset = ether_ipv6_header_len + frag_start + frag_size
      if max_data_offset > packet.max_payload then
         -- Snabb packets have a maximum size of 10240 bytes.
         return self:reassembly_error(entry)
      end
      ffi.copy(reassembly.packet.data + reassembly.reassembly_base + frag_start,
               fragment.payload, frag_size)
      reassembly.packet.length = math.max(reassembly.packet.length,
                                          max_data_offset)
      reassembly.running_length = reassembly.running_length + frag_size
   end

   if reassembly.final_start == 0 then
      -- Still reassembling.
      return
   elseif reassembly.running_length ~= reassembly.packet.length then
      -- Still reassembling.
      return
   elseif not verify_valid_offsets(reassembly) then
      return self:reassembly_error(entry)
   else
      -- Limit the scope of header
      do
         local header = ffi.cast(ether_ipv6_header_ptr_t, reassembly.packet.data)
         header.ipv6.payload_length = htons(reassembly.packet.length - ether_ipv6_header_len)
         header.ipv6.next_header = fragment.next_header
      end
      return self:reassembly_success(entry)
   end
end

function Reassembler:expire (now)
   local cursor = self.scan_cursor
   for i = 1, self.scan_tb:take_burst() do
      local entry
      cursor, entry = self.ctab:next_entry(cursor, cursor + 1)
      if entry then
         if now - entry.value.tstamp > self.ticks_per_timeout then
            self:reassembly_error(entry)
         else
            cursor = cursor + 1
         end
      end
   end
   self.scan_cursor = cursor
   self.scan_tstamp = now
end

function Reassembler:push ()
   local input, output = self.input.input, self.output.output

   self.incoming_ipv6_fragments_alarm:check()

   do
      local now = self.tsc:stamp()
      if now - self.scan_tstamp > self.scan_interval then
         self:expire(now)
      end
   end

   for _ = 1, link.nreadable(input) do
      local pkt = link.receive(input)
      local h = ffi.cast(ether_ipv6_header_ptr_t, pkt.data)
      if ntohs(h.ether.type) ~= ether_type_ipv6 then
         -- Not IPv6; forward it on.  FIXME: should make a different
         -- counter here.
         counter.add(self.shm["in-ipv6-frag-reassembly-unneeded"])
         link.transmit(output, pkt)
      elseif not ipv6_packet_has_valid_length(h, pkt.length) then
         -- IPv6 packet has invalid length; drop.  FIXME: Should add a
         -- counter here.
         packet.free(pkt)
      elseif h.ipv6.next_header == fragment_proto then
         -- A fragment; try to reassemble.
         counter.add(self.shm["in-ipv6-frag-needs-reassembly"])
         link.transmit(input, pkt)
      else
         -- Not fragmented; forward it on.
         counter.add(self.shm["in-ipv6-frag-reassembly-unneeded"])
         link.transmit(output, pkt)
      end
   end

   for _ = 1, link.nreadable(input) do
      local pkt = link.receive(input)
      self:handle_fragment(pkt)
      packet.free(pkt)
   end

   if self.next_counter_update < engine.now() then
      -- Update counters every second, but add a bit of jitter to smooth
      -- things out.
      self:update_counters()
      self.next_counter_update = engine.now() + math.random(0.9, 1.1)
   end
end

function selftest()
   print("selftest: apps.ipv6.reassemble")

   local shm        = require("core.shm")
   local datagram   = require("lib.protocol.datagram")
   local ether      = require("lib.protocol.ethernet")
   local ipv6       = require("lib.protocol.ipv6")
   local Fragmenter = require("apps.ipv6.fragment").Fragmenter

   local ethertype_ipv6 = 0x86dd

   local function random_ipv6() return lib.random_bytes(16) end
   local function random_mac() return lib.random_bytes(6) end

   -- Returns a new packet containing an Ethernet frame with an IPv6
   -- header followed by PAYLOAD_SIZE random bytes.
   local function make_test_packet(payload_size)
      local pkt = packet.from_pointer(lib.random_bytes(payload_size),
                                      payload_size)
      local eth_h = ether:new({ src = random_mac(), dst = random_mac(),
                                type = ethertype_ipv6 })
      local ip_h  = ipv6:new({ src = random_ipv6(), dst = random_ipv6(),
                               next_header = 0xff, hop_limit = 64 })
      ip_h:payload_length(payload_size)

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
      for mtu = 1280, 2500, 113 do
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
