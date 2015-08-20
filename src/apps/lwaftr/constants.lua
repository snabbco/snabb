module(..., package.seeall)

-- http://www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml
proto_icmp = 1
proto_tcp = 6
proto_icmpv6 = 58

-- http://www.iana.org/assignments/ieee-802-numbers/ieee-802-numbers.xhtml
ethertype_ipv4 = 0x0800
ethertype_ipv6 = 0x86DD

ethernet_header_size = 14 -- TODO: deal with 802.1Q tags?
ipv6_header_size = 40
ipv4_header_size = 20
debug = true
