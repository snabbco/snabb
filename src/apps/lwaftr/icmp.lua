module(..., package.seeall)

local constants = require("apps.lwaftr.constants")
local lwheader = require("apps.lwaftr.lwheader")
local lwutil = require("apps.lwaftr.lwutil")

local checksum = require("lib.checksum")
local datagram = require("lib.protocol.datagram")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")

local bit = require("bit")
local ffi = require("ffi")
local lib = require("core.lib")

local band, bnot = bit.band, bit.bnot
local C = ffi.C
local wr16, wr32 = lwutil.wr16, lwutil.wr32
local is_ipv4, is_ipv6 = lwutil.is_ipv4, lwutil.is_ipv6
local get_ihl_from_offset = lwutil.get_ihl_from_offset
local htons, ntohs = lib.htons, lib.ntohs
local write_eth_header = lwheader.write_eth_header

local proto_icmp = constants.proto_icmp
local proto_icmpv6 = constants.proto_icmpv6
local o_ipv4_proto = constants.ethernet_header_size + constants.o_ipv4_proto
local o_ipv4_ver_and_ihl = constants.ethernet_header_size + constants.o_ipv4_ver_and_ihl
local o_icmpv4_msg_type_sans_ihl = constants.ethernet_header_size + constants.o_icmpv4_msg_type
local o_icmpv4_msg_code_sans_ihl = constants.ethernet_header_size + constants.o_icmpv4_msg_code
local o_ipv6_next_header = constants.ethernet_header_size + constants.o_ipv6_next_header
local o_icmpv6_msg_type = constants.ethernet_header_size + constants.ipv6_fixed_header_size + constants.o_icmpv6_msg_type
local o_icmpv6_msg_code = constants.ethernet_header_size + constants.ipv6_fixed_header_size + constants.o_icmpv6_msg_code
local ehs = constants.ethernet_header_size

local function calculate_payload_size(dst_pkt, initial_pkt, max_size, config)
   local original_bytes_to_skip = ehs
   if config.extra_payload_offset then
      original_bytes_to_skip = original_bytes_to_skip + config.extra_payload_offset
   end
   local payload_size = initial_pkt.length - original_bytes_to_skip
   local non_payload_bytes = dst_pkt.length + constants.icmp_base_size
   local full_pkt_size = payload_size + non_payload_bytes
   if full_pkt_size > max_size + ehs then
      full_pkt_size = max_size + ehs
      payload_size = full_pkt_size - non_payload_bytes
   end
   return payload_size, original_bytes_to_skip, non_payload_bytes
end

-- Write ICMP data to the end of a packet
-- Config must contain code and type
-- Config may contain a 'next_hop_mtu' setting.

local function write_icmp(dst_pkt, initial_pkt, max_size, base_checksum, config)
   local payload_size, original_bytes_to_skip, non_payload_bytes =
      calculate_payload_size(dst_pkt, initial_pkt, max_size, config)
   local off = dst_pkt.length
   dst_pkt.data[off] = config.type
   dst_pkt.data[off + 1] = config.code
   wr16(dst_pkt.data + off + 2, 0) -- checksum
   wr32(dst_pkt.data + off + 4, 0) -- Reserved
   if config.next_hop_mtu then
      wr16(dst_pkt.data + off + 6, htons(config.next_hop_mtu))
   end
   local dest = dst_pkt.data + non_payload_bytes
   C.memmove(dest, initial_pkt.data + original_bytes_to_skip, payload_size)

   local icmp_bytes = constants.icmp_base_size + payload_size
   local icmp_start = dst_pkt.data + dst_pkt.length
   local csum = checksum.ipsum(icmp_start, icmp_bytes, base_checksum)
   wr16(dst_pkt.data + off + 2, htons(csum))

   dst_pkt.length = dst_pkt.length + icmp_bytes
end

local function to_datagram(pkt)
   return datagram:new(pkt)
end

