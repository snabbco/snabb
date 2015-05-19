# Neutron API Extentions

## Zones

Snabb NFV introduces a new Neutron network type: `zone`.

Zones are like VLANs but more abstract. Whereas a `type:vlan` network
corresponds directly with a Layer-2 network segment, a `type:zone`
network can be realized in an operator-specific way. Zones thus provide a
framework for operators to connect virtual machines to networks that are
not traditionally supported by Neutron.

Zone networks are defined using the familiar Neutron API:

```
neutron net-create --provider:network_type=zone \
                   --provider:segmentation-id=<zone-number>
```

The actual implementation of Zones for a specific operator's network is
determined by an ML2 mechanism driver. Snabb NFV includes one such
driver: `piesss`.

### Zones mapped to TeraStream

Snabb NFV supports mapping zones onto Deutsche Telekom's
[TeraStream](https://ripe67.ripe.net/archives/video/3/) network.

TeraStream has these key characteristics:

* Simple unified Layer-3 (IPv6) network.
* 64 different services: infrastructure, voice, consumer internet, etc.
* Service type encoded into IPv6 address (`PIESSS` coding).
* Each server port has 64 unique IPv6 subnets (one for each service).

The main challenge for Neutron is that TeraStream uses separate IPv6
subnets for each physical port. This means that no suitable IP address
can be assigned to a Neutron port at the time it is created, which would
be the standard Neutron behavior. Instead the IP address must be assigned
after the Neutron Port is bound to a physical server port.

Snabb NFV addresses this issue and connects Neutron ports to TeraStream
as follows:

* Define one Network for each of the 64 zones.
* Define a template subnet for each network, for example `0::0/64`.
* Ports are allocated template addresses at creation time, for example
  `0::42/64`. The template address is stored in the Port `fixed_ips`
  attribute.
* Ports are assigned real addresses at portbinding time. The real address
  is determined by combining the Port's template IP address (for low
  address bits) with the appropriate subnet for the chosen physical port
  (for high address bits). The result is the real address and this is
  stored in the `zone_ip` field of the Port `vif_details` attribute.
* Ports are also mapped to specific VLAN-IDs to match their real subnets.

## Bandwidth reservation

Snabb NFV associates a bandwidth reservation (Gbps) with each Port when
it is created.

The bandwidth reservation is taken into account when choosing which
physical port of a server to use for a Neutron port. This is to ensure
that the physical network capacity is appropriately shared with the
virtual machines based on their expected bandwidth needs. (If a server
has 8 x 10Gbps physical ports then it would be unfortunate to choose the
same physical port for two Neutron Ports that each require 10Gbps of
bandwidth.)

The operator specifies a bandwidth reservation at Port creation time
using the `binding:profile` attribute. Here is an example of a 6 Gbps
reservation:

```
neutron port-create ... --binding:profile type=dict zone_gbps=6
```

(The default reservation is 1 Gbps.)

### Port selection based on bandwidth reservation

The physical port will be chosen in one of two ways, depending on whether
bandwidth is oversubscribed:

1. If one or more physical ports has enough bandwidth available to
support the new reservation without becoming oversubscribed, then the
most heavily loaded of these ports is chosen. That is, the first priority
is to fill up the ports that are already partly used.

2. If the requested bandwidth is not readily available, and the server
will be oversubscribed with the new reservation, then the least loaded
port is chosen. That is, the second priority is to share the load as
evenly as possible on servers that are oversubscribed.

## Stateless packet filtering

Snabb NFV extends Security Groups with an option to operate statelessly.

Stateless packet filtering has several advantages for NFV applications:

1. Predictable performance under diverse traffic workloads.
2. No limits to the number of TCP/UDP sessions handled by the VM.
3. No CPU or memory overhead for maintaining a connection table.

Stateless filtering can be enabled for a virtual machine port using the
`packetfilter=stateless` option:

```
neutron port-create ...
                    --binding:profile type=dict packetfilter=stateless
```

Note: When applying stateless filtering to a port that will be used to
initiate TCP connections, such as a management port, the [ephemeral port
range](http://en.wikipedia.org/wiki/Ephemeral_port) should be allowed on
ingress in order to accept return traffic.

## L2TPv3 Softwire

Snabb NFV supports L2TPv3 encapsulation for point-to-point
Ethernet-over-IPv6 tunnels. Packets transmitted by the virtual machine
will be encapsulated in L2TPv3 and packets received by the tunnel will be
decapsulated and then sent to the virtual machine.

The local L2TPv3 tunnel endpoint for the virtual machine is the IPv6
address and MAC address assigned by OpenStack (using the "zone" logic
above). The next-hop gateway address is configured as a template address
(e.g. `::1`) and then automatically moved into the same subnet as the
virtual machine. The remaining configuration options are specified
directly: the remote endpoint address, session ID, and cookie values.

Example command:

```
neutron port-create ...
                    --binding:profile type=dict \
tunnel_type=L2TPv3,\
l2tpv3_next_hop=2003:10:1,\
l2tpv3_remote_ip=2003:20::1,\
l2tpv3_session=1,\
l2tpv3_local_cookie=00000000,\
l2tpv3_remote_cookie=00000000
```
