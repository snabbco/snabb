-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- IPv6 fragmentation (RFC 2460 §4.5 and §5)

module(..., package.seeall)

local bit        = require("bit")
local ffi        = require("ffi")
local lib        = require("core.lib")
local packet     = require("core.packet")
local counter    = require("core.counter")
local link       = require("core.link")
local alarms     = require('lib.yang.alarms')
local ctable     = require('lib.ctable')
local datagram   = require('lib.protocol.datagram')
local ethernet   = require('lib.protocol.ethernet')
local ipv6_hdr   = require('lib.protocol.ipv6')
local ptb        = require('lib.protocol.icmp.ptb')
local tsc        = require('lib.tsc')
local S          = require('syscall')

local CounterAlarm = alarms.CounterAlarm
local receive, transmit = link.receive, link.transmit
local ntohs, htons = lib.ntohs, lib.htons
local htonl = lib.htonl

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
local ether_header_len = ffi.sizeof(ether_header_t)
local ether_type_ipv6 = 0x86dd
-- The fragment offset is in units of 2^3=8 bytes, and it's also shifted
-- by that many bits, so we can read its value in bytes just by masking
-- off the flags bits.
local fragment_offset_mask = bit_mask(16) - bit_mask(3)
local fragment_flag_more_fragments = 0x1
-- If a packet has the "more fragments" flag set, or the fragment
-- offset is non-zero, it is a fragment.
local fragment_proto = 44

local ipv6_header_ptr_t = ffi.typeof('$*', ipv6_header_t)
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
   return ntohs(h.ipv6.payload_length) <= len - ether_ipv6_header_len
end

Fragmenter = {}
Fragmenter.shm = {
   ["out-ipv6-frag"]      = {counter},
   ["out-ipv6-frag-not"]  = {counter},
   ["ipv6-pmtud-ptb-received"] = {counter},
   ["ipv6-pmtud-ptb-valid"] = {counter},
   ["ipv6-pmtud-ptb-invalid-csum"] = {counter},
   ["ipv6-pmtud-ptb-invalid"] = {counter}
}
local fragmenter_config_params = {
   -- Maximum transmission unit, in bytes, not including the ethernet
   -- header.
   mtu = { mandatory=true },
   pmtud = { default=false },
   pmtu_timeout = { default = 600 },
   pmtu_local_addresses = { default = {} },
}

deterministic_first_fragment_id = false
function use_deterministic_first_fragment_id()
   deterministic_first_fragment_id = 0x42424242
end

function Fragmenter:new(conf)
   local o = lib.parse(conf, fragmenter_config_params)
   -- RFC 2460 §5.
   assert(o.mtu >= 1280)
   o.next_fragment_id = deterministic_first_fragment_id or
      math.random(0, 0xffffffff)

   if o.pmtud then
      -- Path MTU Discovery is supported by listening to ICMP
      -- Packet-Too-Big messages and recording path MTUs in a
      -- per-destination cache.  Cache entries are removed after 10
      -- minutes by default as recommended by RFC 1981 §5.3.
      local max_occupy = 0.4
      local initial_size = 128
      local params = {
         key_type = ffi.typeof("uint8_t [16]"),
         value_type = ffi.typeof[[
         struct {
            uint16_t mtu;
            uint64_t tstamp;
         } __attribute((packed))]],
         initial_size = initial_size,
         max_occupancy_rate = max_occupy,
         resize_callback = function(table, old_size)
            if old_size > 0 then
               require('jit').flush()
            end
         end,
      }
      o.dcache = ctable.new(params)
      o.scratch_dcache_value = params.value_type()
      o.tsc = tsc.new()
      o.pmtu_timeout_ticks = o.tsc:tps() * o.pmtu_timeout
      o.pmtu_timer = lib.throttle(o.pmtu_timeout/10)
      o.dgram = datagram:new()
      packet.free(o.dgram:packet())

      -- List of local addresses for which to perform PMTUD.  PTB
      -- messages not targeted at any of these addresses are ignored
      o.pmtu_local_address_table = ctable.new(
         {
            key_type = ffi.typeof("uint8_t [16]"),
            value_type = ffi.typeof("uint8_t"), -- dummy
            initial_size = #o.pmtu_local_addresses,
            max_occupancy_rate = 1,
      })
      for _, addr in ipairs(o.pmtu_local_addresses) do
         o.pmtu_local_address_table:add(ipv6_hdr:pton(addr), 0)
      end
      o.ipv6_hdr = ipv6_hdr:new({})
   end

   alarms.add_to_inventory(
      {alarm_type_id='outgoing-ipv6-fragments'},
      {resource=tostring(S.getpid()), has_clear=true,
       description='Outgoing IPv6 fragments over N fragments/s'})
   local outgoing_fragments_alarm = alarms.declare_alarm(
      {resource=tostring(S.getpid()),alarm_type_id='outgoing-ipv6-fragments'},
      {perceived_severity='warning',
       alarm_text='More than 10,000 outgoing IPv6 fragments per second'})
   o.outgoing_ipv6_fragments_alarm = CounterAlarm.new(outgoing_fragments_alarm,
      1, 1e4, o, "out-ipv6-frag")

   return setmetatable(o, {__index=Fragmenter})
