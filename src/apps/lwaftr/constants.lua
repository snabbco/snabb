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

-- Header sizes
-- TODO: refactor these; they're not actually constant
ethernet_header_size = 14 -- TODO: deal with 802.1Q tags?
ipv6_header_size = 40
ipv6_frag_header_size = 8
ipv4_header_size = 20
