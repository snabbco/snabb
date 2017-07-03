# NDP support

There are conceptually two types of NDP support shipped with Snabb lwAFTR.

One listens for neighbor solicitations, and replies with neighbor advertisements.
It replies to a solicitation if and only if the target address is one of the
IPv6 addresses associated with the lwAFTR (specifically, one configured in the
binding table).
This is always on. The router flag is set in the advertisement.

The other is enabled implicitly, whenever a `next_hop6_mac` configuration
value is not detected. It sends out a neighbor solicitation request
to find out the MAC address associated with the IPv6 address specified
in the configuration as `next_hop_ipv6_addr`.

The NDP module sends periodic retries every second until the solicited IPv6
address is resolved.  While the address cannot be resolved, the lwAFTR won't
start running as the next hop is necessary to forward traffic.  However,
if after 30 seconds the next hop address could not be resolved, the lwAFTR
will give up and abort its execution, printing an error message.

Please report any violations of RFC 4861 as a bug.

# ARP support

ARP support works analogous to NDP support.

Whenever a `next_hop4_mac` configuration value is not detected, the lwAFTR
sends out an arp request to find out the MAC address associated with the
IPv4 address specified in the configuration as `next_hop_ipv4_addr`.

At this moment, the ARP module doesn't support periodic solicitation try out.
