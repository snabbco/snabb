Several environment variables can be set for snabbswitch code:

* SNABB_VFIO_DRIVER
  Default value "/sys/bus/pci/drivers/vfio-pci"

* SNABB_VFIO_IOMMU_GROUPS
  Default value "/sys/kernel/iommu_groups"

* SNABB_PCI_DEVICE
  Default value "/sys/bus/pci/devices"

* SNABB_TEST_PCI_ID
  Default value "0000:01:00.0"

* SNABB_HUGEPAGES
  Default value "/proc/sys/vm/nr_hugepages"

* SNABB_MEMINFO
  Default value "/proc/meminfo"

You can run tests defining some of the variables:

    cd src; sudo SNABB_MEMINFO=/proc/meminfo make test;

if a test can't find resource needed it will usually skip and return code 43
(TEST_SKIPPED_CODE).

Also separate commands can utilize environment virables changes:

    sudo SNABB_HUGEPAGES=/proc/sys/vm/nr_hugepages snabbswitch -l designs.basic.basic

FIXME: add some sane examples and explanatory notes to variables.
