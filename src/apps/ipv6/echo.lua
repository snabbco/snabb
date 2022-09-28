-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- ICMPv6 echo request ("ping") responder (RFC 4443)

module(..., package.seeall)

local bit        = require("bit")
local ffi        = require("ffi")
local lib        = require("core.lib")
local packet     = require("core.packet")
local counter    = require("core.counter")
local link       = require("core.link")
local ipsum      = require("lib.checksum").ipsum

local ntohs, htons = lib.ntohs, lib.htons
local htonl = lib.htonl

local ether_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint8_t  dhost[6];
   uint8_t  shost[6];
   uint16_t type;
   uint8_t  payload[0];
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
local ipv6_pseudo_header_t = ffi.typeof[[
struct {
   char src_ip[16];
   char dst_ip[16];
   uint32_t payload_length;
   uint32_t next_header;
} __attribute__((packed))
]]
local icmp_header_t = ffi.typeof [[
struct {
   uint8_t type;
   uint8_t code;
   int16_t checksum;
} __attribute__((packed))
]]
local ether_type_ipv6 = 0x86dd
local proto_icmp = 58
local icmp_header_len = ffi.sizeof(icmp_header_t)
local icmpv6_echo_request = 128
local icmpv6_echo_reply = 129

local ether_ipv6_header_t = ffi.typeof(
   'struct { $ ether; $ ipv6; } __attribute__((packed))',
   ether_header_t, ipv6_header_t)
local ether_ipv6_header_len = ffi.sizeof(ether_ipv6_header_t)
local ether_ipv6_header_ptr_t = ffi.typeof('$*', ether_ipv6_header_t)
local icmp_header_ptr_t = ffi.typeof('$*', icmp_header_t)

local function ipv6_equals(a, b) return ffi.C.memcmp(a, b, 16) == 0 end

ICMPEcho = {
   shm = {
      ['in-icmpv6-echo-bytes'] = {counter},
      ['in-icmpv6-echo-packets'] = {counter},
      ['out-icmpv6-echo-bytes'] = {counter},
      ['out-icmpv6-echo-packets'] = {counter},
   }
}

function ICMPEcho:new(conf)
   local addresses = {}
   if conf.address then
      table.insert(addresses, conf.address)
   end
   if conf.addresses then
      for _, v in ipairs(conf.addresses) do table.insert(addresses, v) end
   end
   return setmetatable({addresses = addresses}, {__index = ICMPEcho})
end

function ICMPEcho:address_matches(dst)
   for _, addr in ipairs(self.addresses) do
      if ipv6_equals(dst, addr) then return true end
   end
   return false
end

function ICMPEcho:respond_to_echo_request(pkt)
   -- Pass on packets too small to be ICMPv6.
   local min_len = ether_ipv6_header_len + icmp_header_len
   if pkt.length < min_len then return false end

   -- Is it ICMPv6?
   local h = ffi.cast(ether_ipv6_header_ptr_t, pkt.data)
   if ntohs(h.ether.type) ~= ether_type_ipv6 then return false end
   if h.ipv6.next_header ~= proto_icmp then return false end

   -- Find the ICMP header.  Is it an echo request?
   local icmp = ffi.cast(icmp_header_ptr_t, h.ipv6.payload)
   if icmp.type ~= icmpv6_echo_request then return false end
   if icmp.code ~= 0 then return false end

   -- Is it sent to us?
   if not self:address_matches(h.ipv6.dst_ip) then return false end

   -- OK, all good.  Let's reply.
   local out = packet.clone(pkt)
   local out_h = ffi.cast(ether_ipv6_header_ptr_t, out.data)

   -- Swap addresses.
   out_h.ether.dhost, out_h.ether.shost = h.ether.shost, h.ether.dhost
   out_h.ipv6.src_ip, out_h.ipv6.dst_ip = h.ipv6.dst_ip, h.ipv6.src_ip

   -- Set hop limit.
   out_h.ipv6.hop_limit = 64

   -- Change ICMP message type.
   icmp = ffi.cast(icmp_header_ptr_t, out_h.ipv6.payload)
   icmp.type = icmpv6_echo_reply

   -- Recalculate ICMP checksum.
   local pseudoheader = ipv6_pseudo_header_t(
      out_h.ipv6.src_ip, out_h.ipv6.dst_ip,
      htonl(ntohs(out_h.ipv6.payload_length)),
      htonl(out_h.ipv6.next_header))
   icmp.checksum = 0
   icmp.checksum = htons(
      ipsum(out_h.ipv6.payload, out.length - ether_ipv6_header_len,
            bit.bnot(ipsum(ffi.cast('char*', pseudoheader),
                           ffi.sizeof(ipv6_pseudo_header_t),
                           0))))

   -- Update counters
   counter.add(self.shm['in-icmpv6-echo-bytes'], pkt.length)
   counter.add(self.shm['in-icmpv6-echo-packets'])
   counter.add(self.shm['out-icmpv6-echo-bytes'], out.length)
   counter.add(self.shm['out-icmpv6-echo-packets'])

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
