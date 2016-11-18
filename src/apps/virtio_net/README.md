# VirtioNet App (apps.virtio_net.virtio_net)

The `VirtioNet` app implements a subset of the driver part of the
[virtio-net](http://docs.oasis-open.org/virtio/virtio/v1.0/csprd04/virtio-v1.0-csprd04.html)
specification. It can connect to a virtio-net device from within a QEMU virtual
machine. Packets can be sent out of the virtual machine by transmitting them on
the `rx` port, and packets sent to the virtual machine will arrive on the `tx`
port.

    DIAGRAM: VirtioNet
           +-----------+
           |           |
    rx --->* VirtioNet *----> tx
           |           |
           +-----------+

## Configuration

The `VirtioNet` app accepts a table as its configuration argument. The
following keys are defined:

— Key **pciaddr**

*Required*. The PCI address of the virtio-net device.

— Key **use_checksum**

*Optional*. Boolean value to enable the checksum offloading pre-calculations
applied on IPv4/IPv6 TCP and UDP packets.

