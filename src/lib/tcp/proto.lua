-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Includes code ported from smoltcp
-- (https://github.com/m-labs/smoltcp), whose copyright is the
-- following:
---
-- Copyright (C) 2016 whitequark@whitequark.org
-- 
-- Permission to use, copy, modify, and/or distribute this software for
-- any purpose with or without fee is hereby granted.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
-- WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
-- MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
-- ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
-- WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
-- AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT
-- OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

module(...,package.seeall)

local lib = require("core.lib")
local ffi = require("ffi")
local bit = require("bit")
local ipsum = require("lib.checksum").ipsum

local ntohs, ntohl = lib.ntohs, lib.ntohl
local htons, htonl = ntohs, ntohl
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rshift = bit.lshift, bit.rshift

local function ptr_to(t) return ffi.typeof("$*", t) end

local proto_tcp = 6

------
-- Ethernet
------

local ethernet_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint8_t  dhost[6];
   uint8_t  shost[6];
   uint16_t type;
} __attribute__((packed))
]]
local ethernet_header_size = ffi.sizeof(ethernet_header_t)
local ethernet_type_ipv4 = 0x0800
local ethernet_type_ipv6 = 0x86dd
local ethernet = {}
ethernet.__index = ethernet
function ethernet:read_type() return ntohs(self.type) end
function ethernet:write_type(type) self.type = htons(type) end
function ethernet:is_ipv4() return self:read_type() == ethernet_type_ipv4 end
function ethernet:is_ipv6() return self:read_type() == ethernet_type_ipv6 end
local ethernet_header_ptr_t = ptr_to(ffi.metatype(ethernet_header_t, ethernet))

------
-- IPv4
------

local ipv4_header_t = ffi.typeof [[
/* All values in network byte order.  */
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
local ipv4_header_size = ffi.sizeof(ipv4_header_t)
local ipv4 = {}; ipv4.__index = ipv4
function ipv4:header_length()
   return band(self.version_and_ihl, 0xf) * 4
end
function ipv4:set_header_length(len)
   self.version_and_ihl = bor(lshift(4, 4), len / 4)
end
function ipv4:read_total_length() return ntohs(self.total_length) end
function ipv4:write_total_length(len) self.total_length = htons(len) end
function ipv4:read_checksum() return ntohs(self.checksum) end
function ipv4:write_checksum(checksum) self.checksum = htons(checksum) end
function ipv4:compute_and_set_checksum()
   self:write_checksum(0)
   self:write_checksum(ipsum(ffi.cast('char*', self), self:header_length(), 0))
end
function ipv4:is_tcp() return self.protocol == proto_tcp end
local ipv4_header_ptr_t = ptr_to(ffi.metatype(ipv4_header_t, ipv4))

------
-- IPv6
------

local ipv6_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint32_t v_tc_fl;               // version:4, traffic class:8, flow label:20
   uint16_t payload_length;
   uint8_t  next_header;
   uint8_t  hop_limit;
   uint8_t  src_ip[16];
   uint8_t  dst_ip[16];
} __attribute__((packed))
]]
local ipv6_header_size = ffi.sizeof(ipv6_header_t)
local ipv6 = {}; ipv6.__index = ipv6
function ipv6:read_payload_length() return ntohs(self.payload_length) end
function ipv6:write_payload_length(len) self.payload_length = htons(len) end
function ipv6:is_tcp() return self.next_header == proto_tcp end
local ipv6_header_ptr_t = ptr_to(ffi.metatype(ipv6_header_t, ipv6))

------
-- TCP
------

local tcp_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint16_t src_port;
   uint16_t dst_port;
   uint32_t seq;
   uint32_t ack;
   uint16_t data_offset_and_flags;
   uint16_t window;
   uint16_t checksum;
   uint16_t urgent;
   uint8_t options_and_payload[0];
} __attribute__((packed))
]]
local tcp_header_size = ffi.sizeof(tcp_header_t)
local ipv4_pseudo_header_t = ffi.typeof[[
struct {
   char src_ip[4];
   char dst_ip[4];
   uint16_t l4_protocol;
   uint16_t l4_length;
} __attribute__((packed))
]]
local ipv4_pseudo_header_size = ffi.sizeof(ipv4_pseudo_header_t)
local ipv6_pseudo_header_t = ffi.typeof[[
struct {
   char src_ip[16];
   char dst_ip[16];
   uint32_t l4_length;
   uint32_t l4_protocol;
} __attribute__((packed))
]]
local ipv6_pseudo_header_size = ffi.sizeof(ipv6_pseudo_header_t)

-- Delay initialization until after we can set metatypes

