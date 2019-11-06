# Intel i210 / i350 / 82599 Ethernet Controller apps (apps.intel_mp.intel_mp)

The `intel_mp.Intel` app provides drivers for Intel i210/i250/82599 based
network cards. The driver exposes multiple receive and transmit queues that can
be attached to separate instances of the app on different processes.

The links are named `input` and `output`.

    DIAGRAM: Intel
                 +-------+
                 |       |
      input ---->* Intel *----> output
                 |       |
                 +-------+

## Caveats

If attaching multiple processes to a single NIC, performance appears
better with `engine.busywait = false`.

The `intel_mp.Intel` app can drive an Intel 82599 NIC at 14 million pps.

— Method **Intel:get_rxstats**

Returns a table with the following keys:

* `counter_id` - Counter id
* `packets` - Number of packets received
* `dropped` - Number of packets dropped
* `bytes` - Total bytes received

— Method **Intel:get_txstats**

Returns a table with the following keys:

* `counter_id` - Counter id
* `packets` - Number of packets sent
* `bytes` - Total bytes sent

## Configuration

— Key **pciaddr**

*Required*. The PCI address of the NIC as a string.

— Key **ndesc**

*Optional*. Number of DMA descriptors to use i.e. size of the DMA
transmit and receive queues. Must be a multiple of 128. Default is not
specified but assumed to be broadly applicable.

— Key **rxq**

*Optional*. The receive queue to attach to, numbered from 0. The default is 0.
When VMDq is enabled, this number is used to index a queue (0 or 1)
for the selected pool. Passing `false` will disable the receive queue.

— Key **txq**

*Optional*. The transmit queue to attach to, numbered from 0. The default is 0.
Passing `false` will disable the transmit queue.

— Key **vmdq**

*Optional*. A boolean parameter that specifies whether VMDq (Virtual Machine
Device Queues) is enabled. When VMDq is enabled, each instance of the driver
is associated with a *pool* that can be assigned a MAC address or VLAN tag.
Packets are delivered to pools that match the corresponding MACs or VLAN tags.
Each pool may be associated with several receive and transmit queues.

For a given NIC, all driver instances should have this parameter either
enabled or disabled uniformly. If this is enabled, *macaddr* must be
specified.

— Key **vmdq_queueing_mode**

*Optional*. Sets the queueing mode to use in VMDq mode. Has no effect when
VMDq is disabled. The available queueing modes for the 82599 are `"rss-64-2"`
(the default with 64 pools, 2 queues each) and `"rss-32-4"`
(32 pools, 4 queues each). The i350 provides only a single mode (8 pools, 2
queues each) and hence ignores this option.

— Key **poolnum**

*Optional*. The VMDq pool to associate with, numbered from 0. The default
is to select a pool number automatically. The maximum pool number depends
on the queueing mode.

— Key **macaddr**

*Optional*. The MAC address to use as a string. The default is a wild-card
(i.e., accept all packets).

— Key **vlan**
*Optional*. A twelve-bit integer (0-4095). If set, incoming packets from
other VLANs are dropped and outgoing packets are tagged with a VLAN header.

— Key **mirror**

*Optional*. A table. If set, this app will receive copies of all selected
packets on the physical port. The selection is configured by setting keys
of the *mirror* table. Either *mirror.pool* or *mirror.port* may be set.

If *mirror.pool* is `true` all pools defined on this physical port are
mirrored. If *mirror.pool* is an array of pool numbers then the specified
pools are mirrored.

If *mirror.port* is one of "in", "out" or "inout" all incoming and/or
outgoing packets on the port are mirrored respectively.  Note that this
does not include internal traffic which does not enter or exit through
the physical port.

— Key **rxcounter**

— Key **txcounter**

*Optional*. Four bit integers (0-15). If set, incoming/outgoing packets
will be counted in the selected statistics counter respectively. Multiple
apps can share a counter. To retrieve counter statistics use
`Intel:get_rxstats()` and `Intel:get_txstats()`.

— Key **rate_limit**

*Optional*. Number. Limits the maximum Mbit/s to transmit. Default is 0
which means no limit. Only applies to outgoing traffic.

— Key **priority**

*Optional*. Floating point number. Weight for the *round-robin* algorithm
used to arbitrate transmission when *rate_limit* is not set or adds up to
more than the line rate of the physical port. Default is 1.0 (scaled to
the geometric middle of the scale which goes from 1/128 to 128). The
absolute value is not relevant, instead only the ratio between competing
apps controls their respective bandwidths. Only applies to outgoing
traffic.

For example, if two apps without *rate_limit* set have the same
*priority*, both get the same output bandwidth.  If the priorities are
3.0/1.0, the output bandwidth is split 75%/25%.  Likewise, 1.0/0.333 or
1.5/0.5 yield the same result.

Note that even a low-priority app can use the whole line rate unless other
(higher priority) apps are using up the available bandwidth.

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

— Key **mac_loopback**

*Optional* Boolean indicating if the card should operate in
“Tx->Rx MAC Loopback mode” for diagnostics or testing purposes. If this is true
then `wait_for_link` is implicitly false. The default is false.


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

The Intel82599 supports both VMDq and RSS with 32/64 pools and 4/2 RSS queues for
each pool.
Intel1g i350 supports both VMDq and RSS with 8 pools 2 queues for each pool.
Intel1g i210 does not support VMDq.
