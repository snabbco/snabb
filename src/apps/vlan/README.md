# VLAN Apps

There are three VLAN related apps, `Tagger`, `Untagger` and `VlanMux`. The
`Tagger` and `Untagger` apps add or remove a VLAN tag whereas the `VlanMux` app
can multiplex and demultiplex packets to different output ports based on tag.

## Tagger (apps.vlan.vlan)

The `Tagger` app adds a VLAN tag, with the configured value and
encapsulation, to packets received on its `input` port and transmits
them on its `output` port.

### Configuration

—  Key **encapsulation**

*Optional*. The Ethertype to use as encapsulation for the
VLAN. Permitted values are the strings _"dot1q"_ and _"dot1ad"_ or a
number to select an arbitrary Ethertype.  _"dot1q"_ and _"dot1ad"_
correspond to the Ethertypes 0x8100 and 0x88a8, respectively,
according to the IEEE standards 802.1Q and 802.1ad.

If a number is given, it is truncated to 16 bits.  This feature is
intended to allow interoperation with vendors that do not use one of
the standard encapsulations (a prominent example being the value
0x9100, which can still be found in practice for double-tagging
instead of 0x88a8).

The default is _"dot1q"_.

—  Key **tag**

*Required*. VLAN tag to add or remove from the packet.  The value must
be a number in the range 1-4094 (inclusive).

## Untagger (apps.vlan.vlan)

The `Untagger` app checks packets received on its `input` port for a
VLAN tag, removes it if it matches with the configured VLAN tag and
transmits them on its `output` port. Packets with other VLAN tags than
the configured tag are dropped.

### Configuration

—  Key **encapsulation**

*Optional*. See above.

—  Key **tag**

*Required*. VLAN tag to add or remove from the packet.  The value must
be a number in the range 1-4094 (inclusive).

## VlanMux (apps.vlan.vlan)

Despite the name, the `VlanMux` app can act both as a multiplexer,
i.e. receive packets from multiple different input ports, add a VLAN
tag and transmit them out onto one, as well as receiving packets from
its `trunk` port and demultiplex it over many output ports based on
the VLAN tag of the received packet.  It supports the notion of a
"native VLAN" by mapping untagged frames on the trunk port to a
dedicated output port.

A packet received on its `trunk` input port must either be untagged or
tagged with the encapsulation as specified with the **encapsulation**
configuration option.  Otherwise, the packet is dropped.

If the Ethernet frame is tagged, the VLAN ID is extracted and the
packet is transmitted on the port named `vlan<vid>`, where `<vid>` is
the decimal representation of the VLAN ID.  If no such port exists,
the packet is dropped.

If the Ethernet frame is untagged, it is transmitted on the port named
`native` or dropped if no such port exists.

A packet received on a port named `vlan<vid>` is tagged with the VLAN
ID `<vid>` according to the configured encapsulation and transmitted
on the trunk port.

A packet received on the port named `native` is transmitted as is on
the trunk port.

### Configuration

—  Key **encapsulation**

*Optional*. See above.

