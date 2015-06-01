# Compute Node Requirements

The Snabb NFV data plane has specific hardware and kernel setup
requirements for compute nodes. These requirements are based on the
standard recommendations from Intel for high performance data planes (see
[Intel DPDK](http://dpdk.org/doc/intel/dpdk-start-linux-1.7.0.pdf)
recommendations for more background.)

#### Hardware setup:

1. Network interfaces based on Intel 82599 Ethernet controller.
2. Network cards in suitable PCIe slots (typically PCIe 2.0/3.0 x8).
3. Network cards connected to CPUs (NUMA nodes) as desired. For example,
spread equally between nodes.

#### Reserve CPU cores for Snabb Switch

Snabb Switch traffic processes run on dedicated CPU cores. The peak
performance configuration is to reserve one core (and its hyperthread)
for each 10G network port.

For example, on the server:

* 2 x Xeon E5-2699v3 CPUs (36 cores / 72 threads)
* 8 x 10G ports (4 per CPU / NUMA node)

You could reserve these resources:

* CPU cores 0-3 (CPU0) and 18-21 (CPU1).
* Corresponding Hyperthreads 36-39 (CPU0) and 54-57 (CPU1). (If
  Hyperthreads are enabled in hardware.)

The details of how to reserve CPUs and assign them to Snabb Switch
processes are given below.

#### Kernel parameters setup

1. Disable the IOMMU: `intel_iommu=off`.
2. Reserve all memory for virtual machines as huge pages. Example for
24GB x 2MB pages: `hugepages=12288`.
3. Reserve CPU cores for Snabb Switch traffic processes by isolating them
from the Linux scheduler. Based on the example above:
`isolcpus=0-3,18-21,36-39,54-57`.

On Ubuntu 14.04 this could be accomplished with this line in
`/etc/default/grub`:

    GRUB_CMDLINE_LINUX_DEFAULT="hugepages=12288 intel_iommu=off isolcpus=0-3,18-21,36-39,54-57"
