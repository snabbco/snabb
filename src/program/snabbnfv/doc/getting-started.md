# Snabb NFV Getting Started Guide

## Introduction

[Snabb NFV](http://snabb.co/nfv.html) is typically deployed for OpenStack
with components on the Network Node, the Database Node, and the Compute
Nodes.  This guide however documents the minimal steps required to
connect two virtual machines over LAN using Snabb NFV. No need to install
OpenStack or even `virsh`. A single compute node with at least 2 10GbE
ports is sufficient to launch two VMs and pass traffic between them.

## Prerequisites

* Compute node with a suitable PCIe slot for the NIC card (PCIe 2.0/3.0
  x8)
* [Ubuntu 14.04.2 LTS](http://releases.ubuntu.com/14.04/) installed on
  the compute node
* 2 10GbE Ethernet SFP+ ports based on [Intel
  82599](http://www.intel.com/content/dam/www/public/us/en/documents/datasheets/82599-10-gbe-controller-datasheet.pdf)
  controller
* Direct Attach/Twinaxial SFP+ loopback cable

## Hardware setup

Use the direct attach SFP+ cable to create a loop between both 10GbE
Ethernet ports.

## Compute node Kernel settings
 
IOMMU must be disabled on the server as documented under [Compute Node
Requirements](https://github.com/SnabbCo/snabbswitch/blob/master/src/program/snabbnfv/doc/compute-node-requirements.md). Disable
intel_iommu and set hugepages for 24GB (each page has 2MB -> 12288
pages). Allocating persistent huge pages on the kernel boot command line
is the most reliable method as memory has not yet become fragmented.

edit /etc/default/grub:

```
GRUB_CMDLINE_LINUX_DEFAULT="hugepages=12288 intel_iommu=off"
```

then activate it by running update-grub and reboot:

```
$ sudo update-grub
Generating grub configuration file ...
Found linux image: /boot/vmlinuz-3.16.0-30-generic
Found initrd image: /boot/initrd.img-3.16.0-30-generic
Found memtest86+ image: /boot/memtest86+.elf
Found memtest86+ image: /boot/memtest86+.bin
done
$ reboot
```
	
Verify iommu is disabled after the reboot:

```
$ sudo dmesg |grep -i iommu
[    0.000000] Command line: BOOT_IMAGE=/boot/vmlinuz-3.16.0-30-generic root=UUID=b1d14c48-a78c-467d-b04d-f5357bb6366a ro hugepages=12288 intel_iommu=off isolcpus=0-1
[    0.000000] Kernel command line: BOOT_IMAGE=/boot/vmlinuz-3.16.0-30-generic root=UUID=b1d14c48-a78c-467d-b04d-f5357bb6366a ro hugepages=12288 intel_iommu=off isolcpus=0-1
[    0.000000] Intel-IOMMU: disabled
```

Verify the successful allocation of persistent huge pages:

```
$ cat /proc/meminfo |grep -i huge
AnonHugePages:      6144 kB
HugePages_Total:   12288
HugePages_Free:    12288
HugePages_Rsvd:        0
HugePages_Surp:        0
Hugepagesize:       2048 kB
```

Mounting huge page (This is required for VM): 

```
$ sudo mkdir /mnt/huge
$ sudo mount -t hugetlbfs nodev /mnt/huge
```
	
Optionally, to make this permanent, update `/etc/fstab` as user `root`:

```
# cat >> /etc/fstab <<EOF
hugetlbfs       /mnt/huge  hugetlbfs       defaults        0 0
EOF
# mount -a
```

## Install developer tools

```
$ sudo apt-get install git build-essential pkg-config zlib1g-dev
$ sudo apt-get --no-install-recommends -y build-dep qemu
```

## Download, compile and install QEMU

We use the `v2.1.0-vhostuser` branch from the QEMU fork on SnabbCo to
reduce the risk of running in any incompatibilities with current
versions. This branch is maintained by Snabb Switch developers.

```
$ git clone -b v2.1.0-vhostuser --depth 50 https://github.com/SnabbCo/qemu
Cloning into 'qemu'...
remote: Counting objects: 4851, done.
remote: Compressing objects: 100% (3647/3647), done.
remote: Total 4851 (delta 1497), reused 2660 (delta 1119), pack-reused 0
Receiving objects: 100% (4851/4851), 10.81 MiB | 5.98 MiB/s, done.
Resolving deltas: 100% (1497/1497), done.
Checking connectivity... done.

$ cd qemu
$ ./configure --target-list=x86_64-softmmu
$ make -j
$ sudo make install
```

You should now have QEMU installed on your system:

```
/usr/local/bin/qemu-system-x86_64  --version
QEMU emulator version 2.1.0, Copyright (c) 2003-2008 Fabrice Bellard
```
	
## Download and build Snabb Switch

```
$ git clone --recursive https://github.com/SnabbCo/snabbswitch.git
$ cd snabbswitch; make
$ make -j
```
 
If all goes well, you will find the `snabb` executable in the `src/`
directory:

```
$ src/snabb
Usage: src/snabb <program> ...
	
This snabb executable has the following programs built in:
	  example_replay
	  example_spray
	  packetblaster
	  snabbmark
	  snabbnfv
	  snsh
	
For detailed usage of any program run:
	snabb <program> --help
	
If you rename (or copy or symlink) this executable with one of
the names above then that program will be chosen automatically.
```

Install `numactl` to control
[NUMA](https://en.wikipedia.org/wiki/Non-uniform_memory_access) policy
for processes or shared memory. We will not use `numactl` in this guide,
but its use will be essential to run any performance tests. `numactl`
runs processes with a specific NUMA scheduling or memory placement
policy.

```
$ sudo apt-get install numactl
$ numactl
usage: numactl [--all | -a] [--interleave= | -i <nodes>] [--preferred= | -p <node>]
               [--physcpubind= | -C <cpus>] [--cpunodebind= | -N <nodes>]
               [--membind= | -m <nodes>] [--localalloc | -l] command args ...
       numactl [--show | -s]
       numactl [--hardware | -H]
       numactl [--length | -l <length>] [--offset | -o <offset>] [--shmmode | -M <shmmode>]
               [--strict | -t]
               [--shmid | -I <id>] --shm | -S <shmkeyfile>
               [--shmid | -I <id>] --file | -f <tmpfsfile>
               [--huge | -u] [--touch | -T]
               memory policy | --dump | -d | --dump-nodes | -D

memory policy is --interleave | -i, --preferred | -p, --membind | -m, --localalloc | -l
<nodes> is a comma delimited list of node numbers or A-B ranges or all.
Instead of a number a node can also be:
  netdev:DEV the node connected to network device DEV
  file:PATH  the node the block device of path is connected to
  ip:HOST    the node of the network device host routes through
  block:PATH the node of block device path
  pci:[seg:]bus:dev[:func] The node of a PCI device
<cpus> is a comma delimited list of cpu numbers or A-B ranges or all
all ranges can be inverted with !
all numbers and ranges can be made cpuset-relative with +
the old --cpubind argument is deprecated.
use --cpunodebind or --physcpubind instead
<length> can have g (GB), m (MB) or k (KB) suffixes
```

## Run the Intel 82599 driver selftest
	
Find the PCI addresses of the available 10-Gigabit Intel 82599 ports in
the system:

```
$ lspci|grep 82599
04:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
04:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
```

Now run the Intel 82599 driver tests with `snabb snsh` using a loopback
cable between the two 10GbE ports. The application will unbind the
specified 10GbE ports (PCI address) from the Linux kernel, but will not
"return" them. E.g. `ifconfig -a` will not show these ports anymore.

```
$ cd ~/snabbswitch/src
$ sudo SNABB_TEST_INTEL10G_PCIDEVA="0000:04:00.0" SNABB_TEST_INTEL10G_PCIDEVB="0000:04:00.1" ./snabb snsh -t apps.intel.intel_app
selftest: intel_app
100 VF initializations:

Running iterated VMDq test...
test #  1: VMDq VLAN=101; 100ms burst. packet sent: 300,645
test #  2: VMDq VLAN=102; 100ms burst. packet sent: 661,725
test #  3: VMDq VLAN=103; 100ms burst. packet sent: 1,020,000
[...]
test #100: VMDq VLAN=200; 100ms burst. packet sent: 346,545
0000:04:00.0: avg wait_lu: 161.71, max redos: 0, avg: 0
-------
Send a bunch of packets from Am0
half of them go to nicAm1 and half go nowhere
link report:
                   0 sent on nicAm0.tx -> sink_ms.in1 (loss rate: 0%)
           1,706,695 sent on nicAm1.tx -> sink_ms.in2 (loss rate: 0%)
           3,413,940 sent on repeater_ms.output -> nicAm0.rx (loss rate: 0%)
                   2 sent on source_ms.out -> repeater_ms.input (loss rate: 0%)
-------
Transmitting bidirectionally between nicA and nicB
link report:
             471,424 sent on nicA.tx -> sink.in1 (loss rate: 0%)
             471,424 sent on nicB.tx -> sink.in2 (loss rate: 0%)
             939,675 sent on source1.out -> nicA.rx (loss rate: 0%)
             939,675 sent on source2.out -> nicB.rx (loss rate: 0%)
-------
Send traffic from a nicA (SF) to nicB (two VFs)
The packets should arrive evenly split between the VFs
link report:
                   0 sent on nicAs.tx -> sink_ms.in1 (loss rate: 0%)
             560,558 sent on nicBm0.tx -> sink_ms.in2 (loss rate: 0%)
             560,665 sent on nicBm1.tx -> sink_ms.in3 (loss rate: 0%)
           1,121,745 sent on repeater_ms.output -> nicAs.rx (loss rate: 0%)
                   2 sent on source_ms.out -> repeater_ms.input (loss rate: 0%)
selftest: ok
```

## Re-attach the 10GbE ports back to the host (optional)

If you need to re-attach a 10GbE ports back to the host OS, send its PCI
address to the ixgbe driver.

```
# ifconfig p2p1
p2p1: error fetching interface information: Device not found
# echo -n  "0000:04:00.0" > /sys/bus/pci/drivers/ixgbe/bind
# ifconfig p2p1
p2p1      Link encap:Ethernet  HWaddr 0c:c4:7a:1f:7e:60
          BROADCAST MULTICAST  MTU:1500  Metric:1
          RX packets:0 errors:0 dropped:0 overruns:0 frame:0
          TX packets:0 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000
          RX bytes:0 (0.0 B)  TX bytes:0 (0.0 B)

```

## Create and launch two VMs

Now that Snabb Switch can talk to both 10GbE ports successfully, lets
build and launch 2 test VMs and connect each of them to one of the 10GbE
port. First, we have to build an empty disk and then download and install
Ubuntu in it.

Create a disk for the VM:

```
$ qemu-img create -f qcow2 ubuntu.qcow2 16G
```
	
Download Ubuntu Server 14.04.2:

```
$ wget http://releases.ubuntu.com/14.04.2/ubuntu-14.04.2-server-amd64.iso
```
	
Launch the Ubuntu installer via QEMU and connect to its VNC console
running at <host>:5901. This can be done via a suitable VNC client.

```
$ sudo qemu-system-x86_64 -m 1024 -enable-kvm \
-drive if=virtio,file=ubuntu.qcow2,cache=none \
-cdrom ubuntu-14.04.2-server-amd64.iso -vnc :1
```

The installer will guide you through the setup of Ubuntu. Power down the
VM once you are done with the installation. We have now a master disk
image to create two VMs from and launch them individually. Create two
copies of the master image:

```
$ cp ubuntu.qcow2 ubuntu1.qcow2
$ cp ubuntu.qcow2 ubuntu2.qcow2
```
	
Before launching the VMs, we need to start Snabb Switch acting as a
virtio interface for the VMs. Snabb provides the `snabnfv traffic`
program for this, which is built into the `snabb` binary that we built
earlier. Source and documentation can be found at
[src/program/snabbnfv](https://github.com/SnabbCo/snabbswitch/tree/master/src/program/snabbnfv).

One `snabbnfv traffic` process is required per physical 10G port. A
configuration file specifies which packets are forwarded to the VM. You
can define more that one virtual port for each physical port, but we will
stick to a basic configuration that defines:

* the MAC address of the VM
* the port ID, which is used to identify a socket name

Create one `snabbnfv` configuration for each 10G port, `port1.cfg` and
`port2.cfg`:

```
return {
  { mac_address = "52:54:00:00:00:01",
    port_id = "id1",
  },
}
```

```
return {
  { mac_address = "52:54:00:00:00:02",
    port_id = "id2",
  },
}
```
	
Create a directory, where the vhost sockets will be created by QEMU and
connected to by `snabbnfv`:

```
$ mkdir ~/vhost-sockets
```
	
Launch `snabbnfv` in different terminals. For production and performance
testing, it is advised to pin the processes to CPU cores using `numactl`,
but for basic connectivity testing you can omit this.

Port 1:

```
$ sudo ./snabbswitch/src/snabb snabbnfv traffic -k 10 -D 0 \
  0000:04:00.0 ./port1.cfg ./vhost-sockets/vm1.socket
```

Port 2:

```
$ sudo ./snabbswitch/src/snabb snabbnfv traffic -k 10 -D 0 \
  0000:04:00.1 ./port2.cfg ./vhost-sockets/vm2.socket
```

Finally launch now the two VMs, either in different terminals or putting
them into the background. You can access their consoles via VNC ports
5901 and 5902 after launch.

ubuntu1:

```
$ sudo /usr/local/bin/qemu-system-x86_64 \
  -drive if=virtio,file=/home/mwiget/ubuntu1.qcow2 -M pc -smp 1 \
  --enable-kvm -cpu host -m 1024 -numa node,memdev=mem \
  -object memory-backend-file,id=mem,size=1024M,mem-path=/mnt/huge,share=on \
  -chardev socket,id=char0,path=/home/mwiget/vhost-sockets/vm1.socket,server \
  -netdev type=vhost-user,id=net0,chardev=char0  \
  -device virtio-net-pci,netdev=net0,mac=52:54:00:00:00:01 \
  -vnc :1
```
	
ubuntu2:

```
$ sudo /usr/local/bin/qemu-system-x86_64 \
  -drive if=virtio,file=/home/mwiget/ubuntu2.qcow2 -M pc -smp 1 \
  --enable-kvm -cpu host -m 1024 -numa node,memdev=mem \
  -object memory-backend-file,id=mem,size=1024M,mem-path=/mnt/huge,share=on \
  -chardev socket,id=char0,path=/home/mwiget/vhost-sockets/vm2.socket,server \
  -netdev type=vhost-user,id=net0,chardev=char0 \
  -device virtio-net-pci,netdev=net0,mac=52:54:00:00:00:02 \
  -vnc :2
```
	
Connect via VNC to ports 5901 and 5902, set a hostname and statically
assign an IP address to the eth0 interfaces (edit
`/etc/network/interfaces`; `ifdown eth0`; `ifup eth0`).

Have a peek at the terminals running both `snabbnfv traffic`
instances. You will see messages when it connects to the vhost sockets
created by qemu:

```
VIRTIO_F_ANY_LAYOUT VIRTIO_NET_F_MQ VIRTIO_NET_F_CTRL_VQ VIRTIO_NET_F_MRG_RXBUF VIRTIO_RING_F_INDIRECT_DESC VIRTIO_NET_F_CSUM
vhost_user: Caching features (0x18028001) in /tmp/vhost_features_.__vhost-sockets__vm1.socket
VIRTIO_F_ANY_LAYOUT VIRTIO_NET_F_CTRL_VQ VIRTIO_NET_F_MRG_RXBUF VIRTIO_RING_F_INDIRECT_DESC VIRTIO_NET_F_CSUM
```
 
If all went well so far, you can finally ping between both VMs. If you
used non-Linux virtual machines for this test,
e.g. [OpenBSD](http://www.openbsd.org), you might not be able to send or
receive packets within the guest OS. This issue can be solved (for
OpenBSD 5.7 at least) by forcing qemu to use vhost (vhostforce=on):

```
$ sudo /usr/local/bin/qemu-system-x86_64 \
  -drive if=virtio,file=/home/mwiget/openbsd1.qcow2 -M pc -smp 1 \
  --enable-kvm -cpu host -m 1024 -numa node,memdev=mem \
  -object memory-backend-file,id=mem,size=1024M,mem-path=/mnt/huge,share=on \
  -chardev socket,id=char0,path=/home/mwiget/vhost-sockets/vm1.socket,server \
  -netdev type=vhost-user,id=net0,chardev=char0,vhostforce=on  \
  -device virtio-net-pci,netdev=net0,mac=52:54:00:00:00:01 \
  -vnc :1
```

The `snabbnfv traffic` processes will print output like this:

```
link report:
                  14 sent on id1_NIC.tx -> id1_Virtio.rx (loss rate: 0%)
                  14 sent on id1_Virtio.tx -> id1_NIC.rx (loss rate: 0%)
load: time: 1.00s  fps: 3         fpGbps: 0.000 fpb: 0   bpp: 98   sleep: 100 us
load: time: 1.00s  fps: 4         fpGbps: 0.000 fpb: 0   bpp: 98   sleep: 100 us
load: time: 1.00s  fps: 3         fpGbps: 0.000 fpb: 0   bpp: 98   sleep: 100 us
load: time: 1.00s  fps: 4         fpGbps: 0.000 fpb: 0   bpp: 98   sleep: 100 us
load: time: 1.00s  fps: 3         fpGbps: 0.000 fpb: 0   bpp: 98   sleep: 100 us
```

and

```
link report:
                 100 sent on id2_NIC.tx -> id2_Virtio.rx (loss rate: 0%)
                 100 sent on id2_Virtio.tx -> id2_NIC.rx (loss rate: 0%)
load: time: 1.00s  fps: 4         fpGbps: 0.000 fpb: 0   bpp: 98   sleep: 100 us
load: time: 1.00s  fps: 4         fpGbps: 0.000 fpb: 0   bpp: 98   sleep: 100 us
load: time: 1.00s  fps: 4         fpGbps: 0.000 fpb: 0   bpp: 98   sleep: 100 us
load: time: 1.00s  fps: 3         fpGbps: 0.000 fpb: 0   bpp: 98   sleep: 100 us
load: time: 1.00s  fps: 4         fpGbps: 0.000 fpb: 0   bpp: 98   sleep: 100 us
load: time: 1.00s  fps: 3         fpGbps: 0.000 fpb: 0   bpp: 98   sleep: 100 us
load: time: 1.00s  fps: 4         fpGbps: 0.000 fpb: 0   bpp: 98   sleep: 100 us
load: time: 1.00s  fps: 4         fpGbps: 0.000 fpb: 0   bpp: 98   sleep: 100 us
load: time: 1.00s  fps: 3         fpGbps: 0.000 fpb: 0   bpp: 98   sleep: 100 us
load: time: 1.00s  fps: 4         fpGbps: 0.000 fpb: 0   bpp: 98   sleep: 100 us
link report:
                 120 sent on id2_NIC.tx -> id2_Virtio.rx (loss rate: 0%)
                 120 sent on id2_Virtio.tx -> id2_NIC.rx (loss rate: 0%)
load: time: 1.00s  fps: 3         fpGbps: 0.000 fpb: 0   bpp: 98   sleep: 100 us
load: time: 1.00s  fps: 3         fpGbps: 0.000 fpb: 0   bpp: 98   sleep: 100 us
```

The difference in packet counters is a result of stopping and starting
one of the `snabbnfv traffic` processes mid-flight. This might not work
with upstream QEMU versions.

## Next Steps

Here are some suggested steps to continue learning about Snabb Switch.

1. Read more on snabbnfv
[README.md](https://github.com/SnabbCo/snabbswitch/blob/master/src/program/snabbnfv/README.md) and the other documents in the doc folder [https://github.com/SnabbCo/snabbswitch/tree/master/src/program/snabbnfv/doc](https://github.com/SnabbCo/snabbswitch/tree/master/src/program/snabbnfv/doc)
2. Before running any performance tests, familiarize yourself with
numactl and how it affects Snabb Switch.

Do not hesitate to contact the Snabb community on the
[snabb-devel@googlegroups.com](https://groups.google.com/forum/#!forum/snabb-devel)
mailing list.
