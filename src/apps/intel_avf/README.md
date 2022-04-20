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

— Key **vlan**

*Optional*. VLAN id used for filtering packets. If specified, VLAN tags are
stripped for incoming packets and inserted for outgoing packets.

— Key **macs**

*Optional*. Additional unicast or multicast MACs to listen to.
The default is the empty array `{}`.

— Key **nqueues**

*Optional*. Number of RSS queues to configure. If specified you need to use
the `intel_avf.IO` app to attach for I/O for each respective queue.

— Key **ring_buffer_size**

*Optional*. Number of DMA descriptors to use i.e. size of the DMA
transmit and receive queues. Must be a multiple of 128. Default is not
specified but assumed to be broadly applicable.

## IO app

The `intel_avf.IO` app provides a driver for a single RSS queue of a
Virtual Function (see *nqueues*).

The links are names `input` and `output`.

    DIAGRAM: Intel_avf_IO
                 +-----------+
                 |           |
      input ---->*    IO     *----> output
                 |           |
                 +-----------+
### Configuration

— Key **pciaddr**

*Required*. The PCI address of the NIC as a string.

— Key **queue**

*Required*. The queue number of the respective RSS queue, starting from zero.

## Supported Hardware
Ethernet controller [0200]: Intel Corporation Ethernet Virtual Function 700 Series [8086:154c] (rev 02)

## Unsupported features
* Multiple vlans are unsupported, `vlan` can be used to strip/insert a single vlan ID.
* All of the advanced offload features are unsupported.
* 16 byte RX descriptors are unsupported.

## Setting up VFs under linux
echo 2 > /sys/bus/pci/devices/0000\:03\:00.1/sriov_numvfs
ip link set up dev enp3s0f1
ip link set enp3s0f1 vf 0 mac 02:00:00:00:00:01
ip link set enp3s0f1 vf 0 vlan 10

A more complete example can be found in apps/intel_avf/tests/setup.sh
