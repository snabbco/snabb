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
Note that:
- this does no retries on failure
- it drops all outgoing packets until a reply is received.

There is no support for router solicitations or router advertisements.

Please report any violations of RFC 4861 as a bug.
