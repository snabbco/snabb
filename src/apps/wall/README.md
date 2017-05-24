SnabbWall Apps
==============

L7Spy (apps.wall.l7spy)
-----------------------

    DIAGRAM: L7Spy
             +-----------+
      north  |           |
        ---->*   L7Spy   *--->
        <----*           *<---
             |           |  south
             +-----------+

The `L7Spy` app is a Snabb app that scans packets passing through it using
an instance of the `Scanner` class. The scanner instance may be shared among
several `L7Spy` instances or with a `L7Fw` app for filtering.

— Method **L7Spy:new** *config*

Construct a new `L7Spy` app instance based on a given configuration table.
The table may contain the following key:

* `scanner` (optional): Either a string identifying the kind of scanner to
  construct (currently only `"ndpi"` is accepted) or an existing scanner
  instance.


Filter (apps.wall.filter)
-------------------------

    DIAGRAM: L7Fw
             +-----------+
      input  |           | output
        ---->*   L7Fw    *--->
             |           *--->
             |           | reject
             +-----------+

The `L7Fw` app implements a stateful firewall by querying the scanner
state collected by a `L7Spy` app. It then filters packets based on a
given set of rules.

— Method **L7Fw:new** *config*

Construct a new `L7Fw` app instance based on a given configuration table.
The table may contain the following keys:

* `scanner`: A `Scanner` instance shared with an `L7Spy` instance. The metadata
  in this scanner is used for packet filtering.
* `rules`: A table mapping protocol names (as strings) to firewall actions.
  The accepted actions are `"accept"`, `"reject"`, `"drop"`, or a pfmatch
  expression. The pfmatch expression may use the variable `flow_count`
  (as an arithmetic expression) to refer to the number of packets in a
  given protocol flow, and may call the `accept`, `reject`, or `drop` methods.
* `local_ipv4` (optional): An IPv4 address that identifies the host running
  the firewall. This is used as the source address in ICMPv4 or TCP reject
  responses.
* `local_ipv6` (optional): An IPv6 address that identifies the host running
  the firewall. This is used as the source address in ICMPv6 or TCP reject
  responses.
* `local_macaddr` (optional): A MAC address that identifies the host running
  the firewall. This is used for the source address in ethernet frames for
  reject responses.
* `logging` (optional): A log level parameter that can be set to "on" or
  "off". When set to "on", it will report dropped/rejected packets to the
  system log.


Scanner (apps.wall.scanner)
---------------------------

`Scanner` objects are responsible for:

- Identifying traffic flows.
- Analyzing the contents of packet to determine which application they belong
  to.
- Keeping enough state to be able to enumerate the identified traffic flows,
  and identify the application they belong to.

The class is not meant to be instantiated directly, but to be used as the basis
for concrete implementations (e.g. `NdpiScanner`). It provides one function
that subclasses can use:

- Method **Scanner:extract_packet_info** *packet*

Extracts fields from the headers of an IPv4 or IPv6 *packet*. The returned
values are:

1. A *key* object (more on this below) which uniquely identifies a traffic
   flow.
2. The *offset* to the packet payload content.
3. The *source_address* of the packet, as an array of bytes.
4. The *source_port*, for UDP and TCP packets.
5. The *destination_address* of the packet, as an array of bytes.
6. The *destination_port*, for UDP and TCP packets.

Key objects contain some of the returned information in a compact FFI
representation, and can be used as an aid to uniquely identify a flow of
packets. The provide the following attributes:

- `:eth_type()`: Method which returns the type of the Ethernet frame payload,
  either `ETH_TYPE_IPv4` or `ETH_TYPE_IPv6`.
- `:hash()`: Method which returns an integer calculated by hashing all the
  other values in the key object.
- `.vlan_id`: VLAN identifier. Zero for no VLAN tags.
- `.ip_proto`: The IP protocol.
- `.lo_addr` and `.hi_addr`: IP addresses (either v4 or v6).
- `.lo_port` and `.hi_port`: For TCP and UDP, the ports as big-endian (network)
  integers.

This method can be very useful to implement scanners using backends which do
not implement their own flow classification.


### Subclassing

All the `Scanner` implementations conform to the `Scanner` base API.

— Method **Scanner:scan_packet** *packet*, *time*

Scans a *packet*.

The *time* parameter is used to know at which time (in seconds from the Epoch)
*packet* has been received for processing. A suitable value can be obtained
using `engine.now()`.

