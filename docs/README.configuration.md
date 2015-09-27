Snabb-lwaftr alpha is configured by a text file.

$ cat sample.conf
aftr_ipv4_ip = ipv4:pton("10.10.10.10"),
aftr_ipv6_ip = ipv6:pton('8:9:a:b:c:d:e:f'),
aftr_mac_b4_side = ethernet:pton("22:22:22:22:22:22"),
aftr_mac_inet_side = ethernet:pton("12:12:12:12:12:12"),
b4_mac = ethernet:pton("44:44:44:44:44:44"),
binding_table = bt.get_binding_table(),
hairpinning = true,
icmpv6_rate_limiter_n_packets=3e5,
icmpv6_rate_limiter_n_seconds=4,
inet_mac = ethernet:pton("68:68:68:68:68:68"),
ipv4_mtu = 1460,
ipv6_mtu = 1500,
policy_icmpv4_incoming = policies['ALLOW'],
policy_icmpv6_incoming = policies['ALLOW'],
policy_icmpv4_outgoing = policies['ALLOW'],
policy_icmpv6_outgoing = policies['ALLOW']

The lwaftr is associated with two physical network cards. One of these cards
faces the internet; traffic over it is IPv4. The other faces the IPv6-only
internal network, and communicates primarily with B4s.

A line-by-line explanation of the configuration file:

First, the IP and MAC addresses for both interfaces are set:
aftr_ipv4_ip = ipv4:pton("10.10.10.10"),
aftr_ipv6_ip = ipv6:pton('8:9:a:b:c:d:e:f'),
aftr_mac_b4_side = ethernet:pton("22:22:22:22:22:22"),
aftr_mac_inet_side = ethernet:pton("12:12:12:12:12:12"),

This associates 12:12:12:12:12:12 and 10.10.10.10 with the internet-facing NIC,
and 8:9:a:b:c:d:e:f and 22:22:22:22:22:22 with the NIC facing the internal network.

As this software is alpha and built on a kernel bypass basis, it does not have
support for ARP or NDP. It assumes that it will talk directly to only one host
on each side, and specifies their MAC addresses for the outgoing packets.
b4_mac = ethernet:pton("44:44:44:44:44:44"),
inet_mac = ethernet:pton("68:68:68:68:68:68"),
The alpha lwaftr can talk to any host, but assumes that the above ones are
the next hop.

binding_table = bt.get_binding_table(),
See README.bindingtable.md for binding table details.

hairpinning = true,
Configurable hairpinning is a requirement of RFC 7596; it can be true or false.

icmpv6_rate_limiter_n_packets=3e5,
icmpv6_rate_limiter_n_seconds=4,
ICMPv6 rate limiting is mandated by several RFCs. This example says that the
lwaftr can send at most 300,000 (3 * 10^5) ICMPv6 packets per 4 seconds.
Lower values are recommended for non-experimental use.

ipv4_mtu = 1460,
ipv6_mtu = 1500,
The MTU settings are used to determine whether a packet needs to be fragmented.
The current MTU handling is otherwise underdeveloped. It is not dynamically
updated on receiving ICMP packet too big messages.

policy_icmpv4_incoming = policies['ALLOW'],
policy_icmpv6_incoming = policies['ALLOW'],
policy_icmpv4_outgoing = policies['ALLOW'],
policy_icmpv6_outgoing = policies['ALLOW']
Snabb-lwaftr can be configured to ALLOW or DROP incoming and outgoing
ICMPv4 and ICMPv6 messages. If a finer granularity of control is desired,
contact the development team via github or email.
