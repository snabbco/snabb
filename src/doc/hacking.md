Several environment variables can be set for snabbswitch code:

* SNABB_VFIO_DRIVER
  Default value "/sys/bus/pci/drivers/vfio-pci"

* SNABB_VFIO_IOMMU_GROUPS
  Default value "/sys/kernel/iommu_groups"

* SNABB_PCI_DEVICE
  Default value "/sys/bus/pci/devices"

* SNABB_HUGEPAGES
  Default value "/proc/sys/vm/nr_hugepages"

* SNABB_MEMINFO
  Default value "/proc/meminfo"

* SNABB_VHOST_USER_SOCKET_FILE
  No default value

* SNABB_TEST_PCI_ID
  No default value

You can run tests defining some of the variables:

    cd src; sudo SNABB_TEST_PCI_ID="0000:01:00.0" \
      SNABB_VHOST_USER_SOCKET_FILE="vhost_user_test.sock" make test;

if a test can't find resource needed it will usually skip and return code 43
(TEST_SKIPPED_CODE).

Also separate commands can utilize environment virables changes:

    sudo SNABB_HUGEPAGES=/proc/sys/vm/nr_hugepages snabbswitch -l designs.basic.basic

FIXME: add some sane examples and explanatory notes to variables.
