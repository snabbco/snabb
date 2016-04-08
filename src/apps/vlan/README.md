# VLAN

There are three VLAN related apps, Tagger, Untagger and VlanMux. Tagger and
Untagger are simple apps that add or remove a tag whereas VlanMux can mux and
demux packets to different interfaces based on tag.

## Tagger

Tagger adds a VLAN tag, with the configured value, to packets received on the
input interface and sends them to the output interface.

### Configuration

-  Key **tag**

*Required*. VLAN tag to add or remove from the packet


## Untagger

Untagger checks packets received on the input interface for a VLAN tag, removes
it if it matches with the configured VLAN tag and sends them to the output
interface. Packets with other VLAN tags than the configured tag will be dropped.

### Configuration

-  Key **tag**

*Required*. VLAN tag to add or remove from the packet


## VlanMux

Despite the name, VlanMux can act both as a multiplexer, i.e. receive packes
from multiple different inputs, add a VLAN tag and send them out onto one, as
well as receiving packets from a "trunk" interface and demultiplex it over many
interfaces based on the VLAN tag of the received packet.

Packets received on the interface named "trunk" with ethertype 0x8100 are
inspected for the VLAN tag and sent out interface "vlanX" where X is the VLAN
tag parsed from the packet. If no such output interface exists the frame is
dropped. Received packets with an ethertype other than 0x8100 are sent out the
output interface "native".

Packets received on the "native" interface are sent out verbatim on the "trunk"
port.

Packets received on an interface named vlanX, where X is a VLAN tag, will have
the VLAN tag X added and then be sent out the "trunk" interface.

There is no configuration for VlanMux, simply link it to your other apps and it
will base its actions on the name of the links.
