Welcome to Snabb-lwaftr! Here is how to get started with it.

This document assumes that ${SNABB_LW_DIR} is the location where your checkout of the Snabb-lwaftr project.

Section 0. The status of this project

Snabb-lwaftr is alpha/prototype software. It can run 2 10-gbit NICs at over 90% of line speed, and it is believed to 
be RFC 7596 compliant. It is ready for experimentation, but not recommended for production use yet.

Section 1. Finding out the PCI addresses of your NICs

Snabb-lwaftr is designed to run on Intel 82599 10-Gigabit NICs. Find the address of NICs on your system with lspci:

$ lspci | grep 82599
01:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
01:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
02:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
02:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
03:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
03:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
81:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
81:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
82:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
82:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)

Many tools accept the short form of the PCI addresses (ie, '01:00.0'), but some require them to match
the filenames in /sys/bus/pci/devices/, such as /sys/bus/pci/devices/0000:04:00.1 : in such cases, you
must write '0000:01:00.0', with the appropriate prefix ('0000:', in this example).

Section 2. Compiling snabb

See README.build.md

Section 3. Running a load generator and the lwaftr

Note: compile Snabb (see README.build.md) before attempting the following.

To run two load generators and one lwaftr, you will need four interfaces. The following example assumes that 01:00.0 is cabled to 01:00.1, and that 02:00.0 is cabled to 02:00.1. Change the concrete pci devices specified to match the current system; see section 0.

$ cd ${SNABB_LW_DIR} # The directory snabb-lwaftr is checked out into
$ sudo ./bin/snabb-lwaftr-blaster --v4-pcap  tests/apps/lwaftr/benchdata/ipv4-0550.pcap --v6-pcap tests/apps/lwaftr/benchdata/ipv6-0550.pcap --v4-pci 01:00.0 --v6-pci 02:00.0

Now, run the lwaftr itself:
$ sudo ./bin/snabb-lwaftr --bt tests/apps/lwaftr/data/binding.table --conf tests/apps/lwaftr/data/icmp_on_fail.conf --v4-pci 01:00.1 --v6-pci 02:00.1

Section 4. Troubleshooting

See README.troubleshooting.md

Section 5. Configuration

See README.bindingtable.md and README.configuration.md.

Section 6. RFC Compliance

See README.rfccompliance.md

Section 7. Benchmarking

See README.benchmarking.md

Section 8. Performance 

See README.performance.md