end

function Fragmenter:fresh_fragment_id()
   -- TODO: Consider making fragment ID not trivially predictable.
   self.next_fragment_id = bit.band(self.next_fragment_id + 1, 0xffffffff)
   return self.next_fragment_id
end

function Fragmenter:transmit_fragment(p)
   counter.add(self.shm["out-ipv6-frag"])
   link.transmit(self.output.output, p)
end

function Fragmenter:unfragmentable_packet(p)
   -- Unfragmentable packet that doesn't fit in the MTU; drop it.
   -- TODO: Send an error packet.
end

function Fragmenter:fragment_and_transmit(in_next_header, in_pkt_box, mtu)
   local mtu_with_l2 = mtu + ether_header_len
   local total_payload_size = in_pkt_box[0].length - ether_ipv6_header_len
   local offset, id = 0, self:fresh_fragment_id()

   -- Use explicit boxing to avoid garbage when passing the header and
   -- packet pointers in case this loop gets compiled first.
   while offset < total_payload_size do
      local in_pkt = in_pkt_box[0]
      local out_pkt = packet.allocate()
      packet.append(out_pkt, ffi.cast("uint8_t *", in_pkt.data),
                    ether_ipv6_header_len)
      local out_h = ffi.cast(ether_ipv6_header_ptr_t, out_pkt.data)
      local fragment_h = ffi.cast(fragment_header_ptr_t, out_h.ipv6.payload)
      out_pkt.length = out_pkt.length + fragment_header_len
      local payload_size, flags = mtu_with_l2 - out_pkt.length, 0
      if offset + payload_size < total_payload_size then
         -- Round down payload size to nearest multiple of 8.
         payload_size = bit.band(payload_size, 0xFFF8)
         flags = bit.bor(flags, fragment_flag_more_fragments)
      else
         payload_size = total_payload_size - offset
      end
      packet.append(out_pkt, ffi.cast("uint8_t *", in_pkt.data +
                                         ether_ipv6_header_len + offset),
                    payload_size)

      out_h.ipv6.next_header = fragment_proto
      out_h.ipv6.payload_length = htons(out_pkt.length - ether_ipv6_header_len)
      fragment_h.next_header = in_next_header
      fragment_h.reserved = 0
      fragment_h.id = htonl(id)
      fragment_h.fragment_offset_and_flags = htons(bit.bor(offset, flags))

      self:transmit_fragment(out_pkt)
      offset = offset + payload_size
   end
end

function Fragmenter:process_ptb (pkt)
   local dgram = self.dgram:new(pkt, ethernet)
   dgram:parse_n(3)
   local _, ipv6, icmp = unpack(dgram:stack())
   local payload, length = dgram:payload()
   if icmp:type() ~= 2 then return false end
   local ptb = dgram:parse()
   counter.add(self.shm["ipv6-pmtud-ptb-received"])

   if (#self.pmtu_local_addresses > 0 and
       not self.pmtu_local_address_table:lookup_ptr(ipv6:dst())) then
      -- PTB not addressed to us
      return false
   end

   if icmp:checksum_check(payload, length, ipv6) then
      local mtu = ptb:mtu()
      local payload, length = dgram:payload()
      local orig_hdr = self.ipv6_hdr:new_from_mem(payload, length)
      if (length >= ipv6_hdr:sizeof() and
             (#self.pmtu_local_addresses == 0 or
              self.pmtu_local_address_table:lookup_ptr(orig_hdr:src()))) then
         counter.add(self.shm["ipv6-pmtud-ptb-valid"])
         local value = self.scratch_dcache_value
         value.mtu = mtu
         value.tstamp = self.tsc:stamp()
         self.dcache:add(orig_hdr:dst(), value, 'update_allowed')
      else
         counter.add(self.shm["ipv6-pmtud-ptb-invalid"])
      end
   else
      counter.add(self.shm["ipv6-pmtud-ptb-invalid-csum"])
   end
   return true
end

-- The destination cache is expected to be fairly small so it should
-- be ok to make a full scan.
function Fragmenter:expire_pmtu ()
   local now = self.tsc:stamp()
   local cursor = 0
   repeat
      local entry
      cursor, entry = self.dcache:next_entry(cursor, cursor + 1)
      if entry then
         if now - entry.value.tstamp > self.pmtu_timeout_ticks then
            self.dcache:remove_ptr(entry)
         else
            cursor = cursor + 1
         end
      end
   until cursor == 0
