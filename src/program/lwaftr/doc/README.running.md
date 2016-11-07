#  Running

## Finding out the PCI addresses of your NICs

Snabb lwAFTR is designed to run on **Intel 82599 10-Gigabit** NICs. Find the
address of NICs on your system with `lspci`:

```bash
$ lspci | grep 82599
01:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+
01:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+
02:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+
02:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+
03:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+
03:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+
81:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+
81:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+
82:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+
82:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+
```

Many tools accept the short form of the PCI addresses (ie, '01:00.0'), but some
require them to match the filenames in `/sys/bus/pci/devices/`, such as
`/sys/bus/pci/devices/0000:04:00.1`: in such cases, you must write `0000:01:00.0`,
with the appropriate prefix (`0000:`, in this example).

Note: Compile Snabb (see [README.build.md](README.build.md)) before attempting
the following.

## Running a load generator and the lwaftr

To run a load generator and an `lwaftr`, you will need four
interfaces. The following example assumes that `01:00.0` is cabled to
`01:00.1`, and that `02:00.0` is cabled to `02:00.1`. Change the
concrete PCI devices specified to match the current system; See [Section
1](Section 1. Finding out the PCI addresses of your NICs).

Note that unless the load generator and the lwaftr are running on the
same NUMA nodes that their NICs are connected to, performance will be
terrible.  See [README.benchmarking.md](README.benchmarking.md) and
[README.performance.md](README.performance.md) for more.

First, start the lwAFTR:

```
$ sudo ./snabb lwaftr run \
    --conf program/lwaftr/tests/data/icmp_on_fail.conf \
    --v4 0000:01:00.1 --v6 0000:02:00.1
```

Then run a load generator:

```bash
$ cd src
$ sudo ./snabb lwaftr loadtest  \
    program/lwaftr/tests/benchdata/ipv4-0550.pcap IPv4 IPv6 0000:01:00.0 \
    program/lwaftr/tests/benchdata/ipv6-0550.pcap IPv6 IPv4 0000:02:00.0
```

The load generator will push packets on the IPv4 and IPv6 interfaces,
ramping up from 0 Gbps to 10 Gbps (by default).  At each step it measures
the return traffic from the lwAFTR, and prints out all this information
to the console.  The load generator stops when the test is done.

## The packetblaster

Another way of generating load is via the `packetblaster lwaftr` command,
see [its documentation](../../packetblaster/lwaftr/README).
