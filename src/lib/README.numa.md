### CPU, memory, and PCI device affinity (lib.numa)

The NUMA module provides an easy way to manage CPU, NUMA, and PCI
device affinity in a high-level user-friendly way.  All Snabb data
planes should expose a `--cpu *n*` command-line argument that if given
by the user will arrange to call `bind_to_cpu(*n*)`.

Finally, before configuring the engine, all Snabb data planes should
call `check_affinity_for_pci_addresses` to verify that the PCI devices
that you are using are local to the current NUMA node, also warning if
for some reason the current process is not bound to a NUMA node.  See
[../doc/performance-tuning.md] for more notes on getting good
performance out of your Snabb program.

— Function **bind_to_cpu** *cpu* *skip_perf_checks*
Bind the current process to *cpu*, arranging for it to only ever be
run on that CPU.  Additionally, call **bind_to_numa_node** on the NUMA
node corresponding to *cpu*.

Unless the optional argument *skip_perf_checks* is true, also run some
basic checks to verify that the given core is suitable for processing
low-latency network traffic: that the CPU has the `performance` scaling
governor, that it has been reserved from the kernel scheduler, and so
on, printing out any problems to `stderr`.

— Function **bind_to_numa_node** *node*
Bind the current process to NUMA node *node*, arranging for it to only
ever allocate memory local to that NUMA node.  Additionally, migrate
existing mapped pages in the current process to that node.

— Function **prevent_preemption** *priority*
Mark the current process as being "real-time" with the given
*priority* (default 1).  The kernel will only ever interrupt a
real-time process if a higher-priorty real-time process is runnable.

— Function **unbind_cpu**
Undo any effects of **bind_to_cpu** or a user **taskset** wrapper,
allowing the current process to be scheduled on any CPU.

— Function **unbind_numa_node**
Undo any effects of **bind_to_numa_node** or a user **numactl**
wrapper, allowing the current process to allocate memory on any NUMA
node.

— Function **has_numa**
Return true if this computer has more than one NUMA node, or false
otherwise.

— Function **cpu_get_numa_node** *cpu*
Return the NUMA node to which CPU number *addr* is local, or nil if
this CPU is unknown.

— Function **pci_get_numa_node** *addr*
Return the NUMA node to which PCI address *addr* is local, or return
`nil` if this information is unavailable.

— Function **check_affinity_for_pci_addresses** *addrs* *require_affinity*
Given that the user wants to use PCI devices in *addrs*, which should
be an array of strings, check that the PCI devices are local to NUMA
node bound by **bind_to_numa_node**, if present, and in any case that
all *addrs* are on the same NUMA node.  If *require_affinity* is true
(not the default), then error if a problem is detected, otherwise just
print a warning to the console.

— Function **parse_cpuset** *cpus*
A helper function to parse a CPU set from a string.  A CPU set is either
the number of a CPU, a range of CPUs, or two or more CPU sets joined by
commas.  The result is a table whose keys are the CPUs and whose values
are true (a set).  For example, q`parse_cpuset("1-3,5")` will return a
table with keys 1, 2, 3, and 5 bound to `true`.

— Function **node_cpus** *node*
Return a set of CPUs belonging to NUMA node *node*, in the same format
as in **parse_cpuset**.

— Function **isolated_cpus**
Return a set of CPUs that have been "isolated" away from the kernel at
boot via the `isolcpus` kernel boot parameter.
