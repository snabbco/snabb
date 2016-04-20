# IPv6 Apps

## Nd_light (apps.ipv6.nd_light)

The `nd_light` app implements a small subset of IPv6 neighbor discovery
(RFC4861).  It has two duplex ports, `north` and `south`.  The `south`
port attaches to a network on which neighbor discovery (ND) must be
performed.  The `north` port attaches to an app that processes IPv6
packets (including full ethernet frames). Packets transmitted to the
`north` port must be wrapped in full Ethernet frames (which may be
empty).

The `nd_light` app replies to neighbor solicitations for which it is
configured as a target and performs rudimentary address resolution for
its configured *next-hop* address. If address resolution succeeds, the
Ethernet headers of packets from the `north` port will be overwritten
with headers containing the discovered destination address and the
configured source address before they are transmitted over the `south`
port. All packets from the `north` port are discarded as long as ND has
not yet succeeded. Packets received from the `south` port are transmitted
to the `north` port unaltered.

    DIAGRAM: nd_light
               +----------+
       north   |          |
          ---->* nd_light *<----
          <----*          *---->
               |          |   south
               +----------+

### Configuration

The `nd_light` app accepts a table as its configuration argument. The
following keys are defined:

— Key **local_mac**

*Required*. Local MAC address as a string or in binary representation.

— Key **local_ip**

*Required*. Local IPv6 address as a string or in binary representation.

— Key **next_hop**

*Required*. IPv6 address of *next hop* as a string or in binary
representation.

— Key **delay**

*Optional*. Neighbor solicitation retransmission delay in
milliseconds. Default is 1,000ms.

— Key **retrans**

*Optional*. Number of neighbor solicitation retransmissions. Default is
unlimited retransmissions.

## SimpleKeyedTunnel (apps.keyed_ipv6_tunnel.tunnel)

The `SimpleKeyedTunnel` app implements "a simple L2 Ethernet over IPv6
tunnel encapsulation" as described in
[Keyed IPv6 Tunnel](http://tools.ietf.org/html/draft-mkonstan-keyed-ipv6-tunnel-01).
It has two duplex ports, `encapsulated` and `decapsulated`. Packets
transmitted on the `decapsulated` input port will be encapsulated and put
on the `encapsulated` output port. Packets transmitted on the
`encapsulated` input port will be decapsulated and put on the
`decapsulated` output port.

    DIAGRAM: SimpleKeyedTunnel
                   +-------------------+
    encapsulated   |                   |
              ---->* SimpleKeyedTunnel *<----
              <----*                   *---->
                   |                   |   decapsulated
                   +-------------------+
    
    encapsulated    
              ------------\   /--------------
              <-----------|---/ /----------->
                          \-----/          decapsulated


### Configuration

The `SimpleKeyedTunnel` app accepts a table as its configuration
argument. The following keys are defined:

— Key **local_address**

*Required*. Local IPv6 address as a string.

— Key **remote_address**

*Required*. Remote IPv6 address as a string.

— Key **local_cookie**

*Required*. Local cookie, 8 bytes encoded in a hexadecimal string.

— Key **remote_cookie**

*Required*. Remote cookie, 8 bytes encoded in a hexadecimal string.

— Key **local_session**

*Optional*. Unsigned integer, 32 bit. If set, the `session_id` field of
the L2TPv3 header will be overwritten with this value.

— Key **hop_limit**

*Optional*. Unsigned integer. Sets the *hop limit*. Default is 64.

— Key **default_gateway_MAC**

*Optional*. Destination MAC as a string. Not required if overwritten by
an app such as `nd_light`.
