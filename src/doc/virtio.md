Snabb Switch supports virtio-based software ethernet I/O interfaces.

In particular: we support the virtio `vring` data structure for packet I/O in shared memory (DMA) and we support the Linux `vhost` API for creating vrings attached to [tuntap](https://www.kernel.org/doc/Documentation/networking/tuntap.txt) devices.

Sadly, we do not yet support an equivalent vhost-like interface to attach vrings to KVM virtual machines. This is something that we are actively working on with the QEMU/KVM community.

Useful background material to understand this code is:

* [QEMU internals: vhost architecture](http://blog.vmsplice.net/2011/09/qemu-internals-vhost-architecture.html) blog entry by Stefan Hajnoczi.
* [Virtio PCI Card Specification](http://ozlabs.org/~rusty/virtio-spec/virtio-0.9.5.pdf) draft by Rusty Russell.
* [virtio: Towards a De-Facto Standard For Virtual I/O Devices](http://ozlabs.org/~rusty/virtio-spec/virtio-paper.pdf) paper by Rusty Russell.

These notable virtio features that are not-yet-implemented:

* Packets spread across multiple descriptors.
* Segmentation and checksum offload via the `virtio_net_hdr` extension.
* The control virtqueue for sending commands to the device.

Foo.

    FIXME: Without this code line the next file is formatted as prose.
