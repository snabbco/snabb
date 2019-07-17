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

The `Fragmenter` app will fragment any IPv6 packets larger than a
configured maximum transmission unit (MTU) or the dynamically
discovered MTU on the network path (PMTU) towards a specific
destination, depending on the setting of the **pmtud** configuration
option.

If path MTU discovery (PMTUD) is disabled, the app expects to receive
packets on its `input` link and sends (possibly fragmented) packets to
its `output` link

    DIAGRAM: IPv6Fragmenter
                   +-----------+
                   |           |
    input     ---->*Fragmenter *---->   output
                   |           |
                   +-----------+

If PMTUD is enabled, the app also expects to process packets in the
reverse direction in order to be able to intercept and interpret ICMP
packets of type 2, code 0. Those packets, known as "Packet Too Big"
(PTB) messages, contain reports from nodes on the path towards a
particular destination, which indicate that a previously sent packet
could not be forwarded due to a MTU bottleneck.  The message contains
the MTU in question as well as at least the header of the original
packet that triggered the PTB message.  The `Fragmenter` app extracts
the destination address from the original packet and stores the MTU in
a per-destination cache as the PMTU for that address.

Apart from checking the integrity of the ICMP message, the app can
optionally also verify whether the message is actually intended for
consumption by this instance of the `Fragmenter` app.  For that
purpose, the app can be configured with an exhaustive list of IPv6
addresses that are designated to be local to the system.  When a PTB
message is received, it is checked whether the destination address of
the ICMP message as well as the source address of the embedded
original packet are contained in this list.  The message is discarded
if this condition is not met.  No such checking is performed if the
list is empty.

When the `Fragmenter` receives a packet on the `input` link, it first
consults the per-destination cache.  In case of a hit, the PMTU from
the cache takes precedence over the statically configured MTU.

A PMTU is removed from the cache after a configurable timeout to allow
the system to discover a larger PMTU, e.g. after a change in network
topology.

With PMTUD enabled, the app has two additional links, called `north`
and `south`


    DIAGRAM: IPv6Fragmenter_PMTUD
                   +-----------+
                   |           |
    input     ---->*Fragmenter *---->   output
    north     <----*           *<----   south
                   |           |
                   +-----------+

All packets received on the `south` link which are not ICMP packets of
type 2, code 0 are passed on unmodified on the `north` link.

### Configuration

The `Fragmenter` app accepts a table as its configuration argument. The
following keys are defined:

— Key **mtu**

*Required*.  The maximum transmission unit, in bytes, not including the
Ethernet header.

— Key **pmtud**

*Optional*.  If set to `true`, dynamic path MTU discovery (PMTUD) is
enabled.  The default is `false`.

— Key **pmtu_timeout**

*Optional*.  The amount of time in seconds after which a PMTU is
 removed from the cache.  The default is 600.  This key is ignored
 unless **pmtud** is `true`.

— Key **pmtu_local_addresses**

*Optional*. A table of IPv6 addresses in human readable representation
for which the app will accept PTB messages.  The default is an empty
table, which disables the check for local addresses.

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