local tcp_data_offset_shift = 12

local flags = { FIN=0x001, SYN=0x002, RST=0x004, PSH=0x008,
                ACK=0x010, URG=0x020, ECE=0x040, CWR=0x080,
                NS =0x100 }
local flags_mask = 0x1ff

local control_flags_mask = 0xf
local controls = { INVALID=0, NONE=1, PSH=2, SYN=3, FIN=4, RST=5 }
local control_array = ffi.new('uint8_t[16]')

local function control_from_flags(flags)
   return control_array[band(flags, control_flags_mask)]
end

do
   local function add_control(control, ...)
      local flags = bor(0, ...)
      assert(flags == band(flags, control_flags_mask))
      assert(control_from_flags(flags) == controls.INVALID)
      control_array[flags] = control
   end

   add_control(controls.NONE)
   add_control(controls.PSH, flags.PSH)
   add_control(controls.SYN, flags.SYN)
   add_control(controls.SYN, flags.SYN, flags.PSH)
   add_control(controls.FIN, flags.FIN)
   add_control(controls.FIN, flags.FIN, flags.PSH)
   add_control(controls.RST, flags.RST)
   add_control(controls.RST, flags.RST, flags.PSH)
end

local options = { END=0, NOP=1, MSS=2, WS=3 }

local tcp = {}; tcp.__index = tcp

function tcp:read_src_port() return ntohs(self.src_port) end
function tcp:write_src_port(port) self.src_port = htons(port) end

function tcp:read_dst_port() return ntohs(self.dst_port) end
function tcp:write_dst_port(port) self.dst_port = htons(port) end

function tcp:read_seq() return ntohl(self.seq) end
function tcp:write_seq(seq) self.seq = htonl(seq) end

function tcp:read_ack() return ntohl(self.ack) end
function tcp:write_ack(ack) self.ack = htonl(ack) end

function tcp:read_data_offset_and_flags()
   return ntohs(self.data_offset_and_flags)
end
function tcp:write_data_offset_and_flags(data_offset_and_flags)
   self.data_offset_and_flags = htons(data_offset_and_flags)
end

function tcp:read_window() return ntohs(self.window) end
function tcp:write_window(window) self.window = htons(window) end

function tcp:read_checksum() return ntohs(self.checksum) end
function tcp:write_checksum(checksum) self.checksum = htons(checksum) end

function tcp:read_urgent() return ntohs(self.urgent) end
function tcp:write_urgent(urgent) self.urgent = htons(urgent) end

function tcp:set_options_length_and_flags(options_length, flags)
   local data_offset = tcp_header_size + options_length
   self:write_data_offset_and_flags(
      bor(lshift(data_offset/4, tcp_data_offset_shift), flags))
end

function tcp:header_length()
   return 4 * rshift(self:read_data_offset_and_flags(),
                     tcp_data_offset_shift)
end
function tcp:set_header_length(len)
   local flags = self:flags()
   self:write_data_offset_and_flags(
      bor(lshift(rshift(len, 2), tcp_data_offset_shift), flags))
end

function tcp:options_length()
   return self:header_length() - tcp_header_size
end

function tcp:payload_offset()
   return self:header_length()
end
function tcp:payload()
   return self.options_and_payload + self:options_length()
end
function tcp:payload_length(l4_length)
   return l4_length - self:payload_offset()
end

function tcp:flags()
   return band(self:read_data_offset_and_flags(), flags_mask)
end
function tcp:set_flags(flags)
   self:write_data_offset_and_flags(
      bor(self:read_data_offset_and_flags(), flags))
end
function tcp:clear_flags(flags)
   self:write_data_offset_and_flags(
      band(self:read_data_offset_and_flags(), band(bnot(flags), flags_mask)))
end

local function has_flag(flags, flag)
   return band(flags, flag) ~= 0
end
function tcp:has_flag(flag)
   return has_flag(self:flags(), flag)
end

-- Return the length of the segment, in terms of sequence space.
function tcp:segment_len(l4_length)
   local len = l4_length - self:payload_length(l4_length)
   local f = self:flags()
   if has_flag(f, flags.SYN) then len = len + 1 end
   if has_flag(f, flags.FIN) then len = len + 1 end
   return len
end

local scratch_ipv4_pseudo_header = ipv4_pseudo_header_t()
local function ipv4_tcp_pseudo_header_checksum(src_ip, dst_ip, l4_length)
   local ph = scratch_ipv4_pseudo_header
   ph.src_ip, ph.dst_ip = src_ip, dst_ip
   ph.l4_protocol = htons(proto_tcp)
   ph.l4_length = htons(l4_length)
   return ipsum(ffi.cast("uint8_t*", ph), ipv4_pseudo_header_size, 0)
