# Intel i210 / i350 / 82599 driver (apps.intel_mp.intel_mp)

The `intel_mp` app provides drivers for Intel i210/i250/82599 based
network cards. `intel_mp.Intel1g` for i210/i350 and `intel_mp.Intel82559`
The driver exposes multiple rx and tx queues that can be attached to different
processes.

The links are named `input` and `output`.

## Caveats
If attaching multiple processes to a single NIC, performance appears
better with `egine.busywait = false`
intel_mp.Intel82599 can drive a nic @14million pps

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
*Optional*. Bool, should :new() block until there is a link light or not.

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
* Intel82599 supports 16 rx and 16 tx queues
* Intel1g i210 supports 4 rx and 4 tx queues
* Intel1g i350 supports 8 rx and 8 tx queues
