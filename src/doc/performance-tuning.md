# Maximizing deployment performance

For maximum performance, several hardware, operating system and Snabb  parameters need
to be tuned. Note that this document is only on tuning for deployment
performance, not on how to write performant Snabb code.

## Snabb
### ring-buffer/num_descriptors
Defined in src/apps/intel10g.lua and adjustable before (!) the NIC gets initialized:

```
require('apps.intel.intel10g').num_descriptors = ring_buffer_size
...
config.app(c, "nic", require(device_info.driver).driver, {...})
```

The default of 512 seems too small, based on load test at IMIX line rate tests against lwaftr, 1024 or 2048 gave equally good results. Num_descriptors controls the Receive Descriptor Length on the Intel 82599 Controller, which determines the number of bytes allocated to the circular buffer. This value must be a multiple of 128 (the maximum cache line size). Since each descriptor is 16 bytes in length, the total number of receive descriptors is always a multiple of 8. In networking terms, this defines the ingress buffer size in packets (TODO: is this correct?). Larger ingress buffer can reduce packet loss while Snabb is busy handling other packets, but it will also increase latency for packets waiting in the queue to be picked up by Snabb.

### Enable engine.busywait
Defined in src/core/app.lua and enabled before calling engine.main() via

```
engine.busywait = true
engine.main(...)
```
If true then the engine will poll for new data in a tight loop (100% CPU) instead of sleeping according to the Hz setting. This will reduce overall packet latency and increase throughput at the cost of utilizing the CPU hosting Snabb at 100%. 

### Monitor ifInDiscards
Snabb offers SNMP based ifInDiscards counters when SNMP is enabled. (TODO: need an easier way to expose these counters from the Intel register QPRDC).

Enable SNMP in Snabb:

```
config.app(c, nic_id, require(device_info.driver).driver, 
  {..., snmp = { directory = "/tmp", status_timer = 1 }, ... })
```

Then access ifInDiscards counter via od (the exact offset can be calculated from the file /tmp/0000:81:00.0.index):

```
od -j 305 -A none -N 4 -t u4 /tmp/0000\:81\:00.0
      94543
```
Above example shows 94543 discarded packets at ingress on Port 0 since launching Snabb.

