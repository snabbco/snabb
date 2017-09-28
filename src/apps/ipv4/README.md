# IPv4 Apps

## ARP (apps.ipv4.arp)

The `ARP` app implements the Address Resolution Protocol, allowing a
Snabb network function to automatically learn the next-hop MAC address
for outgoing IPv4 traffic.  The `ARP` app will also respond to
incoming address resolution requests from other hosts on the same
network.  The next-hop MAC address may also be statically configured.
Finally, the Ethernet source address for all outgoing traffic will be
set to the `self_mac` address configured on the `ARP` app.

All of this together means that using the `ARP` app in your network
function allows you to forget about link-layer concerns, for IPv4
traffic anyway.

Topologically, the `ARP` app sits between your network function and
the Ethernet interface.  Its `north` link relays traffic to and from
the network function; the `south` link talks instead to the Ethernet
interface.

    DIAGRAM: ARP
                   +-----------+
                   |           |
    north     ---->*    ARP    *<----   south
              <----*           *---->
                   |           |
                   +-----------+

### Configuration

The `ARP` app accepts a table as its configuration argument. The
following keys are defined:

— Key **self_mac**

*Optional*.  The MAC address of this network function.  If not
provided, a random MAC address will be generated.  Two random MAC
addresses have a one-in-nine-million chance of colliding.  The ARP app
will ensure that all outgoing southbound traffic will originate from
this MAC address.

— Key **self_ip**

*Required*.  The IPv4 address of this host; used to respond to
requests and when making ARP requests.

— Key **next_mac**

*Optional*.  The MAC address to which to send all network traffic.
This ARP app currently hsa the limitation that it assumes that all
traffic will go to a single MAC address.  If this address is provided
as part of the configuration, no ARP request will be made; otherwise
it will be determined from the *next_ip* via ARP.

— Key **self_ip**

*Optional*.  The IPv4 address of the next-hop host.  Required only if
 *next_mac* is not specified as part of the configuration.

— Key **shared_next_mac_key**

*Optional*.  Path to a shared memory location
(i.e. */var/run/snabb/PID/PATH*) in which to store the resolved
next_mac.  This ARP resolver might be part of a set of peer processes
sharing work via RSS.  In that case, an ARP response will probably
arrive only to one of the RSS processes, not to all of them.  If you are
using ARP behind RSS, set *shared_next_mac_key* to, for example,
`group/arp-next-mac`, to enable the different workers to communicate the
next-hop MAC address.

## Reassembler (apps.ipv4.reassemble)

The `Reassembler` app is a filter on incoming IPv4 packets that
reassembles fragments.  Note that Snabb's internal MTU is 10240 bytes;
attempts to reassemble larger packets will fail.

    DIAGRAM: IPv4Reassembler
                   +-----------+
                   |           |
    input     ---->*Reassembler*---->   output
                   |           |
                   +-----------+

The reassembler has a configurable limit for the reassembly buffer
size.  If the buffer is full and a new reassembly comes in on the
input, the reassembler app will randomly evict a pending reassembly
from its buffer before starting the new reassembly.

The reassembler app currently does not time out reassemblies that have
been around for too long.  It could be a good idea to implement
timeouts and then be able to issue "timeout exceeded" ICMP errors if
needed.

Finally, note that the reassembler app will pass through any incoming
packet that is not IPv4.

### Configuration

The `Reassembler` app accepts a table as its configuration
argument. The following keys are defined:

— Key **max_concurrent_reassemblies**

*Optional*.  The maximum number of concurrent reassemblies.  Note that
each reassembly uses about 11kB of memory.  The default is 20000.

— Key **max_fragments_per_reassembly**

*Optional*.  The maximum number of fragments per reassembly.  The
default is 40.

## Fragmenter (apps.ipv4.fragment)

The `Fragmenter` app that will fragment any IPv4 packets larger than a
configured maximum transmission unit (MTU).

    DIAGRAM: IPv4Fragmenter
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

## ICMP Echo responder (apps.ipv4.echo)

The `ICMPEcho` app responds to ICMP echo requests ("pings") to a given
set of IPv4 addresses.

Like the `ARP` app, `ICMPEcho` sits between your network function and
outside traffic.  Its `north` link relays traffic to and from the
network function; the `south` link talks to the world.

    DIAGRAM: IPv4ICMPEcho
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

*Optional*.  An IPv4 address for which to respond to pings, as a
 `uint8_t[4]`.

— Key **addresses**

*Optional*.  An array of IPv4 addresses for which to respond to pings,
as a Lua array of `uint8_t[4]` values.
