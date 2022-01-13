-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- IPv4 fragmentation (RFC 791)

module(..., package.seeall)

local bit        = require("bit")
local ffi        = require("ffi")
local lib        = require("core.lib")
local packet     = require("core.packet")
local counter    = require("core.counter")
local link       = require("core.link")
local ipsum      = require("lib.checksum").ipsum
local alarms     = require('lib.yang.alarms')
local S          = require('syscall')

local CounterAlarm = alarms.CounterAlarm
local receive, transmit = link.receive, link.transmit
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
local ipv4_header_t = ffi.typeof [[
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
local ipv4_flag_dont_fragment = 0x2
local ipv4_ihl_bits = 4
local ipv4_ihl_mask = bit_mask(ipv4_ihl_bits)

local ether_ipv4_header_t = ffi.typeof(
   'struct { $ ether; $ ipv4; } __attribute__((packed))',
   ether_header_t, ipv4_header_t)
local ether_ipv4_header_ptr_t = ffi.typeof('$*', ether_ipv4_header_t)

local function ipv4_header_length(h)
   return bit.band(h.version_and_ihl, ipv4_ihl_mask) * 4
end

-- Precondition: packet already has IPv4 ethertype.
local function ipv4_packet_has_valid_length(h, len)
   if len < ffi.sizeof(ether_ipv4_header_t) then return false end
   if ipv4_header_length(h.ipv4) < 20 then return false end
   return ntohs(h.ipv4.total_length) <= len - ether_header_len
end

Fragmenter = {}
Fragmenter.shm = {
   ["out-ipv4-frag"]      = {counter},
   ["out-ipv4-frag-not"]  = {counter}
}
local fragmenter_config_params = {
   -- Maximum transmission unit, in bytes, not including the ethernet
   -- header.
   mtu = { mandatory=true }
}

deterministic_first_fragment_id = false
function use_deterministic_first_fragment_id()
   deterministic_first_fragment_id = 0x4242
end

function Fragmenter:new(conf)
   local o = lib.parse(conf, fragmenter_config_params)
   -- RFC 791: "Every internet module must be able to forward a datagram
   -- of 68 octets without further fragmentation.  This is because an
   -- internet header may be up to 60 octets, and the minimum fragment
   -- is 8 octets."
   assert(o.mtu >= 68)
   o.next_fragment_id = deterministic_first_fragment_id or
      math.random(0, 0xffff)

   alarms.add_to_inventory(
      {alarm_type_id='outgoing-ipv4-fragments'},
      {resource=tostring(S.getpid()), has_clear=true,
       description='Outgoing IPv4 fragments over N fragments/s'})
   local outgoing_fragments_alarm = alarms.declare_alarm(
      {resource=tostring(S.getpid()),alarm_type_id='outgoing-ipv4-fragments'},
      {perceived_severity='warning',
       alarm_text='More than 10,000 outgoing IPv4 fragments per second'})
   o.outgoing_ipv4_fragments_alarm = CounterAlarm.new(outgoing_fragments_alarm,
      1, 1e4, o, "out-ipv4-frag")

   return setmetatable(o, {__index=Fragmenter})
end

function Fragmenter:fresh_fragment_id()
   -- TODO: Consider making fragment ID not trivially predictable.
   self.next_fragment_id = bit.band(self.next_fragment_id + 1, 0xffff)
   return self.next_fragment_id
end

function Fragmenter:transmit_fragment(p)
   counter.add(self.shm["out-ipv4-frag"])
   link.transmit(self.output.output, p)
end

function Fragmenter:unfragmentable_packet(p)
   -- Unfragmentable packet that doesn't fit in the MTU; drop it.
   -- TODO: Send an error packet.
end

function Fragmenter:fragment_and_transmit(in_h, in_pkt)
   local in_flags = bit.rshift(ntohs(in_h.ipv4.flags_and_fragment_offset),
                               ipv4_fragment_offset_bits)
   if bit.band(in_flags, ipv4_flag_dont_fragment) ~= 0 then
      return self:unfragmentable_packet(in_pkt)
   end

   local mtu_with_l2 = self.mtu + ether_header_len
   local header_size = ether_header_len + ipv4_header_length(in_h.ipv4)
   local total_payload_size = in_pkt.length - header_size
   local offset, id = 0, self:fresh_fragment_id()

   while offset < total_payload_size do
      local out_pkt = packet.allocate()
      packet.append(out_pkt, in_pkt.data, header_size)
      local out_h = ffi.cast(ether_ipv4_header_ptr_t, out_pkt.data)
      local payload_size, flags = mtu_with_l2 - header_size, in_flags
      if offset + payload_size < total_payload_size then
         -- Round down payload size to nearest multiple of 8.
         payload_size = bit.band(payload_size, 0xFFF8)
         flags = bit.bor(flags, ipv4_flag_more_fragments)
      else
         payload_size = total_payload_size - offset
         flags = bit.band(flags, bit.bnot(ipv4_flag_more_fragments))
      end
      packet.append(out_pkt, in_pkt.data + header_size + offset, payload_size)
      out_h.ipv4.id = htons(id)
      out_h.ipv4.total_length = htons(out_pkt.length - ether_header_len)
      out_h.ipv4.flags_and_fragment_offset = htons(
         bit.bor(offset / 8, bit.lshift(flags, ipv4_fragment_offset_bits)))
      out_h.ipv4.checksum = 0
      out_h.ipv4.checksum = htons(ipsum(out_pkt.data + ether_header_len,
                                        ipv4_header_length(out_h.ipv4), 0))
      self:transmit_fragment(out_pkt)
      offset = offset + payload_size
   end
end

function Fragmenter:push ()
   local input, output = self.input.input, self.output.output
   local max_length = self.mtu + ether_header_len

   self.outgoing_ipv4_fragments_alarm:check()

   for _ = 1, link.nreadable(input) do
      local pkt = link.receive(input)
      local h = ffi.cast(ether_ipv4_header_ptr_t, pkt.data)
      if ntohs(h.ether.type) ~= ether_type_ipv4 then
         -- Not IPv4; forward it on.  FIXME: should make a different
         -- counter here.
         counter.add(self.shm["out-ipv4-frag-not"])
         link.transmit(output, pkt)
      elseif not ipv4_packet_has_valid_length(h, pkt.length) then
         -- IPv4 packet has invalid length; drop.  FIXME: Should add a
         -- counter here.
         packet.free(pkt)
      elseif pkt.length <= max_length then
         -- No need to fragment; forward it on.
         counter.add(self.shm["out-ipv4-frag-not"])
         link.transmit(output, pkt)
      else
         -- Packet doesn't fit into MTU; need to fragment.
         self:fragment_and_transmit(h, pkt)
         packet.free(pkt)
      end
   end
end

function selftest()
   print("selftest: apps.ipv4.fragment")

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
   local function make_test_packet(payload_size, flags)
      local pkt = packet.from_pointer(lib.random_bytes(payload_size),
                                      payload_size)
      local eth_h = ether:new({ src = random_mac(), dst = random_mac(),
                                type = ethertype_ipv4 })
      local ip_h  = ipv4:new({ src = random_ipv4(), dst = random_ipv4(),
                               protocol = 0xff, ttl = 64, flags = flags })
      ip_h:total_length(ip_h:sizeof() + pkt.length)
      ip_h:checksum()

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

   -- Correct reassembly is tested in apps.ipv4.reassemble.  Here we
   -- just test that the packet chunks add up to the original size.
   for size = 0, 2000, 7 do
      local pkt = make_test_packet(size, 0)
      for mtu = 68, 2500, 3 do
         local fragments = fragment(pkt, mtu)
         local payload_size = 0
         for i, p in ipairs(fragments) do
            assert(p.length >= ether_header_len + ipv4:sizeof())
            local ipv4 = ipv4:new_from_mem(p.data + ether_header_len,
                                           p.length - ether_header_len)
            assert(p.length == ether_header_len + ipv4:total_length())
            payload_size = payload_size +
               (p.length - ipv4:sizeof() - ether_header_len)
            packet.free(p)
         end
         assert(size == payload_size)
      end
      packet.free(pkt)
   end

   -- Now check that don't-fragment packets are handled correctly.
   for size = 0, 2000, 7 do
      local pkt = make_test_packet(size, ipv4_flag_dont_fragment)
      for mtu = 68, 2500, 3 do
         local fragments = fragment(pkt, mtu)
         if #fragments == 1 then
            assert(size + ffi.sizeof(ipv4_header_t) <= mtu)
            assert(fragments[1].length == pkt.length)
            packet.free(fragments[1])
         else
            assert(#fragments == 0)
            assert(size + ffi.sizeof(ipv4_header_t) > mtu)
         end
      end
      packet.free(pkt)
   end

   shm.delete_frame(frame)
   link.free(input, 'fragment input')
   link.free(output, 'fragment output')

   print("selftest: ok")
end
