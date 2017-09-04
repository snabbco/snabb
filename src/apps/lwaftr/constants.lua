module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C

-- IPv6 next-header values
-- http://www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml
proto_icmp = 1
proto_ipv4 = 4
proto_tcp = 6
proto_udp = 17
ipv6_frag = 44
proto_icmpv6 = 58

-- Ethernet types
-- http://www.iana.org/assignments/ieee-802-numbers/ieee-802-numbers.xhtml
ethertype_ipv4 = 0x0800
ethertype_ipv6 = 0x86DD

n_ethertype_ipv4 = C.htons(0x0800)
n_ethertype_ipv6 = C.htons(0x86DD)
n_ethertype_arp = C.htons(0x0806)

-- ICMPv4 types
icmpv4_echo_reply = 0
icmpv4_dst_unreachable = 3
icmpv4_echo_request = 8
icmpv4_time_exceeded = 11

-- ICMPv4 codes
icmpv4_ttl_exceeded_in_transit = 0
icmpv4_host_unreachable = 1
icmpv4_datagram_too_big_df = 4

-- ICMPv6 types
icmpv6_dst_unreachable = 1
icmpv6_packet_too_big = 2
icmpv6_time_limit_exceeded = 3
icmpv6_parameter_problem = 4
icmpv6_echo_request = 128
icmpv6_echo_reply = 129
icmpv6_ns = 135
icmpv6_na = 136

-- ICMPv6 codes
icmpv6_code_packet_too_big = 0
icmpv6_hop_limit_exceeded = 0
icmpv6_failed_ingress_egress_policy = 5

-- Header sizes
ethernet_header_size = 14 -- TODO: deal with 802.1Q tags/other extensions?

ipv6_fixed_header_size = 40
ipv6_frag_header_size = 8
ipv6_pseudoheader_size = 40

icmp_base_size = 8 -- size excluding the IP header/playload
max_icmpv4_packet_size = 576 -- RFC 1812
max_icmpv6_packet_size = 1280

-- 802.1q
dotq_tpid = 0x8100

-- Offsets, 0-indexed
o_ethernet_dst_addr = 0
o_ethernet_src_addr = 6
o_ethernet_ethertype = 12

o_ipv4_ver_and_ihl = 0
o_ipv4_dscp_and_ecn = 1
o_ipv4_total_length = 2
o_ipv4_identification = 4
o_ipv4_flags = 6
o_ipv4_ttl = 8
o_ipv4_proto = 9
o_ipv4_checksum = 10
o_ipv4_src_addr = 12
o_ipv4_dst_addr = 16

o_ipv6_payload_len = 4
o_ipv6_next_header = 6
o_ipv6_hop_limit = 7
o_ipv6_src_addr = 8
o_ipv6_dst_addr = 24

o_ipv6_frag_offset = 2
o_ipv6_frag_id = 4

o_icmpv4_msg_type = 0
o_icmpv4_msg_code = 1
o_icmpv4_checksum = 2
o_icmpv4_echo_identifier = 4

o_icmpv6_msg_type = 0
o_icmpv6_msg_code = 1
o_icmpv6_checksum = 2

-- Config values
default_ttl = 255
min_ipv6_mtu = 1280

-- The following should actually be 2^16, but that will require support for
-- larger packets. TODO FIXME
ipv6_max_packet_size = C.PACKET_PAYLOAD_SIZE
ipv4_max_packet_size = C.PACKET_PAYLOAD_SIZE