## Qemu & Vhost-User
[Vhost-User](http://www.virtualopensystems.com/en/solutions/guides/snabbswitch-qemu/) is used to connect Snabb with a high performance virtual interface attached to a Qemu based virtual machine.  This requires hugepages (explained further down) made available to Qemu:

```
cd <qemu-dir>/bin/x86_64-softmmu/
qemu-system-x86_64 -enable-kvm -m 8000 -smp 2 \
    -chardev socket,id=char0,path=./xe0.socket,server \
    -netdev type=vhost-user,id=net0,chardev=char0 \
    -device virtio-net-pci,netdev=net0,mac=02:cf:69:15:0b:00   \
    -object memory-backend-file,id=mem,size=8000M,mem-path=/hugetlbfs,share=on \
    -numa node,memdev=mem -mem-prealloc \
    -realtime mlock=on  \
    /path/to/img
```

The allocated memory must match the memory-backend-file size (example shows 8GB). While qemu will fail to boot if there isn't enough hugepages allocated, it is recommended to have some spare and note that the pages are split amongst the NUMA nodes. Check the paragraph on NUMA in this  document.
It is recommended to specify the qemu option '-realtime mlock=on', despite it being the default. This ensures memory doesn't get swapped out. 

## Hardware / BIOS
### Disable Hyper-Threading
Disable hyper-threading (HT) in the BIOS. Even with isolating the correct hyper-threaded CPU's, can create latency spikes, leading to packet loss, when enabled. (TODO: do we have one of the automated tests showing this?)
According to [Intel on Hyper-Threading](http://www.intel.com/content/www/us/en/architecture-and-technology/hyper-threading/hyper-threading-technology.html): "Intel® Hyper-Threading Technology (Intel® HT Technology) uses processor resources more efficiently, enabling multiple threads to run on each core. As a performance feature, it also increases processor throughput, improving overall performance on threaded software.". Snabb runs single threaded, so can't benefit directly from HT. 
### Performance Profile set to Max 
Servers are optimized for energy efficiency. While this is great for application servers, Virtual Network Functions like Snabb benefit from performance optimized settings. Each vendor offers different BIOS settings to enable or disable energy efficiency settings or profiles. They are typically named "Max performance", "Energy Efficiency" and "Custom".  Select "Max performance" for latency sensitive Snabb use. 
### Turbo Mode
Intel Turbo Boost Technology allows processor cores to run faster than the rated operating frequency if they're operating below power, current, and temperature specification limits. (TODO: impact not yet analyzed on Snabb, nor if it is controlled by the performance profile). 
## Linux Kernel
### Disable IOMMU
Sandybridge CPUs have a known issue on its IOTBL huge page support, impacting small packet performance.  Newer CPUs don't have this issue.
(TODO, only found this info here: [http://dpdk.org/ml/archives/dev/2014-October/007411.html]()
(TODO: pass through mode: [https://lwn.net/Articles/329174/]())

Add IOMMU=pt (pass through) to the kernel:

```
GRUB_CMDLINE_LINUX_DEFAULT="... iommu=pt ... "
```
### Enable huge pages
Required for Snabb to function. Select size 1G. On NUMA systems (more than one CPU socket/node), the pages are equally spread between all sockets. 

```
GRUB_CMDLINE_LINUX_DEFAULT="... default_hugepagesz=1GB hugepagesz=1G hugepages=64 ..."
```
Actual use of hugepages can be monitored with 

```
$ cat /proc/meminfo |grep Huge
AnonHugePages:  12310528 kB
HugePages_Total:      64
HugePages_Free:       58
HugePages_Rsvd:        0
HugePages_Surp:        0
Hugepagesize:    1048576 kB
```
 On NUMA systems, the allocation and usage per node can be seen with
 
```
$ cat /sys/devices/system/node/node*/meminfo|grep Huge
Node 0 AnonHugePages:     12288 kB
Node 0 HugePages_Total:    32
Node 0 HugePages_Free:     32
Node 0 HugePages_Surp:      0
Node 1 AnonHugePages:  12298240 kB
Node 1 HugePages_Total:    32
Node 1 HugePages_Free:     26
Node 1 HugePages_Surp:      0
```
(Above example shows six 1G pages in use on Node 1 with 2 Snabb processes serving one 10GE port each).

### Disable irqbalance
The purpose of irqbalance is to distribute hardware interrupts across processors on a multiprocessor system in order to increase performance. Ubuntu has this installed and running in its default server installation. Snabb doesn't use interrupts to read packets. Disabling irqbalance forces CPU 0 to serve all hardware interrupts. To disable, either uninstall irqbalance or disable it:

```
$ sudo service irqbalance
```

To make it permanent, set ENABLED to 0 in /etc/default/irqbalance:

```
$ cat /etc/default/irqbalance
#Configuration for the irqbalance daemon

#Should irqbalance be enabled?
ENABLED="0"
...
```

Various interrupt counters per CPU core can be retrieved via 

```
$ cat /proc/interrupts
            CPU0       CPU1       CPU2       CPU3       CPU4       CPU5       CPU6       CPU7       CPU8       CPU9       CPU10      CPU11      CPU12      CPU13      CPU14      CPU15      CPU16      CPU17      CPU18      CPU19
   0:         41          0          0          0          0          0          0          0          0          0          0          0          0          0          0          0          0          0          0          0  IR-IO-APIC    2-edge      timer
   8:          1          0          0          0          0          0          0          0          0          0          0          0          0          0          0          0          0          0          0          0  IR-IO-APIC    8-edge      rtc0
...
```
  
### CPU governor 
settings should be performance, rather than ondemand or powersaving. (TODO: put the command here. Is this a linux kernel parameter?)

## CPU Isolation/Pinning
Snabb makes 100% use of a single CPU core, hence its important that no other task ever uses that core. Thats best achieved by telling the kernel scheduler via kernel option 'isolcpus' to ignore cores designated to Snabb. In /etc/default/grub (example reserves cores 18 and 19 for Snabb):

```
GRUB_CMDLINE_LINUX_DEFAULT="... isolcpus=18-19 ..."
```
Note: Never use CPU 0 for Snabb, because the Linux kernel uses CPU 0 to handle interrupts, including NMI (non-maskable interrupts).

Launch Snabb either via 'taskset' or 'numactl'. Examples to ping it on CPU 18:

```
taskset -c 18 ./snabb ...
numactl --physcpubind=18 ./snabb ...
```

Note: Always use 'numactl' on NUMA servers, to limit allocation of memory to specified NUMA nodes with option '--membind=nodes':

```
numactl --physcpubind=18 --membind=1  ./snabb ...
```

## NUMA
Non-uniform memory access (NUMA) enabled systems have two or more CPU sockets (also called nodes), each with its own memory. While accessing memory across sockets is possible (and happening all the time), its slower than accessing local memory. PCI slots are hard wired to a specific node. It is imperative to pin Snabb to the same node )CPU and memory) as the NIC. Linux offers the command 'lstopo' to get an overall picture in text and graphical form:

```
lstopo --of pdf > lstopo.pdf
```

Example from a Lenovo RD650 (Intel(R) Xeon(R) CPU E5-2650 v3): 
![lstopo.png](lstopo.png)

### PCI Card and Snabb on same NUMA node
Memory shared between Snabb (by means of huge page mapping) and the NIC must share the same node. This is achieved via 'numactl', once the correct node is identified for a given NIC port/PCI address. 
To find the node for a given PCI address, use cpulistaffinity combined with numactl (TODO: is there a more direct way??):

```
$ lspci|grep 10-
81:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
81:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ 
$ cat /sys/class/pci_bus/0000:81/cpulistaffinity
14-27,42-55

$ numactl -H|grep cpus
node 0 cpus: 0 1 2 3 4 5 6 7 8 9 10 11 12 13 28 29 30 31 32 33 34 35 36 37 38 39 40 41
node 1 cpus: 14 15 16 17 18 19 20 21 22 23 24 25 26 27 42 43 44 45 46 47 48 49 50 51 52 53 54 55
```

Above example shows the 10GE ports be served by node 1.

Use 'numactl' and pin Snabb to a specific core (ideally excluded from the kernel scheduler) adn memory node:

```
numactl --physcpubind=18 --membind=1  ./snabb ...
```

Snabb applications like snabbnfv and snabbvmx share memory also with one or more QEMU processes running Virtual Machines via VhostUser. These QEMU processes must also be pinned to the same NUMA node with numactl with optional CPU pinning:

```
numactl --membind=1 /usr/local/bin/qemu-system-x86_64 ...
numactl --membind=1 --physcpubind=16-17 /usr/local/bin/qemu-system-x86_64 ...
```

Actual memory usage per node can be displayed with 'numastat':

```
$ sudo numastat -c snabb

Per-node process memory usage (in MBs)
PID              Node 0 Node 1 Total
---------------  ------ ------ -----
...
6049 (snabb)          0   3731  3731
6073 (snabb)          0   3732  3732
...
---------------  ------ ------ -----
Total                 5   7753  7758
$ sudo numastat -c qemu

Per-node process memory usage (in MBs)
PID              Node 0 Node 1 Total
---------------  ------ ------ -----
1899 (qemu-syste      0   7869  7869
1913 (qemu-syste      0   4171  4171
...
---------------  ------ ------ -----
Total                 4  12040 12044
```
Above example shows two snabb processes (6049 & 6073) using memory only from node 1 as desired based on the NIC ports served by node 1. Two QEMU based Virtual Machines also only use memory from node 1. 
If some memory is still used by another node for a given process, investigate its source and fix it. Possible candidates are SHM based filesystems use by Snabb in /var/run/snabb and SNMP SHM location if enabled.

### Watch for TLB shootdowns
TLB (Translation Lookaside Buffer) is a cache of the translations from virtual memory addresses to physical memory addresses. When a processor changes the virtual-to-physical mapping of an address, it needs to tell the other processors to invalidate that mapping in their caches. 
The actions of one processor causing the TLBs to be flushed on other processors is what is called a TLB shootdown.

Occasional packet loss at ingress has been observed while TLB shootdowns happened on the system. There are per cpu counters of TLB shootdowns available in the output of 'cat /proc/interrupts':

```
$ cat /proc/interrupts |grep TLB
 TLB:       2012       2141       1778       1942       2357       2076       2041       2129       2209       1960        486          0          0          0          0          0          0        145          0          0   TLB shootdowns
```
They must remain 0 for the CPU serving Snabb (pinned via taskset or numactl). One possible source of such TLB shootdowns can be the use of SHM between processes on different nodes or pinning Snabb to a list of CPUs instead a single one (TODO: needs confirmation. Have seen periodic TLB shootdowns before optimization based on this doc);

## Docker
CPU pinning via tasket and numactl work also within Docker Containers running in privileged mode. It is important to note that the Container can use all CPU cores, including the ones specifically excluded by the kernel option isolcpus:

```
$ taskset -cp $$
pid 9822's current affinity list: 0,4-8,12-15

$ docker run --name ubuntu -ti ubuntu:14.04.4
root@c819e0f106c4:/# taskset -cp $$
pid 1's current affinity list: 0-15
```




