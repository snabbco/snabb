LWAFTR=../snabb

IPV4_PCAP:=../snabb/tests/apps/lwaftr/benchdata/ipv4-0550.pcap
IPV6_PCAP:=../snabb/tests/apps/lwaftr/benchdata/ipv6-0550.pcap
LWAFTR_CONF=../snabb/tests/apps/lwaftr/data/icmp_on_fail.conf

LWAFTR_IPV4_PCIADDR=0000:81:00.1
LWAFTR_IPV6_PCIADDR=0000:82:00.1

TRANSIENT_IPV4_PCIADDR=0000:81:00.0
TRANSIENT_IPV6_PCIADDR=0000:82:00.0

TRANSIENT_SELF_TEST_NIC1_PCIADDR=0000:81:00.0
TRANSIENT_SELF_TEST_NIC2_PCIADDR=0000:81:00.1

# These CPUs *must* correspond to the NUMA nodes of the corresponding
# PCI cards or performance will be terrible.  To check:
#  grep NUMA /proc/cpuinfo
#  cat /sys/bus/pci/devices/0000:81:00.0/numa_node
LWAFTR_CPU=6
TRANSIENT_CPU=7

SHELL=/bin/bash

transient-self-test.csv: $(LWAFTR)
	taskset -c $(TRANSIENT_CPU) ./snabb lwaftr transient -s 0.25e9 -D 2 $(IPV4_PCAP) NIC1 $(TRANSIENT_SELF_TEST_NIC1_PCIADDR) $(IPV4_PCAP) NIC2 $(TRANSIENT_SELF_TEST_NIC2_PCIADDR) > $@

lwaftr-%.csv:: $(LWAFTR)
	( set -m; set -o pipefail; \
	  taskset -c 6 ./snabb lwaftr run -D 170 --conf $(LWAFTR_CONF) --v4 $(LWAFTR_IPV4_PCIADDR) --v6 $(LWAFTR_IPV6_PCIADDR) & \
	  taskset -c 7 ./snabb lwaftr transient -s 0.25e9 -D 2 $(IPV4_PCAP) IPv4 $(TRANSIENT_IPV4_PCIADDR) $(IPV6_PCAP) IPv6 $(TRANSIENT_IPV6_PCIADDR) | tee $@.tmp && \
	  mv $@.tmp $@ && \
	  wait )
