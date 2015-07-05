# Snabb NFV Getting Started Guide

## Introduction

[Snabb NFV](http://snabb.co/nfv.html) is typically deployed for OpenStack with
components on the Network Node, the Database Node, and the Compute
Nodes. 
This guide however documents the minimal steps required to connect two virtual machines over Snabb Switch using the Snabbnfv Traffic application. No need to install OpenStack or even virsh. A single compute node with at least 2 10GbE ports is sufficient to launch two VMs and pass traffic between them. 

## Prerequisites

* Compute node with a suitable PCIe slot for the NIC card (PCIe 2.0/3.0 x8)
* [Ubuntu 14.04.2 LTS](http://releases.ubuntu.com/14.04/) installed on the compute node
* 2 10GbE Ethernet SFP+ ports based on [Intel 82599](http://www.intel.com/content/dam/www/public/us/en/documents/datasheets/82599-10-gbe-controller-datasheet.pdf) controller
* Direct Attach/Twinaxial SFP+ loopback cable

## Hardware setup

Use the direct attach SFP+ cable to create a loop between both 10GbE Ethernet ports. 

## Compute node Kernel settings
 
IOMMU must be disabled on the server as documented under [Compute Node Requirements](https://github.com/SnabbCo/snabbswitch/blob/master/src/program/snabbnfv/doc/compute-node-requirements.md). Disable intel_iommu and set hugepages for 24GB (each page has 2MB -> 12288 pages). Allocating persistent huge pages on the kernel boot command line is the most reliable method as memory has not yet become fragmented.

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
	
Optionally, to make this permanent, updated /etc/fstab as user root:

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

We use here the v2.1.0-vhostuser branch from the QEMU fork on SnabbCo to reduce the risk of running in any incompatibilities with current versions. This branch is maintained by snabb developers. 

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

You should have now qemu installed on your system:

```
/usr/local/bin/qemu-system-x86_64  --version
QEMU emulator version 2.1.0, Copyright (c) 2003-2008 Fabrice Bellard
```
	
## Download and build snabbswitch 

```
$ git clone --recursive https://github.com/SnabbCo/snabbswitch.git
$ cd snabbswitch; make
$ make -j
```
 
If all goes well, you will find the snabb executable in the src directory:

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

Install numactl to control [NUMA](https://en.wikipedia.org/wiki/Non-uniform_memory_access) policy for processes or shared memory. We won't use numactl in this getting started guide, but its use will be essential to run any performance tests. Numactl runs processes with a specific NUMA scheduling or memory placement policy.

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

## Run the Snabb selftest app
	
Find the PCI addresses of the available 10-Gigabit Intel 82599 ports in the system:

```
$ lspci|grep 82599
04:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
04:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
```

Now run some Intel tests with snabb snsh using a loopback cable between the two 10GbE ports. The application will unbind the specified 10GbE ports (PCI address) from the Linux kernel, but won't "return" them. So don't be surprised when 'ifconfig -a' won't show these ports anymore. 

```
$ cd ~/snabbswitch/src
$ sudo SNABB_TEST_INTEL10G_PCIDEVA="0000:04:00.0" SNABB_TEST_INTEL10G_PCIDEVB="0000:04:00.1" ./snabb snsh -t apps.intel.intel_app
selftest: intel_app
100 VF initializations:

Running iterated VMDq test...
test #  1: VMDq VLAN=101; 100ms burst. packet sent: 300,645
test #  2: VMDq VLAN=102; 100ms burst. packet sent: 661,725
test #  3: VMDq VLAN=103; 100ms burst. packet sent: 1,020,000
test #  4: VMDq VLAN=104; 100ms burst. packet sent: 1,376,235
test #  5: VMDq VLAN=105; 100ms burst. packet sent: 1,730,175
test #  6: VMDq VLAN=106; 100ms burst. packet sent: 2,082,330
test #  7: VMDq VLAN=107; 100ms burst. packet sent: 2,434,485
test #  8: VMDq VLAN=108; 100ms burst. packet sent: 2,784,090
test #  9: VMDq VLAN=109; 100ms burst. packet sent: 3,132,420
test # 10: VMDq VLAN=110; 100ms burst. packet sent: 3,478,455
test # 11: VMDq VLAN=111; 100ms burst. packet sent: 3,824,235
test # 12: VMDq VLAN=112; 100ms burst. packet sent: 4,168,740
test # 13: VMDq VLAN=113; 100ms burst. packet sent: 4,511,205
test # 14: VMDq VLAN=114; 100ms burst. packet sent: 4,852,395
test # 15: VMDq VLAN=115; 100ms burst. packet sent: 5,192,310
test # 16: VMDq VLAN=116; 100ms burst. packet sent: 5,530,440
test # 17: VMDq VLAN=117; 100ms burst. packet sent: 5,867,805
test # 18: VMDq VLAN=118; 100ms burst. packet sent: 6,203,385
test # 19: VMDq VLAN=119; 100ms burst. packet sent: 6,538,200
test # 20: VMDq VLAN=120; 100ms burst. packet sent: 6,871,230
test # 21: VMDq VLAN=121; 100ms burst. packet sent: 7,203,495
test # 22: VMDq VLAN=122; 100ms burst. packet sent: 7,534,485
test # 23: VMDq VLAN=123; 100ms burst. packet sent: 7,863,945
test # 24: VMDq VLAN=124; 100ms burst. packet sent: 8,192,385
test # 25: VMDq VLAN=125; 100ms burst. packet sent: 8,519,805
test # 26: VMDq VLAN=126; 100ms burst. packet sent: 8,846,205
test # 27: VMDq VLAN=127; 100ms burst. packet sent: 9,171,585
test # 28: VMDq VLAN=128; 100ms burst. packet sent: 9,495,180
test # 29: VMDq VLAN=129; 100ms burst. packet sent: 9,818,775
test # 30: VMDq VLAN=130; 100ms burst. packet sent: 10,141,095
test # 31: VMDq VLAN=131; 100ms burst. packet sent: 10,462,650
test # 32: VMDq VLAN=132; 100ms burst. packet sent: 10,783,440
test # 33: VMDq VLAN=133; 100ms burst. packet sent: 11,102,700
test # 34: VMDq VLAN=134; 100ms burst. packet sent: 11,421,450
test # 35: VMDq VLAN=135; 100ms burst. packet sent: 11,739,435
test # 36: VMDq VLAN=136; 100ms burst. packet sent: 12,056,400
test # 37: VMDq VLAN=137; 100ms burst. packet sent: 12,372,090
test # 38: VMDq VLAN=138; 100ms burst. packet sent: 12,687,015
test # 39: VMDq VLAN=139; 100ms burst. packet sent: 13,000,665
test # 40: VMDq VLAN=140; 100ms burst. packet sent: 13,312,530
test # 41: VMDq VLAN=141; 100ms burst. packet sent: 13,624,395
test # 42: VMDq VLAN=142; 100ms burst. packet sent: 13,935,495
test # 43: VMDq VLAN=143; 100ms burst. packet sent: 14,245,320
test # 44: VMDq VLAN=144; 100ms burst. packet sent: 14,554,635
test # 45: VMDq VLAN=145; 100ms burst. packet sent: 14,863,185
test # 46: VMDq VLAN=146; 100ms burst. packet sent: 15,170,970
test # 47: VMDq VLAN=147; 100ms burst. packet sent: 15,477,735
test # 48: VMDq VLAN=148; 100ms burst. packet sent: 15,784,245
test # 49: VMDq VLAN=149; 100ms burst. packet sent: 16,089,480
test # 50: VMDq VLAN=150; 100ms burst. packet sent: 16,394,205
test # 51: VMDq VLAN=151; 100ms burst. packet sent: 16,698,420
test # 52: VMDq VLAN=152; 100ms burst. packet sent: 17,001,615
test # 53: VMDq VLAN=153; 100ms burst. packet sent: 17,304,300
test # 54: VMDq VLAN=154; 100ms burst. packet sent: 17,606,475
test # 55: VMDq VLAN=155; 100ms burst. packet sent: 17,908,140
test # 56: VMDq VLAN=156; 100ms burst. packet sent: 18,208,785
test # 57: VMDq VLAN=157; 100ms burst. packet sent: 18,508,920
test # 58: VMDq VLAN=158; 100ms burst. packet sent: 18,808,290
test # 59: VMDq VLAN=159; 100ms burst. packet sent: 19,106,895
test # 60: VMDq VLAN=160; 100ms burst. packet sent: 19,404,990
test # 61: VMDq VLAN=161; 100ms burst. packet sent: 19,702,320
test # 62: VMDq VLAN=162; 100ms burst. packet sent: 19,999,395
test # 63: VMDq VLAN=163; 100ms burst. packet sent: 20,295,450
test # 64: VMDq VLAN=164; 100ms burst. packet sent: 20,590,995
test # 65: VMDq VLAN=165; 100ms burst. packet sent: 20,885,520
test # 66: VMDq VLAN=166; 100ms burst. packet sent: 21,179,790
test # 67: VMDq VLAN=167; 100ms burst. packet sent: 21,473,550
test # 68: VMDq VLAN=168; 100ms burst. packet sent: 21,766,290
test # 69: VMDq VLAN=169; 100ms burst. packet sent: 22,058,265
test # 70: VMDq VLAN=170; 100ms burst. packet sent: 22,349,985
test # 71: VMDq VLAN=171; 100ms burst. packet sent: 22,641,195
test # 72: VMDq VLAN=172; 100ms burst. packet sent: 22,931,640
test # 73: VMDq VLAN=173; 100ms burst. packet sent: 23,221,320
test # 74: VMDq VLAN=174; 100ms burst. packet sent: 23,510,235
test # 75: VMDq VLAN=175; 100ms burst. packet sent: 23,798,385
test # 76: VMDq VLAN=176; 100ms burst. packet sent: 24,085,770
test # 77: VMDq VLAN=177; 100ms burst. packet sent: 24,372,900
test # 78: VMDq VLAN=178; 100ms burst. packet sent: 24,659,265
test # 79: VMDq VLAN=179; 100ms burst. packet sent: 24,945,375
test # 80: VMDq VLAN=180; 100ms burst. packet sent: 25,230,210
test # 81: VMDq VLAN=181; 100ms burst. packet sent: 25,514,790
test # 82: VMDq VLAN=182; 100ms burst. packet sent: 25,798,605
test # 83: VMDq VLAN=183; 100ms burst. packet sent: 26,082,165
test # 84: VMDq VLAN=184; 100ms burst. packet sent: 26,364,705
test # 85: VMDq VLAN=185; 100ms burst. packet sent: 26,646,990
test # 86: VMDq VLAN=186; 100ms burst. packet sent: 26,928,255
test # 87: VMDq VLAN=187; 100ms burst. packet sent: 27,209,010
test # 88: VMDq VLAN=188; 100ms burst. packet sent: 27,488,490
test # 89: VMDq VLAN=189; 100ms burst. packet sent: 27,768,225
test # 90: VMDq VLAN=190; 100ms burst. packet sent: 28,047,705
test # 91: VMDq VLAN=191; 100ms burst. packet sent: 28,326,420
test # 92: VMDq VLAN=192; 100ms burst. packet sent: 28,604,625
test # 93: VMDq VLAN=193; 100ms burst. packet sent: 28,882,065
test # 94: VMDq VLAN=194; 100ms burst. packet sent: 29,158,995
test # 95: VMDq VLAN=195; 100ms burst. packet sent: 29,435,415
test # 96: VMDq VLAN=196; 100ms burst. packet sent: 29,711,070
test # 97: VMDq VLAN=197; 100ms burst. packet sent: 29,986,215
test # 98: VMDq VLAN=198; 100ms burst. packet sent: 30,260,850
test # 99: VMDq VLAN=199; 100ms burst. packet sent: 30,535,230
test #100: VMDq VLAN=200; 100ms burst. packet sent: 30,808,845
0000:04:00.0: avg wait_lu: 187, max redos: 0, avg: 0
100 PF full cycles

Running iterated VMDq test...
test #  1: VMDq VLAN=101; 100ms burst. packet sent: 363,885
test #  2: VMDq VLAN=102; 100ms burst. packet sent: 353,940
test #  3: VMDq VLAN=103; 100ms burst. packet sent: 362,865
test #  4: VMDq VLAN=104; 100ms burst. packet sent: 361,590
test #  5: VMDq VLAN=105; 100ms burst. packet sent: 363,630
test #  6: VMDq VLAN=106; 100ms burst. packet sent: 364,395
test #  7: VMDq VLAN=107; 100ms burst. packet sent: 271,320
test #  8: VMDq VLAN=108; 100ms burst. packet sent: 358,530
test #  9: VMDq VLAN=109; 100ms burst. packet sent: 357,510
test # 10: VMDq VLAN=110; 100ms burst. packet sent: 345,270
test # 11: VMDq VLAN=111; 100ms burst. packet sent: 355,470
test # 12: VMDq VLAN=112; 100ms burst. packet sent: 352,155
test # 13: VMDq VLAN=113; 100ms burst. packet sent: 347,565
test # 14: VMDq VLAN=114; 100ms burst. packet sent: 352,410
test # 15: VMDq VLAN=115; 100ms burst. packet sent: 357,000
test # 16: VMDq VLAN=116; 100ms burst. packet sent: 343,995
test # 17: VMDq VLAN=117; 100ms burst. packet sent: 345,780
test # 18: VMDq VLAN=118; 100ms burst. packet sent: 353,940
test # 19: VMDq VLAN=119; 100ms burst. packet sent: 351,135
test # 20: VMDq VLAN=120; 100ms burst. packet sent: 354,195
test # 21: VMDq VLAN=121; 100ms burst. packet sent: 352,410
test # 22: VMDq VLAN=122; 100ms burst. packet sent: 186,915
test # 23: VMDq VLAN=123; 100ms burst. packet sent: 351,645
test # 24: VMDq VLAN=124; 100ms burst. packet sent: 339,405
test # 25: VMDq VLAN=125; 100ms burst. packet sent: 348,585
test # 26: VMDq VLAN=126; 100ms burst. packet sent: 352,155
test # 27: VMDq VLAN=127; 100ms burst. packet sent: 353,940
test # 28: VMDq VLAN=128; 100ms burst. packet sent: 347,055
test # 29: VMDq VLAN=129; 100ms burst. packet sent: 353,430
test # 30: VMDq VLAN=130; 100ms burst. packet sent: 340,680
test # 31: VMDq VLAN=131; 100ms burst. packet sent: 330,990
test # 32: VMDq VLAN=132; 100ms burst. packet sent: 350,625
test # 33: VMDq VLAN=133; 100ms burst. packet sent: 352,920
test # 34: VMDq VLAN=134; 100ms burst. packet sent: 346,545
test # 35: VMDq VLAN=135; 100ms burst. packet sent: 353,940
test # 36: VMDq VLAN=136; 100ms burst. packet sent: 335,070
test # 37: VMDq VLAN=137; 100ms burst. packet sent: 347,565
test # 38: VMDq VLAN=138; 100ms burst. packet sent: 349,095
test # 39: VMDq VLAN=139; 100ms burst. packet sent: 351,900
test # 40: VMDq VLAN=140; 100ms burst. packet sent: 339,915
test # 41: VMDq VLAN=141; 100ms burst. packet sent: 326,400
test # 42: VMDq VLAN=142; 100ms burst. packet sent: 333,795
test # 43: VMDq VLAN=143; 100ms burst. packet sent: 348,840
test # 44: VMDq VLAN=144; 100ms burst. packet sent: 336,855
test # 45: VMDq VLAN=145; 100ms burst. packet sent: 346,035
test # 46: VMDq VLAN=146; 100ms burst. packet sent: 344,250
test # 47: VMDq VLAN=147; 100ms burst. packet sent: 339,405
test # 48: VMDq VLAN=148; 100ms burst. packet sent: 342,210
test # 49: VMDq VLAN=149; 100ms burst. packet sent: 335,070
test # 50: VMDq VLAN=150; 100ms burst. packet sent: 346,545
test # 51: VMDq VLAN=151; 100ms burst. packet sent: 338,385
test # 52: VMDq VLAN=152; 100ms burst. packet sent: 352,410
test # 53: VMDq VLAN=153; 100ms burst. packet sent: 337,875
test # 54: VMDq VLAN=154; 100ms burst. packet sent: 29,580
test # 55: VMDq VLAN=155; 100ms burst. packet sent: 339,405
test # 56: VMDq VLAN=156; 100ms burst. packet sent: 346,290
test # 57: VMDq VLAN=157; 100ms burst. packet sent: 346,800
test # 58: VMDq VLAN=158; 100ms burst. packet sent: 346,035
test # 59: VMDq VLAN=159; 100ms burst. packet sent: 335,325
test # 60: VMDq VLAN=160; 100ms burst. packet sent: 344,760
test # 61: VMDq VLAN=161; 100ms burst. packet sent: 338,130
test # 62: VMDq VLAN=162; 100ms burst. packet sent: 346,800
test # 63: VMDq VLAN=163; 100ms burst. packet sent: 320,535
test # 64: VMDq VLAN=164; 100ms burst. packet sent: 335,580
test # 65: VMDq VLAN=165; 100ms burst. packet sent: 314,925
test # 66: VMDq VLAN=166; 100ms burst. packet sent: 312,885
test # 67: VMDq VLAN=167; 100ms burst. packet sent: 336,600
test # 68: VMDq VLAN=168; 100ms burst. packet sent: 347,055
test # 69: VMDq VLAN=169; 100ms burst. packet sent: 337,875
test # 70: VMDq VLAN=170; 100ms burst. packet sent: 340,170
test # 71: VMDq VLAN=171; 100ms burst. packet sent: 338,895
test # 72: VMDq VLAN=172; 100ms burst. packet sent: 341,445
test # 73: VMDq VLAN=173; 100ms burst. packet sent: 339,405
test # 74: VMDq VLAN=174; 100ms burst. packet sent: 348,585
test # 75: VMDq VLAN=175; 100ms burst. packet sent: 324,870
test # 76: VMDq VLAN=176; 100ms burst. packet sent: 351,900
test # 77: VMDq VLAN=177; 100ms burst. packet sent: 339,150
test # 78: VMDq VLAN=178; 100ms burst. packet sent: 344,505
test # 79: VMDq VLAN=179; 100ms burst. packet sent: 342,975
test # 80: VMDq VLAN=180; 100ms burst. packet sent: 327,165
test # 81: VMDq VLAN=181; 100ms burst. packet sent: 339,915
test # 82: VMDq VLAN=182; 100ms burst. packet sent: 326,910
test # 83: VMDq VLAN=183; 100ms burst. packet sent: 349,605
test # 84: VMDq VLAN=184; 100ms burst. packet sent: 343,995
test # 85: VMDq VLAN=185; 100ms burst. packet sent: 338,895
test # 86: VMDq VLAN=186; 100ms burst. packet sent: 344,505
test # 87: VMDq VLAN=187; 100ms burst. packet sent: 319,260
test # 88: VMDq VLAN=188; 100ms burst. packet sent: 337,620
test # 89: VMDq VLAN=189; 100ms burst. packet sent: 338,640
test # 90: VMDq VLAN=190; 100ms burst. packet sent: 325,125
test # 91: VMDq VLAN=191; 100ms burst. packet sent: 344,250
test # 92: VMDq VLAN=192; 100ms burst. packet sent: 347,565
test # 93: VMDq VLAN=193; 100ms burst. packet sent: 323,595
test # 94: VMDq VLAN=194; 100ms burst. packet sent: 336,855
test # 95: VMDq VLAN=195; 100ms burst. packet sent: 335,835
test # 96: VMDq VLAN=196; 100ms burst. packet sent: 339,150
test # 97: VMDq VLAN=197; 100ms burst. packet sent: 339,150
test # 98: VMDq VLAN=198; 100ms burst. packet sent: 336,600
test # 99: VMDq VLAN=199; 100ms burst. packet sent: 324,870
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

## Create and launch two VM's

Now that snabbswitch can talk to both 10GbE ports successfully, lets build and launch 2 test VM's and connect each of them to one of the 10GbE port. First, we have to build an empty disk, download and install Ubuntu in it:

Create a disk for the VM:

```
$ qemu-img create -f qcow2 ubuntu.qcow2 16G
```
	
Download ubuntu server 14.04.2:

```
$ wget http://releases.ubuntu.com/14.04.2/ubuntu-14.04.2-server-amd64.iso
```
	
Launch the ubuntu installer via qemu and connect to its VNC console running at <host>:5901. This can be done via a suitable VNC client.

```
$ sudo qemu-system-x86_64 -m 1024 -enable-kvm \
-drive if=virtio,file=ubuntu.qcow2,cache=none \
-cdrom ubuntu-14.04.2-server-amd64.iso -vnc :1
```

The installer guides you thru the setup of ubuntu. I picked username ubuntu with password ubuntu and use the whole disk without LVM, no automatic updates and selected openssh as the only optional package to install.
Kill qemu after the reboot. 

We have now a master VM ubuntu virtual disk to create two VM's from and launch them individually. Create first two copies:

```
$ cp ubuntu.qcow2 ubuntu1.qcow2
$ cp ubuntu.qcow2 ubuntu2.qcow2
```
	
Before launching the VM's, we need to prepare snabb to work as virtio interface for the VM's. Snabb offers snabnfv traffic app for this, which is built-into the snabb binary that was built earlier. Source and documentation can be found at [https://github.com/SnabbCo/snabbswitch/tree/next/src/program/snabbnfv](https://github.com/SnabbCo/snabbswitch/tree/next/src/program/snabbnfv)

One Snabbnfv traffic process is required per 10 Gigabit port and uses a configuration file with port information for every vhost interface:

* VLAN
* MAC address of the VM
* Id, which is used to identify a socket name

VLAN and MAC are used to pass ethernet frames based on destination address to the correct vhost interface. I created a separate config file per 10GbE port.

```
$ cat port1.cfg
return {
  { vlan = 431,
    mac_address = "52:54:00:00:00:01",
    port_id = "id1",
  },
}
$ cat port2.cfg
return {
  { vlan = 431,
    mac_address = "52:54:00:00:00:02",
    port_id = "id2",
  },
}
```
	
Create a directory, where the vhost sockets will be created by qemu and connected to by snabbnfv:

```
$ mkdir ~/vhost-sockets
```
	
Launch snabbnfv in different terminals. For production and performance testing, it is advised to pin the processes to CPU core's using numactl, but for basic connectivity testing I left this complexity out for now.

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

Finally launch now the two VM's, either in different terminals or putting them into the background. You can access their consoles via VNC ports 5901 and 5902 after launch.

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
	
Connect via VNC to ports 5901 and 5902, set a hostname and statically assign an IP address to the eth0 interfaces (edit /etc/network/interfaces; ifdown eth0; ifup eth0).

Have a peek at the terminals running both snabbnfv traffic commands. You will see messages when it connects to the vhost sockets created by qemu:

```
VIRTIO_F_ANY_LAYOUT VIRTIO_NET_F_MQ VIRTIO_NET_F_CTRL_VQ VIRTIO_NET_F_MRG_RXBUF VIRTIO_RING_F_INDIRECT_DESC VIRTIO_NET_F_CSUM
vhost_user: Caching features (0x18028001) in /tmp/vhost_features_.__vhost-sockets__vm1.socket
VIRTIO_F_ANY_LAYOUT VIRTIO_NET_F_CTRL_VQ VIRTIO_NET_F_MRG_RXBUF VIRTIO_RING_F_INDIRECT_DESC VIRTIO_NET_F_CSUM
```
 
If all went well so far, you can finally ping between both VM's. If you used non-Linux virtual machines for this test, e.g. [OpenBSD](http://www.openbsd.org), you might not be able to send or receive packets within the guest OS. This issue can be solved (for OpenBSD 5.7 at least) by forcing qemu to use vhost (vhostforce=on):

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

The snabbnfv terminals will show counter output similar to:

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

The difference in packet counters is a result of me stopping and starting one of the snabbnfv processes mid-flight. According to the documentation thats ok and it does indeed work just fine. 

## Next Steps

Here are some suggested steps to continue learning about Snabb Switch.

1. Read more on snabbnfv
[README.md](https://github.com/SnabbCo/snabbswitch/blob/master/src/program/snabbnfv/README.md) and the other documents in the doc folder [https://github.com/SnabbCo/snabbswitch/tree/master/src/program/snabbnfv/doc](https://github.com/SnabbCo/snabbswitch/tree/master/src/program/snabbnfv/doc)
2. Before running any performance tests, familiarize userself with numactl and how it affects snabbswitch. (TODO: is there a good intro page to this topics I can link to?)

Don't hesitate to contact the Snabb community on the
[snabb-devel@googlegroups.com](https://groups.google.com/forum/#!forum/snabb-devel)
mailing list.
