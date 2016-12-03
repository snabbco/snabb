# Intel i210 / i350 / 82599 driver (apps.intel_mp.intel_mp)

The `intel_mp.Intel` app provides drivers for Intel i210/i250/82599 based
network cards.  The driver exposes multiple rx and tx queues that can be
attached to different processes.

The links are named `input` and `output`.

## Caveats
If attaching multiple processes to a single NIC, performance appears
better with `egine.busywait = false`
intel_mp.Intel can drive an 82599 nic @14million pps

## Configuration
- Key **pciaddr**

*Required*. The PCI address of the NIC as a string.

- Key **ndesc**

*Optional*. Number of DMA descriptors to use i.e. size of the DMA
transmit and receive queues. Must be a multiple of 128. Default is not
specified but assumed to be broadly applicable.

- Key **rxq**
*Optional*. The receive queue to attach to, numbered from 0

- Key **txq**
*Optional*. The transmit queue to attach to, numbered from 0

- Key **rsskey**
*Optional*. The rsskey is a 32bit integer that seeds the hash used to
distribute packets across queues. If there are mutliple levels of RSS snabb
devices in the packet flow making this unique will help packet distribution.

- Key **wait_for_link**
*Optional*. Bool, false, should :new() block until there is a link light or not.

- Key **link_up_attempts**
*Optional* Number, 60, how many 2s attempts **wait_for_linkup** should make
before new() returns an app with a down link.

- Key **mtu**
*Optionla* Default: 9014 the maximum packet length sent of received, excluding
the trailing 4byte CRC.

- Key **run_stats**
*Optional* Bool, false, should this app export stats registers as counters. One
per physical nic. There is a small but detectable run time performance hit
incurred.

- Key **master_stats**
*Optional* Bool, false, elect an arbitrary  app, the master to
`run_stats == true`

### RSS hashing methods
RSS will distribute packets based on as many of the fields below as are present
in the packet
Source / Dest IP address
Source / Dest TCP ports
Source / Dest UDP ports

### Default RSS Queue
Packets that aren't ipv4/ipv6 will be delivered to receive queue 0

### Hardware limits
Each chipset supports a differing number of rx / tx queues
* Intel82599 supports 16 rx and 16 tx queues, 0-15
* Intel1g i350 supports 8 rx and 8 tx queues, 0-7
* Intel1g i210 supports 4 rx and 4 tx queues, 0-3
