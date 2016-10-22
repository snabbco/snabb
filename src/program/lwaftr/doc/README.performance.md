# Tuning the performance of the lwaftr

## Adjust CPU frequency governor

To avoid power-saving heuristics causing decreased throughput and higher
latency, set the CPU frequency governor to `performance`:

```bash
for CPUFREQ in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
   [ -f $CPUFREQ ] || continue;
   echo -n performance > $CPUFREQ;
done
```

You might need to also go into your BIOS and verify that you have not
enabled aggressive power-saving modes that could downclock your
processors.  A CPU in a power-saving mode typically takes some time to
return to peak performance, and this latency can cause packet loss.

## Avoid fragmentation

Fragment reassembly in particular is a costly operation.  Make sure that
MTUs are set such that fragmentation is rare.

## CPU affinity

The `snabb lwaftr run` and `snabb lwaftr loadtest` commands take a
`--cpu` argument, which will arrange for the Snabb process to run on a
particular CPU.  It will also arrange to make sure that all memory used
by that Snabb process is on the same NUMA node as that CPU, and it will
check that any PCI device used by that Snabb process has affinity to
that NUMA node, and issue a warning if anything is amiss.

Binding Snabb to a CPU and NUMA node can also be done using the `numactl
--membind` and `taskset -c` commands, but we recommend the `--cpu`
argument as it is easiest.

## NUMA

In a machine with multiple sockets, you usually have Non-Uniform Memory
Access, or NUMA.  On such a system, a PCI device or a range of memory
might be "closer" to one node than another.  The `--cpu` argument to
`snabb lwaftr run`, described above, will issue a warning if you use a
PCI device that is not local to the NUMA node that corresponds to the
chosen CPU.

To determine what PCI devices are local to what NUMA nodes, you need to
grovel around in `/sys`.  For example if you are going to be working
with NICs `0000:01:00.0`, `0000:01:00.1`, `0000:02:00.0`, and
`0000:02:00.1`, check:

```bash
$ for device in 0000:0{1,2}:00.{0,1}; do \
    echo $device; cat /sys/bus/pci/devices/$device/numa_node; \
  done
0000:01:00.0
0
0000:01:00.1
0
0000:02:00.0
0
0000:02:00.1
0
```

So all of these are on NUMA node 0.  Then you can check your CPUs:

```
$ numactl -H | grep cpus
node 0 cpus: 0 1 2 3 4 5
node 1 cpus: 6 7 8 9 10 11
```

So for these we should run our binaries under `--cpu CPU` to bind them
to CPUs in the NUMA node 0, and to arrange to use only memory that is
local to that CPU.

## Isolate CPUs

When running a Snabb dataplane, we don't want interference from the
Linux kernel.  In normal operation, a Snabb dataplane won't even make
any system calls at all.  You can prevent the Linux kernel from
pre-empting your Snabb application to schedule other processes on its
CPU by reserving CPUs via the `isolcpus` kernel boot setting.

To isolate CPUs, boot your Linux kernel with the `isolcpus` parameter.
Under NixOS, edit `/etc/nixos/configuration.nix` to add this parameter:

```
boot.kernelParams = [ "isolcpus=1-5,7-11" ];
```

The line above prevents the kernel to schedule processes in CPUs ranging
from 1 to 5 and 7 to 11. That leaves CPUs 0 and 6 for the Linux kernel.
By default, the kernel will arrange deliver interrupts to the first CPU
on a socket, so this `isolcpus` setting should also isolate the
dataplane from interrupt handling as well.

After adding the `isolcpus` flag run `nixos-rebuild switch` and then reboot 
your workstation to enable the changes.

## Ingress and egress filtering

Simply enabling ingress and/or egress filtering has a cost.  Enabling
all filters adds 4 apps to the Snabb graph, and there is a cost for
every additional Snabb app.  In our tests, while a normal run can do 10
Gbps over two interfaces in full duplex, enabling filters drops that to
8.2 Gbps before dropping packets.  However we have not found that the
performance depends much on the size of the filter, as the filter's
branches are well-biased.

## Interrupts

Normally Linux will handle hardware interrupts on the first core on a
socket.  In our case above, that would be cores 0 and 6.  That works
well with our `isolcpus` setting as well: interrupts like timers and so
on will only get delivered to the cores which Linux is managing already,
and won't interrupt the dataplanes.

However, some distributions (notably Ubuntu) enable `irqbalanced`, a
daemon whose job it is to configure the system to deliver interrupts to
all cores.  This can increase interrupt-handling throughput, but that's
not what we want in a Snabb scenario: we want low latency for the
dataplane, and handling interrupts on dataplane CPUs is undesirable.
When deploying on Ubuntu, be sure to disable irqbalanced.

