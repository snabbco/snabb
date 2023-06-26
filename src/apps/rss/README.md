# RSS app (apps.rss.rss)

The `rss` app implements the basic functionality needed to provide
generic *receive side scaling* to other apps.  In essence, the `rss`
app takes packets from an arbitrary number `n` of input links and
distributes them to an arbitrary number `m` of output links

    DIAGRAM: rss
                  +--------+
    input_1  ---->*        *---->  output_1
            .     |  rss   |      .
            .     |        |      .
    input_n  ---->*        *---->  output_m
                  +--------+

The distribution algorithm has the property that all packets belonging
to the same *flow* are guaranteed to be mapped to the same output
link, where a flow is identified by the value of certain fields of the
packet header, depending on the type of packet.

For IPv4 and IPv6, the basic classifier is given by the 3-tuple
(`source address`, `destination address`, `protocol`), where
`protocol` is the value of the protocol field of the IPv4 header or
the value of the next-header field that identifies the "upper-layer
protocol" of the IPv6 header (which may be preceeded by any number of
extension headers).

If the protocol is either TCP (protocol #6), UDP (protocol #17) or
SCTP (protocol #132), the list of header fields is augmented by the
port numbers to yield the 5-tuple (`source address`, `destination
address`, `protocol`, `source port`, `destination port`).

The output link is determined by applying a hash function to the set
of header fields

```
out_link = ( hash(flow_fields) % m ) + 1
```

All other packets are not classified into flows and are always mapped
to the first output link.

The actual scaling property is achieved by running the receivers in
separate processes and use specialized inter-process links to connect
them to the `rss` app.

In addition to this basic functionality, the `rss` app also implements
the following set of extensions.

## Flow-director

The output links can be grouped into equivalence classes with respect
to matching conditions in terms of arbitrary pflang expressions as
provided by the `pf` module. Because the current implementation of the
`pf` module does not implement the `vlan` primitive, an auxiliary
construct is needed to match on the VLAN tag if required. Apart from a
regular BPF expression, the `rss` module also accepts a string of the
form

```
VLAN <vid1> <vid2> ... [ BPF <string> ]
```

where `<vidn>` are numbers representig VLAN IDs. This expression
matches a packet that carries any of the given VLAN tags. If the
expression also contains the keyword `BPF` followed by a regular BPF
expression, the packet must also match that expression to be mapped to
this equivalence class.

Matching packets are only distributed to the output links that belong
to the equivalence class.  By default, a single equivalence class
exists which matches all packets.  It is special in the sense that the
matching condition cannot be expressed in pflang.  This default class
is the only one that can receive non-IP packets.

Classes are specified in an explicit order when an instance of the
`rss` app is created.  The default class is created implicitly as the
last element in the list. Each packet is matched against the filter
expressions, starting with the first one.  If a match is found, the
packet is assigned to the corresponding equivalence class and
processing of the list stops.

The default class can be disabled by configuration. In that case,
packets not assigned to any class are dropped.

## Packet replication

The standard flow-director assigns a packet to at most one class.  Any
class can also be marked with the attribute `continue` to allow
matches to multiple classes.  When a packet is matched to such a
class, it is distributed to the set of ouput links associated with
that class but processing of the remaining filter expressions
continues.  If the packet matches a subsequent class, a copy is
created and distributed to the corresponding set of output links.
Processing stops when the packet matches a class that does not have
the `continue` attribute.

## Weighted links

By default, all output links in a class are treated the same.  In
other words, if the input consists of a sufficiently large sample of
random flows, all links will receive about the same share of them.  It
is possible to introduce a bias for certain links by assigning a
*weight* to them, given by a positive integer `w`.  If the number of
links is `m` and the weight of link `i` (`1 <= i <= m`) is `w_i`, the
share of traffic received by it is given by

```
share_i = w_i/(w_1 + w_2 + ... + w_m)
```

For example, if `m = 2` and `w_1 = 1, w_2 = 2`, link #1 will get 1/3
and link #2 will get 2/3 of the traffic.

## Packet meta-data

In order to compute the hash over the header fields, the `rss` app
must parse the packets to a certain extent.  Internally, the result of
this analysis is prepended as a block of data to the start of the
actual packet data.  Because this data can be useful to other apps
downstream of the `rss` app, it is exposed as part of the API.

The meta-data is structured as follows

```
   struct {
      uint16_t magic;
      uint16_t ethertype;
      uint16_t vlan;
      uint16_t total_length;
      uint8_t *filter_start;
      uint16_t filter_length;
      uint8_t *l3;
      uint8_t *l4;
      uint16_t filter_offset;
      uint16_t l3_offset;
      uint16_t l4_offset;
      uint8_t  proto;
      uint8_t  frag_offset;
      int16_t  length_delta;
   }
```

* `magic`

  This field contains the constant `0x5abb` to mark the start of a
  valid meta-data block.  The **get** API function asserts that this
  value is correct.

* `ethertype`

  This is the Ethertype contained in the Ethernet header of the
  packet.  If the frame is of type 802.1q, i.e. the Ethertype is
  `0x8100`, the `ethertype` field is set to the effective Ethertype
  following the 802.1q header.  Only one level of tagging is
  recognised, i.e. for double-tagged frames, `ethertype` will contain
  the value `0x8100`.

* `vlan`

  If the frame contains a 802.1q tag, `vlan` is set to the value of
  the `VID` field of the 802.1q header.  Otherwise it is set to 0.

* `total_length`

  If `ethertype` identifies the frame as either a IPv4 or IPv6 packet
  (i.e. the values `0x0800` and `0x86dd`, respectively),
  `total_length` is the size of the L3 payload of the Ethernet frame
  according to the L3 header, including the L3 header itself.  For
  IPv4, this is the value of the header's *Total Length* field.  For
  IPv6, it is the sum of the header's *Payload Length* field and the
  size of the basic header (40 bytes).

  For all other values of `ethertype`, `total_length` is set to the
  effective size of the packet (according to the `length` field of the
  `packet` data structure) minus the the size of the Ethernet header
  (14 bytes for untagged frames and 18 bytes for 802.1q tagged
  frames).

* `filter_start`

  This is a pointer into the packet that can be passed as first
  argument to a BPF matching function generated by
  **pf.compile_filter**.

  For untagged frames, this is a pointer to the proper Ethernet
  header.

  For 802.1q tagged frames, an offset of 4 bytes is added to skip the
  802.1q header. The reason for this is that the `pf` module does not
  implement the `vlan` primitive of the standard BPF syntax.  The
  additional 4-byte offset places the effective Ethertype (i.e. the
  same value as in the `ethertype` meta-data field) at the position of
  an untagged Ethernet frame.  Note that this makes the original MAC
  addresses unavailable to the filter.

* `filter_length`

  This value is the size of the chunk of data pointed to by
  `filter_start` and can be passed as second argument to a BPF
  matching function generated by **pf.compile_filter**.  It is equal
  to the size of the packet if the frame is untagged or 4 bytes less
  than that if the frame is 802.1q tagged.

* `l3`

  This is a pointer to the start of the L3 header in the packet.

* `l4`

  This is a pointer to the start of the L4 header in the packet. For
  IPv4 and IPv6, it points to the first byte following the L3 header.
  For all other packets, it is equal to `l3`.

* `filter_offset`, `l3_offset`, `l4_offset`

  These values are the offsets of `filter_start`, `l3`, and `l4`
  relative to the start of the packet.  They are used by the **copy**
  API call to re-calculate the pointers after the meta-data block has
  been relocated.

* `proto`

  For IPv4 and IPv6, the `proto` field contains the identifier of the
  *upper layer protocol* carried in the payload of the packet.  For
  all other packets, its value is undefined.

  For IPv4, the upper layer protocol is given by the value of the
  *Protocol* field of the header.  For IPv6, it is the value of the
  *Next Header* field of the last extension header in the packet's
  header chain.  The `rss` app recognizes the following protocol
  identifiers as extension headers according to the [IANA
  ipv6-parameters
  registry](http://www.iana.org/assignments/ipv6-parameters)

  * 0	IPv6 Hop-by-Hop Option
  * 43	Routing Header for IPv6
  * 44	Fragment Header for IPv6
  * 51	Authentication Header
  * 60	Destination Options for IPv6
  * 135	Mobility Header
  * 139	Host Identity Protocol
  * 140	Shim6 Protocol

  Note that the protocols 50 (Encapsulating Security Payload, ESP),
  253 and 254 (reserved for experimentation and testing) are treated
  as upper layer protocols, even though, technically, they are
  classified as extension headers.

* `frag_offset`

  For fragmented IPv4 and IPv6 packets, the `frag_offset` field
  contains the offset of the fragment in the original packet's payload
  in 8-byte units.  A value of zero indicates that the packet is
  either not fragmented at all or is the initial fragment.

  For non-IP packets, the value is undefined.

* `length_delta`

  This field contains the difference of the packet's effective length
  (as given by the `length` field of the packet data structure) and
  the size of the packet calculated from the IP header, i.e. the sum
  of `l3_offset` and `total_length`.  For a regular packet, this
  difference is zero.

  A negative value indicates that the packet has been truncated.  A
  typical scenario where this is expected to occur is a setup
  involving a port-mirror that truncates packets either due to
  explicit configuration or due to a hardware limitation.  The
  `length_delta` field can be used by a downstream app to determine
  whether it has received a complete packet.

  A positive value indicates that the packet contains additional data
  which is not part of the protocol data unit.  This is not expected
  to occur under normal circumstances.  However, it has been observed
  that some devices perform this kind of padding when port-mirroring
  is configured with packet truncation and the mirrored packet is
  smaller than the truncation limit.

  For non-IP packets, `length_delta` is always zero.

## IPv6 extension header elimination

The `pf` module does not implement the `protochain` primitive for
IPv6.  The only extension header it can deal with is the fragmentation
header (protocol 44).  As a consequence, packets containing arbitrary
extension headers can not be matched against filter expressions.

To overcome this limitation, the meta-data generator of the `rss` app
removes all extension headers from a packet by default, leaving only
the basic IPv6 header followed immediately by the upper layer
protocol.  The values of the *Payload Length* and *Next Header* fields
of the basic IPv6 header as well as the packet length are adjusted
accordingly.

## VLAN pseudo-tagging

Since the `rss` app can accept packets from multiple sources, the
information on which link the packet was received is not trivially
available to receiving apps unless the packets contain a unique
identifier of some sort, e.g. a particular VLAN tag.  If such an
identifier is not available, the `rss` app can be configured to attach
a pseudo VLAN tag to packets arriving on a particular input link.  It
is called "pseudo tagging" because the VLAN is only added to the
packet's meta-data, not the packet itself. As a consequence, a
receiving app only sees this kind of tag when it examines the
meta-data provided by the `rss` app.  Such a pseudo-tag also overrides
any native VLAN tag that a packet might have.

The pseudo-tagging is enabled by following a convention for the naming
of input links as described below.

If proper VLAN tagging is required, the `vlan.vlan.Tagger` app can be
pushed between the packet source and the input link.

## Configuration

The `rss` app accepts the following arguments.

— Key **default_class**

*Optional*. A boolean that specifies whether the default filter class
should be enabled.  The default is `true`.  The name of the default
class is *default*.

— Key **classes**

*Optional*. An ordered list of class specifications.  Each
specification must be a table with the following keys.

  * Key **name**

    *Required*. The name of the class.  It must be unique among all
    classes and it must match the Lua regular expression `%w+`.

  * Key **filter**

    *Required*. A string containing a pflang filter expression.

  * Key **continue**

    *Optional*. A boolean that specifies whether processing of classes
    should continue if a packet has matched the filter of this class.
    The default is `false`.

— Key **remove_extension_headers**

*Optional*. A boolean that specifies whether IPv6 extension headers
shoud be removed from packets.  The default is `true`.

The **classes** configuration option specifies the set of classes
known to an instance of the `rss` app.  The assignment of links to
classes is done implicitly by connecting other apps using the
convention `<class>_<instance>` for the name of the links, where
`<class>` is the name of the class to which the links should be
assigned exactly as specified by the **name** parameter of the class
definition. The `<instance>` specifier can be any string (adhering to
the naming convention for links) that distinguishes the links within a
class.

If the instance specifier is formatted as `<instance>_<weight>`, where
`<instance>` is restricted to the pattern `%w+` and `<weight>` must be
a number, the link's weight is set to the value `<weight>`.  The
default weight for a links is 1.

If the `rss` app detects an output link whose name does not match any
of the configured classes, it issues a warning message and ignores the
link.  Classes to which no output links are assigned are ignored.

The names of the input links are arbitrary unless the VLAN
pseudo-tagging feature should be used.  In that case, the link must be
named `vlan<vlan-id>`, where `<vlan-id>` must be a number between 1
and 4094 and will be placed in the `<vlan>` meta-data field of every
packet received on the link (irrespective of whether the packet has a
real VLAN ID or not).

## Meta-data API

The meta-data functionality is provided by the module
`apps.rss.metadata` and provides the following API. The metadata is
stored in the area of the packet buffer that is reserved as headroom
for prepending headers to the packet. Consequently, using any of the
functions that add or remove headers (`append`, `prepend`,
`shiftleft`, `shiftright` from `core.packet`) will invalidate the
metadata.

— Function **add** *packet*, *remove_extension_headers*, *vlan*

Analyzes *packet* and adds a meta-data block starting immediately
after the packet data.  If the boolean *remove_extension_headers* is
`true`, IPv6 extension headers are removed from the packet.  The
optional *vlan* overrides the value of the `vlan` meta-data field
extracted from the packet, irrespective of whether the packet actually
has a tag or not.

An error is raised if there is not enough room for the mata-data block
in the packet.

— Function **get** *packet*

Returns a pointer to the meta-data in *packet*.  An error is raised if
the meta-data block does not start with the magic number (`0x5abb`).

— Function **copy** *packet*

Creates a copy of *packet* including the meta-data block.  Returns a
pointer to the new packet.
