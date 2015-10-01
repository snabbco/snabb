# Virtualization

## Background

Currently, SnabbSwitch works on the 'host' (bare metal) and uses a driver called
**VhostUser** (See `apps/vhost/vhost_user.lua`) to bypass several things: the
typical linux bridge used in VMs, the tun/tap device, the QEMU device emulator
and the host kernel vhost-net handler. That way, the SnabbSwitch process gets
access to the very same memory pages presented to the virtio device in the VM.

However the implementation of Snabb Switch running within a VM can be still
further improved. The current approach assumes the VM would run third-party
applications that use TCP/UDP endpoints given by a stock OS, and with a
virtio-net driver that interacts with the virtio device by attaching buffers to
the virtqueues. With the VhostUser driver mentioned above just behind the
guest/host frontier, we can basically negate the virtualization overhead.

The lwAFTR application is packet-based, so there's no value in using TCP
streams provided by the Guest OS.  We can use the RawSocket to push/pull
packets directly from any existing ethernet interface, including the virtio-net
 guest driver. But this still passes through the guest kernel to queue and
prioritize the packets, and through the virtio-net driver to actually put them
in the virtqueues. At multi-million-packets-per-second, the context switching
is noticeable.

To really avoid user/kernel context switches in the guest, it is necessary to
drive the virtqueues ourselves.

## The Vguest driver

The 'vguest' driver implements a virtio-net guest driver, replacing in
userspace both virtio-net and virtio-pci. For that, it handles the emulated
PCI bus device to get hold of the virtqueues, that allow communication with
the outer world.

The design is at this point pretty much solid and unlikely to change. There is
a virtqueue object, a 'device' that initializes it and sets up the virtqueues,
and the 'app' that implements the 'push/pull' methods. See `src/apps/vguest`.

## Example of use

The development of the Vguest driver is still work in progress, but the approach
has been proved successful. The driver contains a test app that basically sends
packets from the guest to the host side. It's possible to observe packets arriving
on the host using tcpdump.

In order to run the selftest, it is necessary to prepare a Linux OS image and launch
it with QEMU:

```
#!/bin/bash
img=vma.img

sudo qemu-system-x86_64 \
     -kernel vmlinuz \
     -append "earlyprintk root=/dev/vda rw console=tty0 console=ttyS0
intel_iommu=on" \
     -m 1024 -machine type=q35,iommu=on \
     -smp 1 -cpu host --enable-kvm -serial stdio \
     -drive if=virtio,file=$img -curses \
     -netdev type=bridge,id=netuser0,br=virbr0 \
     -device virtio-net-pci,netdev=netuser0 \
     -netdev type=tap,id=netuser1 \
     -device virtio-net-pci,netdev=netuser1
```

In our case, `vma.img` contains a simple Ubuntu 14.04 system with a copy of
SnabbSwitch. The VM has two ethernet interfaces:

- **eth0** to communicate with the host system
- **eth1** to communicate with SnabbSwitch.


To run the selftest:

```
./snabb snsh -t apps.vguest.vguest_app
```

And see packets out on the host's tap1 (with tcpdump).

## Current status

It does handle guest-to-host traffic very well, but incoming traffic is still
work in progress. The default virtio device has little virtqueue rings and
a light trigger for interrupts. That doesn't play well with the QEMU-KVM, which
occasionally terminates abruptly.
