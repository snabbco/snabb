# VLAN

There are two apps, Tagger and Untagger. As the name suggests one is used to
add a VLAN tag to a packet whereas the other is used to strip one.

## Tagger

Tagger adds a VLAN tag to packets received on the input interface and sends
them to the output interface.

### Configuration

-  Key **tag**

*Required*. VLAN tag to add or remove from the packet

## Untagger

Untagger remove a VLAN tag from packets received on the input interface and
sends them to the output interface.

### Configuration

-  Key **tag**

*Required*. VLAN tag to add or remove from the packet
