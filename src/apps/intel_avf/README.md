# Intel AVF (adaptive virtual function) app (apps.intel_avf.intel_avf)

The `intel_avf.Intel_avf` app provides drivers for the Virtual Functions exported
by recent generations of Intel network cards.

The links are named `input` and `output`.

    DIAGRAM: Intel_avf
                 +-----------+
                 |           |
      input ---->* Intel_avf *----> output
                 |           |
                 +-----------+

## Configuration

— Key **pciaddr**

*Required*. The PCI address of the NIC as a string.

— Key **ring_buffer_size**

*Optional*. Number of DMA descriptors to use i.e. size of the DMA
transmit and receive queues. Must be a multiple of 128. Default is not
specified but assumed to be broadly applicable.

## Supported Hardware
Ethernet controller [0200]: Intel Corporation Ethernet Virtual Function 700 Series [8086:154c] (rev 02)

## Unsupported features
* Multiple queues per VF. This driver supports a single queue. The spec allows for up to 4 queues.
* RSS with only 1 queue RSS doesn't make sense.
* Multiple vlans are unsupported, `ip link` can be used to map all traffic to a single vlan.
* Multiple MAC addresses are unsupported, `ip link` can be used to set the mac before snabb startup.
* All of the advanced offload features are unsupported.
* 16 byte RX descriptors are unsupported.

## Setting up VFs under linux
echo 2 > /sys/bus/pci/devices/0000\:03\:00.1/sriov_numvfs
ip link set up dev enp3s0f1
ip link set enp3s0f1 vf 0 mac 02:00:00:00:00:01
ip link set enp3s0f1 vf 0 vlan 10

A more complete example can be found in apps/intel_avf/tests/setup.sh
