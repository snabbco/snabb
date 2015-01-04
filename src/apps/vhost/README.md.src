# VhostUser App (apps.vhost.vhost_user)

The `VhostUser` app implements portions of the
[Virtio](http://ozlabs.org/~rusty/virtio-spec/virtio-paper.pdf) protocol
for virtual ethernet I/O interfaces. In particular, `VhostUser` supports
the virtio *vring* data structure for packet I/O in shared memory (DMA)
and the Linux *vhost* API for creating vrings attached to
[tuntap](https://www.kernel.org/doc/Documentation/networking/tuntap.txt)
devices.

With `VhostUser` SnabbSwitch can be used as a virtual ethernet interface
by *QEMU virtual machines*. When connected via a UNIX socket, packets can
be sent to the virtual machine by transmitting them on the `rx` port and
packets send by the virtual machine will arrive on the `tx` port.

    DIAGRAM: VhostUser
           +-----------+
           |           |
    rx --->* VhostUser *----> tx
           |           |
           +-----------+

## Configuration

The `VhostUser` app accepts a table as its configuration argument. The
following keys are defined:

— Key **socket_path**

*Optional*. A string denoting the path to the UNIX socket to connect
on. Unless given all incoming packets will be dropped.

— Key **is_server**

*Optional*. Listen and accept an incoming connection on *socket_path*
instead of connecting to it.
