# VLAN Apps

There are three VLAN related apps, `Tagger`, `Untagger` and `VlanMux`. The
`Tagger` and `Untagger` apps add or remove a VLAN tag whereas the `VlanMux` app
can multiplex and demultiplex packets to different output ports based on tag.

## Tagger (apps.vlan.vlan)

The `Tagger` app adds a VLAN tag, with the configured value, to packets
received on its `input` port and transmits them on its `output` port.

### Configuration

—  Key **tag**

*Required*. VLAN tag to add or remove from the packet.


## Untagger (apps.vlan.vlan)

The `Untagger` app checks packets received on its `input` port for a VLAN tag,
removes it if it matches with the configured VLAN tag and transmits them on its
`output` port. Packets with other VLAN tags than the configured tag will be
dropped.

### Configuration

—  Key **tag**

*Required*. VLAN tag to add or remove from the packet.


## VlanMux (apps.vlan.vlan)

Despite the name, the `VlanMux` app can act both as a multiplexer, i.e. receive
packets from multiple different input ports, add a VLAN tag and transmit them
out onto one, as well as receiving packets from its `trunk` port and
demultiplex it over many output ports based on the VLAN tag of the received
packet.

Packets received on its `trunk` input port with Ethernet type 0x8100 are
inspected for the VLAN tag and transmitted on an output port `vlanX` where *X*
is the VLAN tag parsed from the packet. If no such output port exists the
packet is dropped. Received packets with an Ethernet type other than 0x8100 are
transmitted on its `native` output port,

Packets received on its `native` input port are transmitted verbatim on its
`trunk` output port.

Packets received on input ports named `vlanX`, where *X* is a VLAN tag, will
have the VLAN tag *X* added and then be transmitted on its `trunk` output port.

There is no configuration for the `VlanMux` app, simply connect it to your
other apps and it will base its actions on the name of the ports.
