module(..., package.seeall)

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
ttl_exceeded_in_transit = 0
icmpv4_host_unreachable = 1
icmpv4_datagram_too_big_df = 4
icmpv4_communication_admin_prohibited = 13

-- Header sizes
-- TODO: refactor these; they're not actually constant
ethernet_header_size = 14 -- TODO: deal with 802.1Q tags/other extensions?
ipv6_header_size = 40
ipv6_frag_header_size = 8
ipv4_header_size = 20
icmpv4_base_size = 8 -- size excluding the IP header
icmp_orig_datagram = 8 -- as per RFC792; IP header + 8 octects original datagram
icmpv4_default_payload_size = ipv4_header_size + icmp_orig_datagram
icmpv4_total_size =  icmpv4_base_size + icmpv4_default_payload_size

-- Offsets, 0-indexed
ethernet_src_addr = 6
ipv4_flags = 6
ipv4_checksum = 10
ipv4_src_addr = 12
ipv4_dst_addr = 16


-- Config values
default_ttl = 255