-- initial_pkt is the one to embed (a subset of) in the ICMP payload
function new_icmpv4_packet(from_eth, to_eth, from_ip, to_ip, initial_pkt, config)
   local new_pkt = packet.allocate()
   local dgram = to_datagram(new_pkt)
   local ipv4_header = ipv4:new({ttl = constants.default_ttl,
                                 protocol = constants.proto_icmp,
                                 src = from_ip, dst = to_ip})
   dgram:push(ipv4_header)
   new_pkt = dgram:packet()
   ipv4_header:free()
   new_pkt = packet.shiftright(new_pkt, ehs)
   write_eth_header(new_pkt.data, from_eth, to_eth, constants.n_ethertype_ipv4, config.vlan_tag)

   -- Generate RFC 1812 ICMPv4 packets, which carry as much payload as they can,
   -- rather than RFC 792 packets, which only carry the original IPv4 header + 8 octets
   write_icmp(new_pkt, initial_pkt, constants.max_icmpv4_packet_size, 0, config)

   -- Fix up the IPv4 total length and checksum
   local new_ipv4_len = new_pkt.length - ehs
   local ip_tl_p = new_pkt.data + ehs + constants.o_ipv4_total_length
   wr16(ip_tl_p, ntohs(new_ipv4_len))
   local ip_checksum_p = new_pkt.data + ehs + constants.o_ipv4_checksum
   wr16(ip_checksum_p,  0) -- zero out the checksum before recomputing
   local csum = checksum.ipsum(new_pkt.data + ehs, new_ipv4_len, 0)
   wr16(ip_checksum_p, htons(csum))

   return new_pkt
end

function is_icmpv4(pkt)
   return is_ipv4(pkt) and pkt.data[o_ipv4_proto] == proto_icmp
end

function is_icmpv4_message(pkt, msg_type, msg_code)
   if is_icmpv4(pkt) then
      local ihl = get_ihl_from_offset(pkt, o_ipv4_ver_and_ihl)
      return pkt.data[o_icmpv4_msg_type_sans_ihl + ihl] == msg_type
         and pkt.data[o_icmpv4_msg_code_sans_ihl + ihl] == msg_code
   else
      return false
   end
end

function new_icmpv6_packet(from_eth, to_eth, from_ip, to_ip, initial_pkt, config)
   local new_pkt = packet.allocate()
   local dgram = to_datagram(new_pkt)
   local ipv6_header = ipv6:new({hop_limit = constants.default_ttl,
                                 next_header = constants.proto_icmpv6,
                                 src = from_ip, dst = to_ip})
   dgram:push(ipv6_header)
   new_pkt = packet.shiftright(dgram:packet(), ehs)
   write_eth_header(new_pkt.data, from_eth, to_eth, constants.n_ethertype_ipv6)

   local max_size = constants.max_icmpv6_packet_size
   local ph_len = calculate_payload_size(new_pkt, initial_pkt, max_size, config) + constants.icmp_base_size
   local ph = ipv6_header:pseudo_header(ph_len, constants.proto_icmpv6)
   local ph_csum = checksum.ipsum(ffi.cast("uint8_t*", ph), ffi.sizeof(ph), 0)
   ph_csum = band(bnot(ph_csum), 0xffff)
   write_icmp(new_pkt, initial_pkt, max_size, ph_csum, config)

   local new_ipv6_len = new_pkt.length - (constants.ipv6_fixed_header_size + ehs)
   local ip_pl_p = new_pkt.data + ehs + constants.o_ipv6_payload_len
   wr16(ip_pl_p, ntohs(new_ipv6_len))

   ipv6_header:free()
   return new_pkt
end

function is_icmpv6(pkt)
   return is_ipv6(pkt) and pkt.data[o_ipv6_next_header] == proto_icmpv6
end


function is_icmpv6_message(pkt, msg_type, msg_code)
   return is_icmpv6(pkt) and pkt.data[o_icmpv6_msg_type] == msg_type and pkt.data[o_icmpv6_msg_code] == msg_code
end
