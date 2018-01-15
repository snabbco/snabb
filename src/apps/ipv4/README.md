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