## Hyperthreads

Hyperthreads are a way of maximizing resource utilization on a CPU core,
driven by the observation that a CPU is often waiting on memory or some
external event, and might as well be doing something else while it's
waiting.  In such a situation, it can be advantageous to run a second
thread on that CPU.  However for Snabb that's exactly what we don't
want.  We do not want another thread competing for compute and cache
resources on our CPU and increasing our latency.  For best results and
lowest latency, disable hyperthreading via the BIOS settings.

## Huge pages

By default on a Xeon machine, the virtual memory system manages its
allocations in 4096-byte "pages".  It has a "page table" which maps
virtual page addresses to physical memory addresses.  Frequently-used
parts of a page table are cached in the "translation lookaside buffer"
(TLB) for fast access.  A virtual memory mapping that describes 500 MB
of virtual memory would normally require 120000 entries for 4096-byte
pages.  However, a TLB only has a limited amount of space and can't hold
all those entries.  If it is missing an entry, that causes a "TLB miss",
causing an additional trip out to memory to fetch the page table entry,
slowing down memory access.

To mitigate this problem, it's possible for a Xeon machine to have some
"huge pages", which can be either 2 megabytes or 1 gigabyte in size.
The same 500MB address space would then require only 250 entries for 2MB
hugepages, or just 1 for 1GB hugepages.  That's a big win!  Also,
memory within a huge page is physically contiguous, which is required to
interact with some hardware devices, notably the Intel 82599 NICs.

However because hugepages are bigger and need to be physically
contiguous, it may be necessary to pre-allocate them at boot-time.  To
do that, add the `default_hugepagesz`, `hugepagesz`, and `hugepages`
parameters to your kernel boot.  In NixOS, we use the following, adding
on to the `isolcpus` setting mentioned above:

```
boot.kernelParams = [ "default_hugepagesz=2048K" "hugepagesz=2048K"
                      "hugepages=10000" "isolcpus=1-5,7-11" ];
```

## Ring buffer sizes

The way that Snabb interfaces with a NIC is that it will configure the
NIC to receive incoming packets into a /ring buffer/.  This ring buffer
is allocated by Snabb (incidentally, to a huge page; see above) and will
be filled by the NIC.  It has to be a power of 2 in size: so it can hold
space for 64 packets, 128 packets, 256 packets, and so on.  The default
size is 512 packets and the maximum is 65536.  The NIC will fill this
buffer with packets as it receives them: first to slot 0, then to slot
1, all the way up to slot 511 (for a ring buffer of the default size),
then back to slot 0, then slot 1, and so on.  Snabb will periodically
take some packets out of this read buffer (currently 128 at a time),
process them, then come back and take some more: wash, rinse, repeat.

The ring buffer size is configurable via the `--ring-buffer-size`
argument to `snabb lwaftr run`.  What is the right size?  Well, there
are a few trade-offs.  If the buffer is too big, it will take up a lot
of memory and start to have too much of a cache footprint.  The ring
buffer is mapped into Snabb's memory as well, and the NIC arranges for
the ring buffer elements that it writes to be directly placed in L3
cache.  This means that receiving packets can evict other entries in L3
cache.  If your ring buffer is too big, it can evict other data resident
in cache that you might want.

Another down-side of having a big buffer is latency.  The bigger your
buffer, the more the bloat.  Usually, Snabb applications always run
faster than the incoming packets, so the buffer size isn't an issue when
everything is going well; but in a traffic spike where packets come in
faster than Snabb can process them, the buffer can remain full the whole
time, which just adds latency for the packets that Snabb does manage to
process.

However, too small a buffer exposes the user to a higher risk of packet
loss due to jitter in the Snabb breath time.  A "breath" is one cycle of
processing a batch of packets, and as we mentioned it is currently up to
128 packets at a time.  This processing doesn't always take the same
amount of time: the contents of the packets can obviously be different,
causing different control flow and different data flow.  Even well-tuned
applications can exhibit jitter in their breath times due to differences
between what data is in cache (and which cache) and what data has to be
fetched from memory.  Infrequent events like reloading the binding table
or dumping configuration can also cause one breath to take longer than
another.  Poorly-tuned applications might have other sources of latency
such as garbage collection, though this is not usually the case in the
lwAFTR.

So, a bigger ring buffer insulates packet processing from breath jitter.
You want your ring buffer to be big enough to not drop packets due to
jitter during normal operation, but not bigger than that.  In our
testing we usually use the default ring buffer size.  In your operations
you might want to increase this up to 2048 entries.  We have not found
that bigger ring buffer sizes are beneficial, but it depends very much
on the environment.
