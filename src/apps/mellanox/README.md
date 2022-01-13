# Mellanox Connect-X app (apps.mellanox.connectx)

The `connectx.ConnectX` app provides a driver for
Mellanox Connect-X 4, 5, and 6 series network cards.

The links are named `input` and `output`.

    DIAGRAM: ConnectX
                 +-----------+
                 |           |
      input ---->* ConnectX  *----> output
                 |           |
                 +-----------+

## Configuration

— Key **pciaddress**

*Required*. The PCI address of the NIC as a string.

— Key **queues**

*Required*. Array of RX/TX queue specifications.
You need to use the `connectx.IO` app to attach for I/O on each respective queue.
A queue specification is a table with the following keys:

 * `id`—a unique queue identifier string
 * `vlan`—an optional VLAN identifier
 * `mac`—an optional MAC address as a string
   (either none or all queues must specify a MAC)

Multiple queues with matching `vlan`/`mac` identifiers will have incoming traffic
distributed between them via 3-tuple or 5-tuple RSS.
Multicast and broadcast traffic arrives on the first queue of each RSS group.

— Key **mtu**

*Optional.* MTU configured for the device. The default is 9500.

— Key **sendq_size**

— Key **recvq_size**

*Optional*. Sizes of the send and receive queues. The default is 1024.


## IO app

The `connectx.IO` app provides a driver for a single queue of a
Mellanox Connect-X network card (see *queues*).

The links are names `input` and `output`.

    DIAGRAM: connectx_IO
                 +-----------+
                 |           |
      input ---->*    IO     *----> output
                 |           |
                 +-----------+
### Configuration

— Key **pciaddress**

*Required*. The PCI address of the NIC as a string.

— Key **queue**

*Required*. The queue identifier of the respective queue.

## Supported Hardware

This driver has been confirmed to work with
Mellanox Connect-X 4, 5, and 6 series cards.

## Unsupported features

* VLAN promiscuous mode is not supported
  (i.e., queues that specify `vlan` but no `mac`)
* Local-loopback between queues is not implemented