— Method **Scanner:get_flow** *packet*

Obtains the traffic flow for a given *packet*. If the packet is determined to
not match any of the detected flows, `nil` is returned. The returned flow
object has at least the following fields:

* `protocol`: The L7 protocol for the flow. A user-visible string can be
  obtained by passing this value to `Scanner:protocol_name()`.
* `packets`: Number of packets scanned which belong to the traffic flow.
* `last_seen`: Last time (in seconds from the Epoch) at which a packet
  belonging to the flow has been scanned.

— Method **Scanner:flows**

Returns an iterator over all the traffic flows detected by the scanner. The
returned value is suitable to be used in a `for`-loop:

```lua
for flow in my_scanner:flows() do
   -- Do something with "flow".
end
```

— Method **Scanner:protocol_name** *protocol*

Given a *protocol* identifier, returns a user-friendly name as a string.
Typically the *protocol* is obtained flow objects returned by
`Scanner:get_flow()`.


### NdpiScanner (apps.wall.scanner.ndpi)

`NdpiScanner` uses the
[nDPI](http://www.ntop.org/products/deep-packet-inspection/ndpi/) library (via
the [ljndpi](https://github.com/aperezdc/ljndpi) FFI binding) to scan packets
and determine L7 traffic flows. The nDPI library (`libndpi.so`) must be
available in the host system. Versions 1.7 and 1.8 are supported.

— Method **NdpiScanner:new** *ticks_per_second*

Creates a new scanner, with a *ticks_per_second* resolution.


Utilities
---------

The `apps.wall.util` module contains miscellaneous utilities.

— Function **util.ipv4_addr_cmp** *a*, *b*

Compares two IPv4 addresses *a* and *b*. The returned value follows the same
convention as for `C.memcmp()`: zero if both addresses are equal, or an
integer value with the same sign as the sign of the difference between
the first pair of bytes that differ in *a* and *b*.

— Function **util.ipv6_addr_cmp** *a*, *b*

Compares two IPv6 addresses *a* and *b*. The returned value follows the same
convention as for `C.memcmp()`: zero if both addresses are equal, or an
integer value with the same sign as the sign of the difference between
the first pair of bytes that differ in *a* and *b*.

### SouthAndNorth (apps.wall.util)

The `SouthAndNorth` application is not to mean to be used directly, but rather
as a building block for more complex applications which need two duplex ports
(`south` and `north`) which forward packets between them, optionally doing
some intermediate processing.

Packets arriving to the `north` port are passed to the
`:on_southbound_packet()` method —which can be overriden in a subclass—, and
forwarded to the `south` port. Conversely, packets arriving to the `south`
port are passed to `:on_northbound_packet()` method, and finally forwarded to
the `north` port.

    DIAGRAM: SouthAndNorth
             +---------------+
      north  |               |
        ---->* SouthAndNorth *--->
        <----*               *<---
             |               |  south
             +---------------+

The value returnbyed `:on_southbound_packet()` and `:on_northbound_packet()`
determines what will be done to the packet being processed:

* Returning `false` discards the packet: the packet will *not* be forwarded,
  and `packet.free()` will be called on it.
* Returning a different packet replaces the packet: the packet originally
  being processed is discarded, `packet.free()` called on it, and the returned
  packet is forwarded.
* Returning the same packet being handled will forward it. Retuning `nil`
  achieves the same effect.

#### Example

The following snippet defines an application derived from `SouthAndNorth`
which silently discards packets bigger than a certain size, and keeps a
count of how many packets have been discarded and forwarded:

```lua

-- Setting SouthAndNorth as metatable "inherits" from it.
DiscardBigPackets = setmetatable({},
   require("apps.wall.util").SouthAndNorth)

function DiscardBigPackets:new (max_length)
   return setmetatable({
      max_packet_length = max_length,
      discarded_packets = 0,
      forwarded_packets = 0,
   }, self)
end

function DiscardBigPackets:on_northbound_packet (pkt)
   if pkt.length > self.max_packet_length then
      self.discarded_packets = self.discarded_packets + 1
      return false
   end
   self.forwarded_packets = self.forwarded_packets + 1
end

-- Apply the same logic for packets in the other direction.
DiscardBigPackets.on_southbound_packet =
   DiscardBigPackets.on_northbound_packet
```
