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
local eth_proto  = require("lib.protocol.ethernet")
local ip4_proto  = require("lib.protocol.ipv4")

local constants = require("apps.lwaftr.constants")
local lwutil = require("apps.lwaftr.lwutil")

local receive, transmit = link.receive, link.transmit

local is_ipv4 = lwutil.is_ipv4
local rd16, wr16, get_ihl_from_offset = lwutil.rd16, lwutil.wr16, lwutil.get_ihl_from_offset
local band, bor = bit.band, bit.bor
local ntohs, htons = lib.ntohs, lib.htons
local ceil = math.ceil

local ehs = constants.ethernet_header_size

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
   return ntohs(h.ipv4.total_length) == len - ether_header_len
end


-- Constants to manipulate the flags next to the frag-offset field directly
-- as a 16-bit integer, without needing to shift the 3 flag bits.
local flag_dont_fragment_mask  = 0x4000
local flag_more_fragments_mask = 0x2000
local frag_offset_field_mask   = 0x1FFF

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

function Fragmenter:new(conf)
   local o = lib.parse(conf, fragmenter_config_params)
   -- RFC 791: "Every internet module must be able to forward a datagram
   -- of 68 octets without further fragmentation.  This is because an
   -- internet header may be up to 60 octets, and the minimum fragment
   -- is 8 octets."
   assert(o.mtu >= 68)
   o.next_fragment_id = math.random(0, 0xffff)
   return setmetatable(o, {__index=Fragmenter})
end

function Fragmenter:fresh_fragment_id()
   local id = self.next_fragment_id
   -- TODO: Consider making fragment ID not trivially predictable.
   self.next_fragment_id = bit.band(self.next_fragment_id + 1, 0xffff)
   return id
end

function Fragmenter:fragment_and_transmit (h, ipv4_pkt)
   local l2_mtu = self.mtu + ehs

   if bit.band(ntohs(h.ipv4.flags_and_fragment_offset),
               bit.lshift(ipv4_flag_dont_fragment,
                          ipv4_fragment_offset_bits)) ~= 0 then
      -- Unfragmentable packet that doesn't fit in the MTU; drop it.
      -- TODO: Send an error packet.
      return packet.free(ipv4_pkt)
   end

   local ver_and_ihl_offset = ehs + constants.o_ipv4_ver_and_ihl
   local total_length_offset = ehs + constants.o_ipv4_total_length
   local frag_id_offset = ehs + constants.o_ipv4_identification
   local flags_and_frag_offset_offset = ehs + constants.o_ipv4_flags
   local checksum_offset = ehs + constants.o_ipv4_checksum

   local ihl = get_ihl_from_offset(ipv4_pkt, ehs)
   local header_size = ehs + ihl
   local payload_size = ipv4_pkt.length - header_size
   -- Payload bytes per packet must be a multiple of 8
   local payload_bytes_per_packet = band(l2_mtu - header_size, 0xFFF8)
   local total_length_per_packet = payload_bytes_per_packet + ihl
   local num_packets = ceil(payload_size / payload_bytes_per_packet)

   local pkts = { ipv4_pkt }

   wr16(ipv4_pkt.data + frag_id_offset, htons(self:fresh_fragment_id()))
   wr16(ipv4_pkt.data + total_length_offset, htons(total_length_per_packet))
   wr16(ipv4_pkt.data + flags_and_frag_offset_offset, htons(flag_more_fragments_mask))
   wr16(ipv4_pkt.data + checksum_offset, 0)

   local raw_frag_offset = payload_bytes_per_packet

   for i = 2, num_packets - 1 do
      local frag_pkt = packet.allocate()
      ffi.copy(frag_pkt.data, ipv4_pkt.data, header_size)
      ffi.copy(frag_pkt.data + header_size,
               ipv4_pkt.data + header_size + raw_frag_offset,
               payload_bytes_per_packet)
      wr16(frag_pkt.data + flags_and_frag_offset_offset,
           htons(bor(flag_more_fragments_mask,
                       band(frag_offset_field_mask, raw_frag_offset / 8))))
      wr16(frag_pkt.data + checksum_offset,
           htons(ipsum(frag_pkt.data + ver_and_ihl_offset, ihl, 0)))
      frag_pkt.length = header_size + payload_bytes_per_packet
      raw_frag_offset = raw_frag_offset + payload_bytes_per_packet
      pkts[i] = frag_pkt
   end

   -- Last packet
   local last_pkt = packet.allocate()
   local last_payload_len = payload_size - raw_frag_offset
   ffi.copy(last_pkt.data, ipv4_pkt.data, header_size)
   ffi.copy(last_pkt.data + header_size,
            ipv4_pkt.data + header_size + raw_frag_offset,
            last_payload_len)
   wr16(last_pkt.data + flags_and_frag_offset_offset,
        htons(band(frag_offset_field_mask, raw_frag_offset / 8)))
   wr16(last_pkt.data + total_length_offset, htons(last_payload_len + ihl))
   wr16(last_pkt.data + checksum_offset,
        htons(ipsum(last_pkt.data + ver_and_ihl_offset, ihl, 0)))
   last_pkt.length = header_size + last_payload_len
   pkts[num_packets] = last_pkt

   -- Truncate the original packet, and update its checksum
   ipv4_pkt.length = header_size + payload_bytes_per_packet
   wr16(ipv4_pkt.data + checksum_offset,
        htons(ipsum(ipv4_pkt.data + ver_and_ihl_offset, ihl, 0)))

   for i=1,#pkts do
      counter.add(self.shm["out-ipv4-frag"])
      link.transmit(self.output.output, pkts[i])
   end
end

function Fragmenter:push ()
   local input, output = self.input.input, self.output.output
   local max_length = self.mtu + ether_header_len

   for _ = 1, link.nreadable(input) do
      local pkt = receive(input)
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
            assert(p.length >= ehs + ipv4:sizeof())
            local ipv4 = ipv4:new_from_mem(p.data + ehs,
                                           p.length - ehs)
            assert(p.length == ehs + ipv4:total_length())
            local this_payload_size = p.length - ipv4:sizeof() - ehs
            payload_size = payload_size + this_payload_size
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
