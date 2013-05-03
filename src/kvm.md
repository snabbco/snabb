# [NYI] KVM guest networking support

Snabb Switch needs to provide the Ethernet connectivity for KVM
virtual machines ("guests"). This is normally done by the Linux
kernel -- we have to take it over!

The fundamental mechiansm is a "Virtio-net" shared memory DMA ring
configured using the "Vhost-net" interface. This is a pretty
straightforward interface. Snabb Switch already supports Vhost-net
as a client (talking to the Linux kernel) and what we need is to
also support Vhost-net as a server (KVM talks to us instead of
Linux).

The trouble is that Vhost-net is designed as a user-to-kernel
interface rather than a peer-to-peer interface. KVM implements its
Vhost-net client with `ioctl()` calls on the special file
`/dev/net/vhost_net`. These calls need to somehow come to Snabb
Switch instead of the Linux kernel.

The best plan of attack is an open question. Here are some options:

1. Implement Vhost-net compatible networking and reuse KVM's
   support. Perhaps use FUSE to emulate `/dev/net/tun` and
   `/dev/net/vhost_net`. Snabb Switch would provide a
   filesystem-based interface with `ioctl()`s that are compatible
   with the Linux kernel. KVM could use this filesystem with
   little or no modification. The risk is that this approach will
   be a technical dead-end e.g. FUSE will lack some necessary
   capability.

2. Implement VMware-compatible networking and reuse KVM's support.
   Here is the relevant code in KVM:
   [vmxnet3.h](https://github.com/qemu/qemu/blob/master/hw/net/vmxnet3.h)
   and
   [vmxnet3.c](https://github.com/qemu/qemu/blob/master/hw/net/vmxnet3.c).

3. Implement Xen-compatible networking and reuse KVM's support.
   Here is the relevant code in KVM: [xen_nic.c](https://github.com/qemu/qemu/blob/master/hw/net/xen_nic.c)

4. Add native Snabb Switch support to KVM. If none of the above
   are suitable, we could do this. It would be important to have it
   mainlined into the upstream version of KVM.

Random tech note: KVM guests can be started with the `-mem-path`
parameter to have them create guest machine memory as a ramdisk file.
To open and `mmap()` this file could be Snabb Switch's basic mechanism
for guest DMA.
