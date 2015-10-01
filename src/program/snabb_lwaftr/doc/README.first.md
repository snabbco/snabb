# Welcome to Snabb-lwaftr!

Here is how to get started with it.

This document assumes that `${SNABB_LW_DIR}` is the location where your checkout
of the **snabb-lwaftr** project.

# Current status

Snabb-lwaftr is alpha/prototype software. It can run 2 10-Gbit NICs at over 90%
of line speed, and it is believed to be [RFC 7596](https://tools.ietf.org/html/rfc7596) compliant.
It is ready for experimentation, but not recommended for production use yet.

# Section 1. Finding out the PCI addresses of your NICs

Snabb-lwaftr is designed to run on **Intel 82599 10-Gigabit** NICs. Find the
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

# Section 2. Compiling snabb

See [README.build.md](README.build.md).

# Section 3. Running a load generator and the lwaftr

Note: Compile Snabb (see [README.build.md](README.build.md)) before attempting
the following.

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
$ sudo ./src/snabb-lwaftr run \
    --bt tests/apps/lwaftr/data/binding.table \
    --conf tests/apps/lwaftr/data/icmp_on_fail.conf \
    --v4-pci 0000:01:00.1 --v6-pci 0000:02:00.1
```

Then run a load generator:

```bash
$ cd ${SNABB_LW_DIR} # The directory snabb-lwaftr is checked out into
$ sudo ./bin/snabb-lwaftr transient  \
    tests/apps/lwaftr/benchdata/ipv4-0550.pcap IPv4 0000:01:00.0 \
    tests/apps/lwaftr/benchdata/ipv6-0550.pcap IPv6 0000:02:00.0 \
```

The load generator will push packets on the IPv4 and IPv6 interfaces,
ramping up from 0 Gbps to 10 Gbps (by default) and then coming back
down.  It also measures the return traffic from the lwAFTR, and prints
out all this information to the console in CSV format.  The load
generator stops when the transient is done.

# Section 4. Troubleshooting

See [README.troubleshooting.md](README.troubleshooting.md).

# Section 5. Configuration

See [README.bindingtable.md](README.bindingtable.md) and [README.configuration.md](README.configuration.md).

# Section 6. RFC Compliance

See [README.rfccompliance.md](README.rfccompliance.md).

# Section 7. Benchmarking

See [README.benchmarking.md](README.benchmarking.md).

# Section 8. Performance

See [README.performance.md](README.performance.md).

# Section 9. Virtualization

See [README.virtualization.md](README.virtualization.md).
