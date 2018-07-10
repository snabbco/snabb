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

— Key **remote_mac**

*Optional*. MAC address of **next_hop** address as a string or in
binary representation.  If this option is present, the `nd_light` app
does not perform neighbor solicitation for the **next_hop** address
and uses **remote_mac** as the MAC address associated with
**next_hop**.

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

— Key **quiet**

*Optional*. If set to **true**, suppress log messages about ND
activity. Default is **false**.

### Special Counters

— Key **ns_checksum_errors**

Neighbor solicitation requests dropped due to invalid ICMP checksum.

— Key **ns_target_address_errors**

Neighbor solicitation requests dropped due to invalid target address.

— Key **na_duplicate_errors**

Neighbor advertisement requests dropped because next-hop is already resolved.

— Key **na_target_address_errors**

Neighbor advertisement requests dropped due to invalid target address.

— Key **nd_protocol_errors**

Neighbor discovery requests dropped due to protocol errors (invalid IPv6
hop-limit or invalid neighbor solicitation request options).


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


### Special Counters

— Key **length_errors**

Ingress packets dropped due to invalid length (packet too short).

— Key **protocol_errors**

Ingress packets dropped due to unrecognized IPv6 protocol ID.

— Key **cookie_errors**

Ingress packets dropped due to wrong cookie value.

— Key **remote_address_errors**

Ingress packets dropped due to wrong remote IPv6 endpoint address.

— Key **local_address_errors**

Ingress packets dropped due to wrong local IPv6 endpoint address.

## Fragmenter (apps.ipv6.fragment)

The `Fragmenter` app that will fragment any IPv6 packets larger than a
configured maximum transmission unit (MTU).

    DIAGRAM: IPv6Fragmenter
                   +-----------+
                   |           |
    input     ---->*Fragmenter *---->   output
                   |           |
                   +-----------+

### Configuration

The `Fragmenter` app accepts a table as its configuration argument. The
following key is defined:

— Key **mtu**

*Required*.  The maximum transmission unit, in bytes, not including the
Ethernet header.

## ICMP Echo responder (apps.ipv6.echo)

The `ICMPEcho` app responds to ICMP echo requests ("pings") to a given
set of IPv6 addresses.

Like the `ARP` app, `ICMPEcho` sits between your network function and
outside traffic.  Its `north` link relays traffic to and from the
network function; the `south` link talks to the world.

    DIAGRAM: IPv6ICMPEcho
                   +-----------+
                   |           |
    north     ---->* ICMPEcho  *<----   south
              <----*           *---->
                   |           |
                   +-----------+

### Configuration

The `ICMPEcho` app accepts a table as its configuration argument. The
following keys is defined:

— Key **address**

*Optional*.  An IPv6 address for which to respond to pings, as a
 `uint8_t[16]`.

— Key **addresses**

*Optional*.  An array of IPv6 addresses for which to respond to pings,
as a Lua array of `uint8_t[16]` values.
