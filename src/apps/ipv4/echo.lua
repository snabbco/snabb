-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- ICMPv4 echo request ("ping") responder (RFC 792)

module(..., package.seeall)

local bit        = require("bit")
local ffi        = require("ffi")
local lib        = require("core.lib")
local packet     = require("core.packet")
local counter    = require("core.counter")
local link       = require("core.link")
local ipsum      = require("lib.checksum").ipsum

local ntohs, htons = lib.ntohs, lib.htons
local ntohl, htonl = lib.ntohl, lib.htonl

local function bit_mask(bits) return bit.lshift(1, bits) - 1 end

local ether_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint8_t  dhost[6];
   uint8_t  shost[6];
   uint16_t type;
   uint8_t  payload[0];
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
local icmp_header_t = ffi.typeof [[
struct {
   uint8_t type;
   uint8_t code;
   int16_t checksum;
} __attribute__((packed))
]]
local ether_header_len = ffi.sizeof(ether_header_t)
local ether_type_ipv4 = 0x0800
local min_ipv4_header_len = ffi.sizeof(ipv4_header_t)
local ipv4_fragment_offset_bits = 13
local ipv4_fragment_offset_mask = bit_mask(ipv4_fragment_offset_bits)
local ipv4_ihl_bits = 4
local ipv4_ihl_mask = bit_mask(ipv4_ihl_bits)
local proto_icmp = 1
local icmp_header_len = ffi.sizeof(icmp_header_t)
local icmpv4_echo_reply = 0
local icmpv4_echo_request = 8

local ether_ipv4_header_t = ffi.typeof(
   'struct { $ ether; $ ipv4; } __attribute__((packed))',
   ether_header_t, ipv4_header_t)
local ether_ipv4_header_ptr_t = ffi.typeof('$*', ether_ipv4_header_t)
local icmp_header_ptr_t = ffi.typeof('$*', icmp_header_t)

local uint32_ptr_t = ffi.typeof('uint32_t*')
local function ipv4_as_uint32(addr)
   return ntohl(ffi.cast(uint32_ptr_t, addr)[0])
end
local function ipv4_header_length(h)
   return bit.band(h.version_and_ihl, ipv4_ihl_mask) * 4
end

ICMPEcho = {
   shm = {
      ['in-icmpv4-echo-bytes'] = {counter},
      ['in-icmpv4-echo-packets'] = {counter},
      ['out-icmpv4-echo-bytes'] = {counter},
      ['out-icmpv4-echo-packets'] = {counter},
   }
}

function ICMPEcho:new(conf)
   local addresses = {}
   if conf.address then
      addresses[ipv4_as_uint32(conf.address)] = true
   end
   if conf.addresses then
      for _, v in ipairs(conf.addresses) do
         addresses[ipv4_as_uint32(v)] = true
      end
   end
   return setmetatable({addresses = addresses}, {__index = ICMPEcho})
end

function ICMPEcho:respond_to_echo_request(pkt)
   -- Pass on packets too small to be ICMPv4.
   local min_len = ether_header_len + min_ipv4_header_len + icmp_header_len
   if pkt.length < min_len then return false end

   -- Is it ICMPv4?
   local h = ffi.cast(ether_ipv4_header_ptr_t, pkt.data)
   if ntohs(h.ether.type) ~= ether_type_ipv4 then return false end
   if h.ipv4.protocol ~= proto_icmp then return false end

   -- Find the ICMP header.  Is it an echo request?
   local ipv4_header_len = ipv4_header_length(h.ipv4)
   local min_len = min_len - min_ipv4_header_len + ipv4_header_len
   if pkt.length < min_len then return false end
   local icmp = ffi.cast(icmp_header_ptr_t, h.ether.payload + ipv4_header_len)
   if icmp.type ~= icmpv4_echo_request then return false end
   if icmp.code ~= 0 then return false end

   -- Is it sent to us?
   if not self.addresses[ipv4_as_uint32(h.ipv4.dst_ip)] then return false end

   -- OK, all good.  Let's reply.
   local out = packet.clone(pkt)
   local out_h = ffi.cast(ether_ipv4_header_ptr_t, out.data)

   -- Swap addresses.
   out_h.ether.dhost, out_h.ether.shost = h.ether.shost, h.ether.dhost
   out_h.ipv4.src_ip, out_h.ipv4.dst_ip = h.ipv4.dst_ip, h.ipv4.src_ip

   -- Clear flags
   out_h.ipv4.flags_and_fragment_offset =
      bit.band(out_h.ipv4.flags_and_fragment_offset, ipv4_fragment_offset_mask)

   -- Set TTL.
   out_h.ipv4.ttl = 64

   -- Recalculate IPv4 checksum.
   out_h.ipv4.checksum = 0
   out_h.ipv4.checksum = htons(
      ipsum(out.data + ether_header_len, ipv4_header_len, 0))

   -- Change ICMP message type.
   icmp = ffi.cast(icmp_header_ptr_t, out_h.ether.payload + ipv4_header_len)
   icmp.type = icmpv4_echo_reply

   -- Recalculate ICMP checksum.
   icmp.checksum = 0
   icmp.checksum = htons(
      ipsum(out.data + ether_header_len + ipv4_header_len,
            out.length - ether_header_len - ipv4_header_len, 0))

   -- Update counters
   counter.add(self.shm['in-icmpv4-echo-bytes'], pkt.length)
   counter.add(self.shm['in-icmpv4-echo-packets'])
   counter.add(self.shm['out-icmpv4-echo-bytes'], out.length)
   counter.add(self.shm['out-icmpv4-echo-packets'])

   link.transmit(self.output.south, out)

   return true
end

function ICMPEcho:push()
   local northbound_in, northbound_out = self.input.south, self.output.north
   for _ = 1, link.nreadable(northbound_in) do
      local pkt = link.receive(northbound_in)

      if self:respond_to_echo_request(pkt) then
         packet.free(pkt)
      else
         link.transmit(northbound_out, pkt)
      end
   end

   local southbound_in, southbound_out = self.input.north, self.output.south
   for _ = 1, link.nreadable(southbound_in) do
      link.transmit(southbound_out, link.receive(southbound_in))
   end
end
