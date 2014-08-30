# Intel Ethernet Controller Apps

## `Intel10G` app: I/O with Intel 82599 Ethernet controller

![Intel10G](.images/Intel10G.png)

`Intel10G` represents one 10G Ethernet port of an Intel 82599
Ethernet controller. Packets taken from the `input` port are
transmitted onto the network. Packets received from the network are
put on the `output` port.

### Performance

`Intel10G` can transmit + receive at approximately 10 Mpps / core.

### Hardware limits

Each physical `Intel10G` port supports up to:

* 64 *pools* (virtualized `Intel10G` app instances, e.g. apps per PCI
  address)
* 127 MAC addresses (see the `macaddr` configuration option)
* 64 VLANs (see the `vlan` configuration option)
* 4 *mirror pools* (see the `mirror` configuration option)

## `LoadGen` app: Load generation by repeating transmit

![LoadGen](.images/LoadGen.png)

`LoadGen` takes up to 32K packets from the `input` port and transmits
them continuously onto the network. The packets are collected
incrementally from the `input` port, and only the first 32K packets
will be fetched.

Packets are not received from the network.

### Performance

`LoadGen` can transmit at line-rate (14 Mpps) using less than 3% CPU.

