# Virtualization

## Background

Currently, SnabbSwitch works on the 'host' (bare metal) and uses a driver called
**VhostUser** (See `apps/vhost/vhost_user.lua`) to bypass several things: the
typical linux bridge used in VMs, the tun/tap device, the QEMU device emulator
and the host kernel vhost-net handler.  That way, the SnabbSwitch process gets
access to the very same memory pages presented to the virtio device in the VM.

However the implementation of Snabb running within a VM can be still
further improved.  The current approach assumes the VM would run third-party
applications that use TCP/UDP endpoints given by a stock OS, and with a
virtio-net driver that interacts with the virtio device by attaching buffers to
the virtqueues.  With the VhostUser driver mentioned above just behind the
guest/host frontier, we can basically negate the virtualization overhead.

The lwAFTR application is packet-based, so there's no value in using TCP
streams provided by the guest OS.  We can use the RawSocket to push/pull
packets directly from any existing ethernet interface, including the virtio-net
 guest driver.  But this still passes through the guest kernel to queue and
prioritize the packets, and through the virtio-net driver to actually put them
in the virtqueues.  At multi-million-packets-per-second, the context switching
is noticeable.

To be able to obtain the maximum performance running the lwAFTR inside a VM,  it
 is necessary to run it paravirtualized using the 'vguest' driver.

The 'vguest' driver implements a virtio-net guest driver, replacing in
userspace both virtio-net and virtio-pci.  For that, it handles the emulated
PCI bus device to get hold of the virtqueues, that allow communication with
the outer world.

## How to run lwAFTR inside a VM

The script `program/lwaftr/virt/lwaftrctl` eases the process of launching a 
virtualized lwAFTR.  The script provides a series of commands and actions to start
and stop a VM and the lwAFTR inside of it from a host.

## Settings

In order to run successfully, the `lwaftrctl` script needs a configuration with all
its parameters.  Use `program/lwaftr/virt/conf/lwaftrctl1.conf` as a reference 
for such configuration file.

## Steps

### Start SnabbNFV

The snabbnfv command will take two NICs and make them available to QEMU.  Basically,
the snabbnfv command makes the NIC to be handle with the Vhost-User driver.  Each
NIC will be a handled by a single core.

```
$ ./lwaftrctl snabbnfv start

Start snabbnfv (screen: 'snabbnfv-1') at core 1 (pci: 0000:02:00.0; conf: 
  /.../src/program/lwaftr/virt/ports/lwaftr1/a.cfg}; socket: /tmp/vh1a.sock)
Start snabbnfv (screen: 'snabbnfv-2') at core 2 (pci: 0000:02:00.1; conf: 
  /.../src/program/lwaftr/virt/ports/lwaftr1/b.cfg}; socket: /tmp/vh1b.sock)
```

A SnabbNFV process needs three parameters: config file, PCI and socket file.
  These parameters are taken from the `lwaftrctl.conf` file.  See SnabbNFV 
documentation for more information about these parameters.

The SnabbNFV processes are running each of them in a _screen_.  The _screens_ 
as:

```
$ screen -ls
There are screens on:
    14888.snabbnfv-1    (Detached)
    14891.snabbnfv-2    (Detached)
2 Sockets in /tmp/uscreens/S-dpino.
```

It is possible to connect to _screen_ running:

```
$ screen -r 14888.snabbnfv-1
load: time: 1.00s  fps: 0         fpGbps: 0.000 fpb: 0   bpp: -    sleep: 100 us
load: time: 1.00s  fps: 0         fpGbps: 0.000 fpb: 0   bpp: -    sleep: 100 us
load: time: 1.00s  fps: 0         fpGbps: 0.000 fpb: 0   bpp: -    sleep: 100 us
```

Press Ctrl-A + Ctrl-D to deattach from the current screen.

### Start VM

Once SnabbNFV is running it will possible to launch the VM with QEMU.

```
$ ./lwaftrctl vm start
Starting QEMU. Please wait...
QEMU waiting for connection on: disconnected:unix:/tmp/vh1a.sock,server
QEMU waiting for connection on: disconnected:unix:/tmp/vh1b.sock,server
qemu-system-x86_64: -netdev type=vhost-user,id=net0,chardev=char1: chardev "char1" went up
qemu-system-x86_64: -netdev type=vhost-user,id=net1,chardev=char2: chardev "char2" went up
pid 14913's current affinity list: 0,6
pid 14913's new affinity list: 0
pid 14914's current affinity list: 0,6
pid 14914's new affinity list: 0
pid 14931's current affinity list: 0,6
pid 14931's new affinity list: 0
pid 14932's current affinity list: 0,6
pid 14932's new affinity list: 0
pid 14934's current affinity list: 0,6
pid 14934's new affinity list: 0
Pinned QEMU to core 0
```

See `confs/lwaftrctl1.conf` for the parameters related with the VM settings.  
It expects to be able to connect to the VM with user `igalia` at 10.21.21.2.
You will need to have a user already created inside the VM as well as a network
interface correctly configured.  Example of `/etc/network/interfaces` inside the
guest:

```
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto eth2
iface eth2 inet static
        address 10.21.21.2
        netmask 255.255.255.0
        gateway 10.21.21.1
```

The `lwaftrctl vm` commands makes a pause of 30 seconds, after that it pins QEMU
and all its child process to a core.

## Start lwAFTR in a guest

It is possible to automatically start the lwAFTR inside the guest from the host:

```
lwaftrctl lwaftr start
```

Alternatively, it is possible to log into the VM and start the lwAFTR manually.

Under the current setup, the source code of the lwAFTR lives in the host.  It is
located at `~/workspace/snabb_guest`.  The code is available inside the guest 
through a mounting point setup when QEMU is launched:

```
-fsdev local,security_model=passthrough,id=fsdev0,path=${SHARED_LOCATION} \
  -device virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=share \
```

What the `lwaftrctl lwaftr start` command does is actually log into the VM with
VM_USER and execute the script `~/run_lwaftr`.  This script must contains the
inscrutions necessary to run the lwAFTR in the guest.  Basically, just copy 
`program/lwaftr/virt/run_lwaftr.sh.example` into your HOME folder in the VM
and rename it as `run_lwaftr.sh`.

If you guest and host use different architectures or operating systems,  you must
log into the guest and build the lwAFTR code.  Using the current settings as 
example:

```
$ ssh igalia@10.21.21.2
$ cd /mnt/host/snabb_guest/
$ sudo make clean
$ sudo make -C /mnt/host/snabb_guest/
```

The `lwaftrctl lwaftr start` command also launches a process inside a screen to
which is possible to attach.

```
igalia@testsystem:~$ screen -ls
There is a screen on:
    1331.lwaftr (02/09/2016 06:59:36 PM)    (Detached)
1 Socket in /var/run/screen/S-igalia.
```

Attach to this screen to see the RX/TX statistics of the runnign lwAFTR process.

```

# Stop lwAFTR in a guest

All the listed command so far can take a `stop` action that will stop them running.
There is also a `restart` action that will stop a command and start it again.

As the lwAFTR is started running `snabbnfv`, `vm` and `lwaftr` commands one after
another, the whole process should be stopped in inverse order, that is:  `lwaftr`,
`vm` and `snabbnfv`
.
