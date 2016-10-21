# Configuration

The lwAFTR is configured by a text file. Where applicable, default values can
be found in [the code](../../../../apps/lwaftr/conf.lua#L72).

Here's an example:

```
aftr_ipv4_ip = 10.10.10.10
aftr_ipv6_ip = 8:9:a:b:c:d:e:f
aftr_mac_b4_side = 22:22:22:22:22:22
aftr_mac_inet_side = 12:12:12:12:12:12
next_hop6_mac = 44:44:44:44:44:44
# next_hop_ipv6_addr = fd00::1
inet_mac = 52:54:00:00:00:01
# next_hop_ipv4_addr = 192.168.0.1
binding_table = path/to/binding-table.txt
hairpinning = true
icmpv6_rate_limiter_n_packets=3e5
icmpv6_rate_limiter_n_seconds=4
inet_mac = 68:68:68:68:68:68
ipv4_mtu = 1460
ipv6_mtu = 1500
max_fragments_per_reassembly_packet = 1,
max_ipv6_reassembly_packets = 10,
max_ipv4_reassembly_packets = 10,
policy_icmpv4_incoming = ALLOW
policy_icmpv6_incoming = ALLOW
policy_icmpv4_outgoing = ALLOW
policy_icmpv6_outgoing = ALLOW
v4_vlan_tag = 1234
v6_vlan_tag = 42
vlan_tagging = true
# ipv4_ingress_filter = "ip"
# ipv4_egress_filter = "ip"
# ipv6_ingress_filter = "ip6"
# ipv6_egress_filter = "ip6"
```

The lwAFTR is associated with two physical network cards. One of these cards
faces the internet; traffic over it is IPv4. The other faces the IPv6-only
internal network, and communicates primarily with B4s.

## Line-by-line explanation

### L2 and L3 addresses of the lwAFTR

First, we set the IP and MAC addresses for both interfaces:

```
aftr_ipv4_ip = 10.10.10.10
aftr_ipv6_ip = 8:9:a:b:c:d:e:f
aftr_mac_b4_side = 22:22:22:22:22:22
aftr_mac_inet_side = 12:12:12:12:12:12
```

This associates **12:12:12:12:12:12** and **10.10.10.10** with the
internet-facing NIC, and **8:9:a:b:c:d:e:f** and **22:22:22:22:22:22** with the
NIC facing the internal network.

### L2 next hops

Normally you might expect to just set a default IPv4 and IPv6 gateway
and have the lwAFTR figure out the next hop ethernet addresses on its
own.  However the lwAFTR doesn't support
[ARP](https://en.wikipedia.org/wiki/Address_Resolution_Protocol) yet.

The lwAFTR assumes that it will talk directly to only one host on each
side, and provides these configuration options to specify the L2
addresses of those hosts.

```
next_hop6_mac = 44:44:44:44:44:44
inet_mac = 68:68:68:68:68:68
```

The lwAFTR can talk to any host, but assumes that the above ones are the
next hop.

Alternatively, it is possible to use IP addresses for the next hops. The lwAFTR
will resolve the IP addresses to their correspondent MAC addresses, using
the NDP and ARP protocols.

```
next_hop_ipv6_addr = fd00::1
next_hop_ipv4_addr = 192.168.0.1
```

### The binding table

```
binding_table = path/to/binding-table.txt
```

See [README.bindingtable.md](README.bindingtable.md) for binding table
details.  Note that you can compile the binding table beforehand; again,
see [README.bindingtable.md](README.bindingtable.md).

If the path to the binding table is a relative path, it will be relative
to the location of the configuration file.  Enclose the path in single
or double quotes if the path contains spaces.

### Hairpinning

```
hairpinning = true
```

Configurable hairpinning is a requirement of [RFC
7596](https://tools.ietf.org/html/rfc7596); it can be true or false.

### Rate-limiting of ICMP error messages

```
icmpv6_rate_limiter_n_packets=3e5
icmpv6_rate_limiter_n_seconds=4
```

ICMPv6 rate limiting is mandated by several RFCs. This example says that the
lwAFTR can send at most 300,000 (3 * 10^5) ICMPv6 packets per 4 seconds.
Lower values are recommended for non-experimental use.

### MTU

```
ipv4_mtu = 1460
ipv6_mtu = 1500
```

The MTU settings are used to determine whether a packet needs to be
fragmented.  The current MTU handling is otherwise underdeveloped.  It
is not dynamically updated on receiving ICMP packet too big messages.

### Packet reassembly

```
max_fragments_per_reassembly_packet = 1,
max_ipv6_reassembly_packets = 10,
max_ipv4_reassembly_packets = 10,
```

A packet might be split into several fragments, from which it will be
reassembled. The maximum allowed number of fragments per packet can be set.
The maximum simultaneous number of packets undergoing reassembly can also be
set separately for IPv4 and IPv6.

### ICMP handling policies

```
policy_icmpv4_incoming = ALLOW
policy_icmpv6_incoming = ALLOW
policy_icmpv4_outgoing = ALLOW
policy_icmpv6_outgoing = ALLOW
```

The lwAFTR can be configured to `ALLOW` or `DROP` incoming and outgoing
ICMPv4 and ICMPv6 messages. If a finer granularity of control is
desired, contact the development team via github or email.

### VLAN tagging

```
v4_vlan_tag = 1234
v6_vlan_tag = 42
vlan_tagging = tru
```

Enable/disable 802.1Q Ethernet tagging with 'vlan_tagging'.

If it is enabled, set one tag per interface to tag outgoing packets with, and
assume that incoming packets are tagged. If it is 'false', v4_vlan_tag and
v6_vlan_tag are currently optional (and unused).

Values of `v4_vlan_tag` and `v6_vlan_tag` represent the identifier value in a
VLAN tag. It must be a value between 0 and 4095.

More sophisticated support, including for mixes of tagged/untagged packets,
will be provided upon request.

### Ingress and egress filters

```
# ipv4_ingress_filter = "ip"
# ipv4_egress_filter = "ip"
# ipv6_ingress_filter = "ip6"
# ipv6_egress_filter = "ip6"
```

In the example configuration these entries are commented out by the `#`
character.  If uncommented, the right-hand-side should be a
[pflang](https://github.com/Igalia/pflua/blob/master/doc/pflang.md)
filter.  Pflang is the language of `tcpdump`, `libpcap`, and other
tools.

If an ingress or egress filter is specified in the configuration file,
then only packets which match that filter will be allowed in or out of
the lwAFTR.  It might help to think of the filter as being "whitelists"
-- they pass only what matches and reject other things.  To make a
"blacklist" filter, use the `not` pflang operator:

```
ipv4_ingress_filter = "not ip6"
```

You might need to use parentheses so that you are applying the `not` to
the right subexpression.  Note also that if you have 802.1Q vlan tagging
enabled, the ingress and egress filters run after the tags have been
stripped.

Here is a more complicated example:

```
ipv6_egress_filter = "
  ip6 and not (
    (icmp6 and
     src net 3ffe:501:0:1001::2/128 and
     dst net 3ffe:507:0:1:200:86ff:fe05:8000/116)
    or
    (ip6 and udp and
     src net 3ffe:500::/28 and
     dst net 3ffe:0501:4819::/64 and
     src portrange 2397-2399 and
     dst port 53)
  )
"
```

As filter definitions can be a bit unmanageable as part of the
configuration, you can also load filters from a file.  To do this, start
the filter configuration like with `<` and follow it immediately with a
file name.

```
ipv4_ingress_filter = <ingress4.pf
```

As with the path to the binding table, if the path to the filter file is
a relative path, it will be relative to the location of the
configuration file.  If the path contains spaces, enclose the whole
string, including the `<` character, in single or double quotes.

Enabling ingress and egress filters currently has a performance cost.
See [README.performance.md](README.performance.md).