end

local scratch_ipv6_pseudo_header = ipv6_pseudo_header_t()
local function ipv6_tcp_pseudo_header_checksum(src_ip, dst_ip, l4_length)
   local ph = scratch_ipv6_pseudo_header
   ph.src_ip, ph.dst_ip = src_ip, dst_ip
   ph.l4_protocol = htonl(proto_tcp)
   ph.l4_length = htonl(l4_length)
   return ipsum(ffi.cast("uint8_t*", ph), ipv6_pseudo_header_size, 0)
end

function tcp:prezeroed_checksum(l4_length, ph_csum)
   -- Return checksum of packet, assuming checksum field itself has been
   -- zeroed out.
   return ipsum(ffi.cast("uint8_t*", self), l4_length, bnot(ph_csum))
end

function tcp:compute_and_set_checksum(l4_length, ph_csum)
   self:write_checksum(0)
   self:write_checksum(self:prezeroed_checksum(l4_length, ph_csum))
end

function tcp:compute_checksum(l4_length, ph_csum)
   local csum = self:prezeroed_checksum(l4_length, ph_csum)
   -- We just did a checksum but didn't reset the checksum value in the
   -- header to 0.  Now munge the result to give the checksum that would
   -- have been, if the checksum field were zero.
   csum = band(bnot(csum), 0xffff)
   csum = csum + band(bnot(self:read_checksum()), 0xffff)
   csum = rshift(csum, 16) + band(csum, 0xffff)
   csum = csum + rshift(csum, 16)
   return band(bnot(csum), 0xffff)
end

function tcp:is_valid_checksum(l4_length, ph_csum)
   return self:compute_checksum(l4_length, ph_csum) == self:read_checksum()
end

function tcp:is_valid_checksum_ipv4(src_ip, dst_ip, l4_length)
   local ph_csum = ipv4_tcp_pseudo_header_checksum(src_ip, dst_ip, l4_length)
   return self:is_valid_checksum(l4_length, ph_csum)
end

function tcp:is_valid_checksum_ipv6(src_ip, dst_ip, l4_length)
   local ph_csum = ipv6_tcp_pseudo_header_checksum(src_ip, dst_ip, l4_length)
   return self:is_valid_checksum(l4_length, ph_csum)
end

-- When packet too short, return false
-- Otherwise return op, param, next_idx
-- Skip over NOP options
local function read_option(base, idx, len)
   if idx >= len then return false end
   local op = base[idx]
   if op == options.END then return op, nil, idx + 1 end
   if op == options.NOP then return op, nil, idx + 1 end
   local avail = len - idx
   if avail < 2 then return false end
   local param_len = base[idx + 1]
   if avail < param_len then return false end
   if param_len < 2 then return false end
   if op == options.MSS then
      if param_len ~= 4 then return false end
      local mss = ntohs(ffi.cast("uint16_t*", base + idx + 2)[0])
      return op, mss, idx + param_len
   elseif op == options.WS then
      if param_len ~= 3 then return false end
      return op, base[idx + 2], idx + param_len
   end
   -- Unknown option.  Return index into base.
   return op, idx + 2, idx + param_len
end

local function read_options(base, idx, len)
   local ret = {}
   while true do
      if idx == len then return ret end
      local op, param, next_idx = read_option(base, idx, len)
      if not op then return false end
      if op == options.END then return ret end
      if op ~= options.NOP then
         table.insert(ret, { op, param, next_idx })
      end
      idx = next_idx
   end
end

local function read_tcp_options(tcp)
   return read_options(tcp.options_and_payload, 0, tcp:options_length())
end

function tcp:control()
   return control_from_flags(self:flags())
end

function tcp:is_valid()
   return self:read_src_port() ~= 0 and
      self:read_dst_port() ~= 0 and
      self:control() ~= controls.INVALID
   -- could parse options
end

function tcp:is_valid_ipv4(src_ip, dst_ip, tcp_length)
   return self:is_valid() and
      self:is_valid_checksum_ipv4(src_ip, dst_ip, tcp_length)
end

function tcp:is_valid_ipv6(src_ip, dst_ip, tcp_length)
   return self:is_valid() and
      self:is_valid_checksum_ipv6(src_ip, dst_ip, tcp_length)
end

local tcp_header_ptr_t = ptr_to(ffi.metatype(tcp_header_t, tcp))

------
-- Getting a TCP header from a packet
------

