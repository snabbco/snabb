module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C

-- IPv6 next-header values
-- http://www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml
proto_icmp = 1
proto_ipv4 = 4
proto_tcp = 6
ipv6_frag = 44
proto_icmpv6 = 58

-- Ethernet types
-- http://www.iana.org/assignments/ieee-802-numbers/ieee-802-numbers.xhtml
ethertype_ipv4 = 0x0800
ethertype_ipv6 = 0x86DD

-- ICMPv4 types
icmpv4_echo_reply = 0
icmpv4_dst_unreachable = 3
icmpv4_echo_request = 8
icmpv4_time_exceeded = 11

-- ICMPv4 codes
icmpv4_ttl_exceeded_in_transit = 0
icmpv4_host_unreachable = 1
icmpv4_datagram_too_big_df = 4
-- icmpv4_communication_admin_prohibited = 13 -- May be received from B4s

-- ICMPv6 types
icmpv6_dst_unreachable = 1

-- ICMPv6 codes
icmpv6_failed_ingress_egress_policy = 5

-- Header sizes
-- TODO: refactor these; they're not actually constant
ethernet_header_size = 14 -- TODO: deal with 802.1Q tags/other extensions?

ipv4_header_size = 20

ipv6_fixed_header_size = 40
ipv6_frag_header_size = 8

icmp_base_size = 8 -- size excluding the IP header
icmp_orig_datagram = 8 -- as per RFC792; IP header + 8 octects original datagram
icmpv4_default_payload_size = ipv4_header_size + icmp_orig_datagram
icmpv4_total_size =  icmp_base_size + icmpv4_default_payload_size

-- Offsets, 0-indexed
ethernet_dst_addr = 0
ethernet_src_addr = 6
ethernet_ethertype = 12

ipv4_flags = 6
ipv4_checksum = 10
ipv4_src_addr = 12
ipv4_dst_addr = 16

ipv6_payload_len = 4
ipv6_next_header = 6
ipv6_src_addr = 8
ipv6_dst_addr = 24

ipv6_frag_offset = 2
ipv6_frag_id = 4

-- Config values
default_ttl = 255
min_ipv6_mtu = 1280

-- The following should actually be 2^16, but that will require support for
-- larger packets. TODO FIXME
ipv6_max_packet_size = C.PACKET_PAYLOAD_SIZE