end

local pkt_box = ffi.new("struct packet *[1]")
function Fragmenter:push ()
   local input, output = self.input.input, self.output.output
   local south, north = self.input.south, self.output.north

   self.outgoing_ipv6_fragments_alarm:check()

   for _ = 1, link.nreadable(input) do
      local pkt = link.receive(input)
      local h = ffi.cast(ether_ipv6_header_ptr_t, pkt.data)
      if ntohs(h.ether.type) ~= ether_type_ipv6 then
         -- Not IPv6; forward it on.  FIXME: should make a different
         -- counter here.
         counter.add(self.shm["out-ipv6-frag-not"])
         link.transmit(output, pkt)
      elseif not ipv6_packet_has_valid_length(h, pkt.length) then
         -- IPv6 packet has invalid length; drop.  FIXME: Should add a
         -- counter here.
         packet.free(pkt)
      else
         link.transmit(input, pkt)
      end
   end

   for _ = 1, link.nreadable(input) do
      local pkt = link.receive(input)
      local mtu = self.mtu
      if self.pmtud then
         local h = ffi.cast(ether_ipv6_header_ptr_t, pkt.data)
         local entry = self.dcache:lookup_ptr(h.ipv6.dst_ip)
         if entry then
            mtu = entry.value.mtu
         end
      end
      -- FIXME: assumes that there is always room to store the MTU at
      -- the end of the payload.
      ffi.cast("uint16_t *", pkt.data + pkt.length)[0] = mtu
      if pkt.length <= mtu + ether_header_len then
         -- No need to fragment; forward it on.
         counter.add(self.shm["out-ipv6-frag-not"])
         link.transmit(output, pkt)
      else
         -- Packet doesn't fit into MTU; need to fragment.
         link.transmit(input, pkt)
      end
   end

   for _ = 1,  link.nreadable(input) do
      local pkt  = link.receive(input)
      local mtu = ffi.cast("uint16_t *", pkt.data + pkt.length)[0]
      local next_header =
         ffi.cast(ether_ipv6_header_ptr_t, pkt.data).ipv6.next_header
      pkt_box[0] = pkt
      self:fragment_and_transmit(next_header, pkt_box, mtu)
      packet.free(pkt_box[0])
   end

   if self.pmtud then
      for _ = 1, link.nreadable(south) do
         local pkt = link.receive(south)
         local h = ffi.cast(ether_ipv6_header_ptr_t, pkt.data)
         if h.ipv6.next_header == 58 then -- ICMP6
            if self:process_ptb(pkt) then
               packet.free(pkt)
            else
               -- Packet was not addressed to us
               link.transmit(north, pkt)
            end
         else
            link.transmit(north, pkt)
         end
      end

      if self.pmtu_timer() then
         self:expire_pmtu()
      end
   end
end

function selftest()
   print("selftest: apps.ipv6.fragment")

   local shm        = require("core.shm")
   local datagram   = require("lib.protocol.datagram")
   local ether      = require("lib.protocol.ethernet")
   local ipv6       = require("lib.protocol.ipv6")

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

   local frame = shm.create_frame("apps/fragmenter", Fragmenter.shm)
   local input = link.new('fragment input')
   local output = link.new('fragment output')

   local function fragment(pkt, mtu)
      local fragment = Fragmenter:new({mtu=mtu})
      fragment.shm = frame
      fragment.input, fragment.output = { input = input }, { output = output }
      link.transmit(input, packet.clone(pkt))
      fragment:push()
      local ret = {}
      while not link.empty(output) do
         table.insert(ret, link.receive(output))
      end
      return ret
   end

   -- Correct reassembly is tested in apps.ipv6.reassemble.  Here we
   -- just test that the packet chunks add up to the original size.
   for size = 0, 2000, 7 do
      local pkt = make_test_packet(size)
      for mtu = 1280, 2500, 3 do
         local fragments = fragment(pkt, mtu)
         local payload_size = 0
         for i, p in ipairs(fragments) do
            assert(p.length >= ether_ipv6_header_len)
            local h = ffi.cast(ether_ipv6_header_ptr_t, p.data)
            local header_size = ether_ipv6_header_len
            if h.ipv6.next_header == fragment_proto then
               header_size = header_size + fragment_header_len
            end
            assert(p.length >= header_size)
            payload_size = payload_size + p.length - header_size
            packet.free(p)
         end
         assert(size == payload_size)
      end
      packet.free(pkt)
   end

   shm.delete_frame(frame)
   link.free(input, 'fragment input')
   link.free(output, 'fragment output')

   -- FIXME: add test case for PMTUD
   print("selftest: ok")
end