local function as_ethernet(ptr) return ffi.cast(ethernet_header_ptr_t, ptr) end
local function as_ipv4(ptr) return ffi.cast(ipv4_header_ptr_t, ptr) end
local function as_ipv6(ptr) return ffi.cast(ipv6_header_ptr_t, ptr) end
local function as_tcp(ptr) return ffi.cast(tcp_header_ptr_t, ptr) end

function is_ipv4(p) return as_ethernet(p.data):is_ipv4() end
function is_ipv6(p) return as_ethernet(p.data):is_ipv6() end

-- Precondition: P's ethertype is IPv4
function parse_ipv4_tcp(p)
   if p.length < ethernet_header_size + ipv4_header_size then return end
   local ipv4 = as_ipv4(p.data + ethernet_header_size)
   local total_size = ipv4:read_total_length()
   local header_size = ipv4:header_length()
   if header_size < ipv4_header_size then return end
   if total_size < header_size + tcp_header_size then return end
   if p.length < ethernet_header_size + total_size then return end
   if not ipv4:is_tcp() then return end
   -- FIXME: validate IPv4 checksum
   local l4_size = total_size - header_size
   local tcp = as_tcp(p.data + ethernet_header_size + header_size)
   if not tcp:is_valid_ipv4(ipv4.src_ip, ipv4.dst_ip, l4_size) then return end

   return ipv4, tcp, tcp:payload_length(l4_size)
end

-- Precondition: P's ethertype is IPv6
function parse_ipv6_tcp(p)
   if p.length < ethernet_header_size + ipv6_header_size then return end
   local ipv6 = as_ipv6(p.data + ethernet_header_size)
   local l4_size = ipv6:read_payload_length()
   if l4_size < tcp_header_size then return end
   if p.length < ethernet_header_size + ipv6_header_size + l4_size then return end
   if not ipv6:is_tcp() then return end
   local tcp = as_tcp(p.data + ethernet_header_size + ipv6_header_size)
   if not tcp:is_valid_ipv6(ipv6.src_ip, ipv6.dst_ip, l4_size) then return end

   return ipv6, tcp, tcp:payload_length(l4_size)
end

------
-- Pushing TCP, IP, and Ethernet headers onto a packet
------

local function push_tcp_header(p, src_ip, dst_ip, compute_pseudo_header_checksum,
                               src_port, dst_port, seq, ack,
                               options_length, flags, window)
   local p = packet.shiftright(p, tcp_header_size)
   local tcp = ffi.cast(tcp_header_ptr_t, p.data)

   tcp:write_src_port(src_port); tcp:write_dst_port(dst_port)
   tcp:write_seq(seq); tcp:write_ack(ack)
   tcp:set_options_length_and_flags(options_length, flags)
   tcp:write_window(window)
   tcp.urgent = 0

   local ph_csum = compute_pseudo_header_checksum(src_ip, dst_ip, p.length)
   tcp:compute_and_set_checksum(p.length, ph_csum)

   return p
end

local function push_ipv4_header(p, src_ip, dst_ip, ttl)
   local p = packet.shiftright(p, ipv4_header_size)
   local ipv4 = ffi.cast(ipv4_header_ptr_t, p.data)

   local version = 4

   ipv4:set_header_length(ipv4_header_size)
   ipv4.dscp_and_ecn = 0
   ipv4:write_total_length(p.length)
   ipv4.id = 0
   ipv4.flags_and_fragment_offset = 0
   ipv4.ttl = ttl
   ipv4.protocol = proto_tcp
   ipv4.src_ip, ipv4.dst_ip = src_ip, dst_ip

   ipv4:compute_and_set_checksum()

   return p
end

local function push_ipv6_header(p, src_ip, dst_ip, ttl)
   local payload_length = p.length
   local p = packet.shiftright(p, ipv6_header_size)
   local ipv6 = ffi.cast(ipv6_header_ptr_t, p.data)

   ipv6.v_tc_fl = 0
   lib.bitfield(32, ipv6, 'v_tc_fl', 0, 4, 6)  -- IPv6 Version
   lib.bitfield(32, ipv6, 'v_tc_fl', 4, 8, 0)  -- Traffic class
   lib.bitfield(32, ipv6, 'v_tc_fl', 12, 20, 0) -- Flow label
   ipv6.payload_length = htons(payload_length)
   ipv6.next_header = proto_tcp
   ipv6.hop_limit = ttl
   ipv6.src_ip, ipv6.dst_ip = src_ip, dst_ip

   return p
end

-- Assume an ARP app sets L2 addresses.
local function push_ethernet_header(p, proto)
   local p = packet.shiftright(p, ethernet_header_size)
   local ether = ffi.cast(ethernet_header_ptr_t, p.data)

   ffi.fill(p.data, ethernet_header_size)
   ether.type = htons(proto)

   return p
