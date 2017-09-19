# Intel i210 / i350 / 82599 Ethernet Controller apps (apps.intel_mp.intel_mp)

The `intel_mp.Intel` app provides drivers for Intel i210/i250/82599 based
network cards. The driver exposes multiple receive and transmit queues that can
be attached to separate instances of the app on different processes.

The links are named `input` and `output`.

## Caveats

If attaching multiple processes to a single NIC, performance appears
better with `engine.busywait = false`.

The `intel_mp.Intel` app can drive an Intel 82599 NIC at 14 million pps.

## Configuration

— Key **pciaddr**

*Required*. The PCI address of the NIC as a string.

— Key **ndesc**

*Optional*. Number of DMA descriptors to use i.e. size of the DMA
transmit and receive queues. Must be a multiple of 128. Default is not
specified but assumed to be broadly applicable.

— Key **rxq**

*Optional*. The receive queue to attach to, numbered from 0.

— Key **txq**

*Optional*. The transmit queue to attach to, numbered from 0.

— Key **rsskey**

*Optional*. The rsskey is a 32 bit integer that seeds the hash used to
distribute packets across queues. If there are multiple levels of RSS snabb
devices in the packet flow making this unique will help packet distribution.

— Key **wait_for_link**

*Optional*. Boolean that indicates if `new` should block until there is a link
light or not. The default is `false`.

— Key **linkup_wait**

*Optional* Number of seconds `new` waits for the device to come up. The default
is 120.

— Key **linkup_wait_recheck**

*Optional* If the `linkup_wait` option is true, the number of seconds
to sleep between checking the link state again.  The default is 0.1
seconds.

— Key **mtu**

*Optional* The maximum packet length sent or received, excluding the trailing
 4 byte CRC. The default is 9014.

— Key **master_stats**

*Optional* Boolean indicating whether to elect an arbitrary app (the master)
to collect device statistics. The default is true.

— Key **run_stats**

*Optional* Boolean indicating if this app instance should collect device
statistics. One per physical NIC (conflicts with `master_stats`). There is a
small but detectable run time performance hit incurred. The default is false.


### RSS hashing methods

RSS will distribute packets based on as many of the fields below as are present
in the packet:

* Source / Destination IP address
* Source / Destination TCP ports
* Source / Destination UDP ports

### Default RSS Queue

Packets that are not IPv4 or IPv6 will be delivered to receive queue 0.

### Hardware limits

Each chipset supports a differing number of receive / transmit queues:

* Intel82599 supports 16 receive and 16 transmit queues, 0-15
* Intel1g i350 supports 8 receive and 8 transmit queues, 0-7
* Intel1g i210 supports 4 receive and 4 transmit queues, 0-3