end

function push_ethernet_ipv4_tcp_headers(p, src_ip, dst_ip, ttl,
                                        src_port, dst_port, seq, ack,
                                        options_length, flags, window)
   p = push_tcp_header(p, src_ip, dst_ip, ipv4_tcp_pseudo_header_checksum,
                       src_port, dst_port, seq, ack,
                       options_length, flags, window)
   p = push_ipv4_header(p, src_ip, dst_ip, ttl)
   return push_ethernet_header(p, ethernet_type_ipv4)
end

function push_ethernet_ipv6_tcp_headers(p, src_ip, dst_ip, ttl,
                                        src_port, dst_port, seq, ack,
                                        options_length, flags, window)
   p = push_tcp_header(p, src_ip, dst_ip, ipv6_tcp_pseudo_header_checksum,
                       src_port, dst_port, seq, ack,
                       options_length, flags, window)
   p = push_ipv6_header(p, src_ip, dst_ip, ttl)
   return push_ethernet_header(p, ethernet_type_ipv6)
end

function selftest()
   print('selftest: lib.tcp.proto')
   local packet = require('core.packet')

   local function assert_eq(a, b)
      if not lib.equal(a, b) then
         print('not equal', a, b)
         error('not equal')
      end
   end

   local p = packet.from_string(lib.hexundump([[
      52:54:00:02:02:02 52:54:00:01:01:01 08 00 45 00
      00 34 00 00 00 00 40 06 49 A9 c0 a8 14 a9 6b 15
      f0 b4 de 0b 01 bb e7 db 57 bc 91 cd 18 32 80 10
      05 9f 38 2a 00 00 01 01 08 0a 06 0c 5c bd fa 4a
      e1 65
   ]], 66))

   local ipv4, tcp, payload_length = parse_ipv4_tcp(p)

   assert_eq(tcp:read_src_port(), 56843)
   assert_eq(tcp:read_dst_port(), 443)
   assert_eq(tcp:read_seq(), 0xe7db57bc)
   assert_eq(tcp:read_ack(), 0x91cd1832)
   assert_eq(tcp:header_length(), 32);
   assert_eq(tcp:flags(), flags.ACK)
   assert_eq(tcp:has_flag(flags.ACK), true)
   assert_eq(tcp:has_flag(flags.SYN), false)
   assert_eq(tcp:read_window(), 1439)
   assert_eq(tcp:read_urgent(), 0)
   -- This particular packet has two nops followed by a timestamps
   -- option and 8 bytes of data.  We don't really support timestamps
   -- yet, so the param is a pointer into the options array with its
   -- corresponding end index.
   local tcp_option_timestamps = 8
   assert_eq(read_tcp_options(tcp), { { tcp_option_timestamps, 4, 12 } })

   local p2 = packet.from_pointer(tcp:payload(), payload_length)

   p2 = packet.prepend(p2, tcp.options_and_payload, tcp:options_length())
   p2 = push_ethernet_ipv4_tcp_headers(
      p2, ipv4.src_ip, ipv4.dst_ip, ipv4.ttl,
      tcp:read_src_port(), tcp:read_dst_port(),
      tcp:read_seq(), tcp:read_ack(),
      tcp:options_length(), flags.ACK, tcp:read_window())

   assert_eq(p.length, p2.length)
   -- Only compare L3 and onwards; p2 has empty L2 addresses.
   p = packet.shiftleft(p, ethernet_header_size)
   p2 = packet.shiftleft(p2, ethernet_header_size)
   assert(ffi.C.memcmp(p.data, p2.data, p.length) == 0)

   packet.free(p2)
   packet.free(p)

   local function validate_options(str, res)
      local bytes = lib.hexundump(str, math.floor((#str+1)/3))
      local buf = ffi.cast('uint8_t*', bytes)
      assert_eq(read_options(buf, 0, #bytes), res)
   end
   validate_options("", {})
   validate_options("00", {})
   validate_options("01", {})
   validate_options("02 04 05 dc", {{options.MSS, 1500, 4}})
   validate_options("03 03 0c", {{options.WS, 12, 3}})
   validate_options("0c 05 01 02 03", {{0x0c, 2, 5}})

   validate_options("0c", false) -- Unknown option, missing length
   validate_options("0c 05 01 02", false) -- Missing last byte of option data 
   validate_options("0c 01", false) -- Length invalid (less than 2)
   validate_options("02 02", false) -- Bad length for MSS
   validate_options("03 02", false) -- Bad length for WS

   print('selftest: ok')
end
