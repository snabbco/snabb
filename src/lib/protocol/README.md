### Protocol Header (lib.protocol.header)

The `lib.protocol.header` module contains the base class from which the
supported protocol classes are derived. It defines generic methods on all
protocol subclasses.

— Method **header:new_from_mem** *memory*, *length*

Creates and returns a header object by "overlaying" the respective header
structure over *length* bytes of *memory*. Returns `nil` if *length* is
too small to contain the header.

— Method **header:header**

Returns the raw header as a *cdata* object.

— Method **header:sizeof**

Returns the byte size of header.

— Method **header:eq** *header*

Generic equality predicate. Returns `true` if *header* is equal to self
and `false` otherwise.

— Method **header:copy** *destination*, *relocate*

Copies the header to *destination*. The caller must ensure that there is
enough space at *destination*. If *relocate* is a true value,
*destination* is promoted to be the active storage for the header.

— Method **header:clone**

Returns a copy of the header object.

— Method **header:upper_layer**

Returns the protocol class that can handle the "upper layer protocol" or
`nil` if the protocol is not supported or the protocol has no upper
layer.

For instance, on an Ethernet header object this method might return a
IPv4 or IPv6 header class.

### Ethernet (lib.protocol.ethernet)

The `lib.protocol.ethernet` module contains a class for representing
*Ethernet headers*. The `ethernet` protocol class supports three upper
layer protocols: `lib.protocol.ipv4`, `lib.protocol.ipv6`,
and `lib.protocol.dot1q`.

— Method **ethernet:new** *config*

Returns a new Ethernet header for *config*. *Config* must a be a table
which may contain the following keys:

* `dst` - Destination MAC (binary representation). Default is
  `00:00:00:00:00:00`.
* `src` - Source MAC (binary representation). Default is
  `00:00:00:00:00:00`.
* `type` - Either `0x0800` or `0x86dd` for IPv4/6 individually. Default
  is `0x0`.

— Method **ethernet:src** *mac*

— Method **ethernet:dst** *mac*

— Method **ethernet:type** *type*

Combined accessor and setter methods. These methods set the values of the
source, destination and type fields of an Ethernet header. If no argument
is given the current value is returned.

Example:

```
local eth = ethernet:new({src = ethernet:pton("00:00:00:00:00:00"),
                          dst = ethernet:pton("00:00:00:00:00:00"),
                          type = 0x86dd})
eth:dst(ethernet:pton("54:52:00:01:00:00"))
ethernet:ntop(eth:dst()) => "54:52:00:01:00:00"
```

— Method **ethernet:src_eq** *mac*

— Method **ethernet:dst_eq** *mac*

Predicate methods to test if *mac* is equal to the source or destination
addresses individually.

— Method **ethernet:swap**

Swaps the values of the source and destination fields.

— Function **ethernet:pton** *string*

Returns the binary representation of MAC address denoted by *string*.

— Function **ethernet:ntop** *mac*

Returns the string representation of *mac* address.

— Function **ethernet:is_mcast** *mac*

Returns a true value if *mac* address denotes a [Multicast address](https://en.wikipedia.org/wiki/Multicast_address#Ethernet).

— Function **ethernet:is_bcast** *mac*

Returns a true value if *mac* address denotes a [Broadcast address](https://en.wikipedia.org/wiki/Broadcast_address#Ethernet).

— Function **ethernet:ipv6_mcast** *ip*

Returns the MAC address for IPv6 multicast *ip* as defined by RFC2464,
section 7.

### IEEE 802.1Q VLAN (lib.protocol.dot1q)

The `lib.protocol.dot1q` module contains a class for representing
[IEEE 802.1Q](https://en.wikipedia.org/wiki/IEEE_802.1Q) VLAN headers.
The `dot1q` protocol class supports two upper layer protocols:
`lib.protocol.ipv4` and `lib.protocol.ipv6`.

— Method **dot1q:new** *config*

Returns a new VLAN header for *config*. *Config* must a be a table
which may contain the following keys:

* `id` - VLAN id (PCP/DEI/VID) encoded in host byte order. Default is 0.
* `type` - Either `0x0800` or `0x86dd` for IPv4/6 individually. Default
  is `0x0`.

— Method **dot1q:id** *mac*

— Method **dot1q:type** *type*

Combined accessor and setter methods. These methods set the values of the
id and type fields of the VLAN header. If no argument
is given the current value is returned.

— Constant **dot1q.TPID**

The value `0x8100`. Used as the type in `lib.protocol.ethernet` to
indicate that a IEEE 802.1Q VLAN header follows.


### IPv4 (lib.protocol.ipv4)

The `lib.protocol.ipv4` module contains a class for representing
*IPv4 headers*. The `ipv4` protocol class supports four upper
layer protocols: `lib.protocol.tcp`, `lib.protocol.udp`,
`lib.protocol.gre` and `lib.protocol.icmp.header`.

— Method **ipv4:new** *config*

Returns a new IPv4 header for *config*. *Config* must a be a table
which may contain the following keys:

* `dst` - Destination IPv4 address (binary representation). Default is
  `0.0.0.0`.
* `src` - Source IPv4 address (binary representation). Default is
  `0.0.0.0`.
* `protocol` - The upper layer protocol, can be 6 (TCP), 17 (UDP), 47
  (GRE) or 58 (ICMP). Default is 255.
* `dscp` - "Differentiated Services Code Point" field (6 bit unsigned
  integer). Default is 0.
* `ecn` - "Explicit Congestion Notification" field (2 bit unsigned
  integer). Default is 0.
* `id` - "Identification" field (16 bit unsigned integer). Default is 0.
* `flags` - "Don't Fragment (DF)" and "More Fragments (MF)" fields (3 bit
  unsigned integer). Default is 0.
* `frag_off` - "Fragment Offset" field (13 bit unsigned integer). Default
  is 0.
* `ttl` - "Time To Live" field (8 bit unsigned integer). Default is 0.

— Method **ipv4:dst** *ip*

— Method **ipv4:src** *ip*

— Method **ipv4:protocol** *protocol*

— Method **ipv4:dscp** *dscp*

— Method **ipv4:ecn** *ecn*

— Method **ipv4:id** *id*

— Method **ipv4:flags** *flags*

— Method **ipv4:frag_off** *frag_off*

— Method **ipv4:ttl** *ttl*

Combined accessor and setter methods. These methods set the values of the
instance fields (see `new`) of an IPv4 header. If no argument is given
the current value is returned.

— Method **ipv4:version** *version*

Combined accessor and setter method for the "Version" field (4 bit
unsigned integer). Defaults to 4 (set automatically by `new`).
Sets the "Version" field to *version*. If no argument is given the
current value is returned.

— Method **ipv4:ihl** *ihl*

Combined accessor and setter method for the "Internet Header Length"
field (4 bit unsigned integer). Set automatically by `new`. Sets the
"Internet Header Length" field to *ihl*. If no argument is given the
current value is returned.

— Method **ipv4:total_length** *length*

Combined accessor and setter method for the "Total Length" field (16 bit
unsigned integer). Defaults to header length (set automatically by `new`).
Sets the "Total Length" field to *length*. If no argument is given the
current value is returned.

— Method **ipv4:checksum**

Computes and sets the IPv4 header checksum. Its called automatically by
`new` but must be called after the header is changed.

— Method **ipv4:dst_eq** *ip*

— Method **ipv4:src_eq** *ip*

Predicate methods to test if *ip* is equal to the source or destination
addresses individually.

— Function **ipv4:pton** *string*

Returns the binary representation of IPv4 address denoted by *string*.

— Function **ipv4:ntop** *ip*

Returns the string representation of *ip* address.

— Function **ipv4:pton_cidr** *string*

Returns the binary representation of the IPv4 address prefix and prefix length
encoded denoted by *string* of the form `<ipv4address>/<length>`.
See [CIDR notation](https://en.wikipedia.org/wiki/Classless_Inter-Domain_Routing).


### IPv6 (lib.protocol.ipv6)

The `lib.protocol.ipv6` module contains a class for representing
*IPv6 headers*. The `ipv6` protocol class supports four upper
layer protocols: `lib.protocol.tcp`, `lib.protocol.udp`,
`lib.protocol.gre` and `lib.protocol.icmp.header`.

— Method **ipv6:new** *config*

Returns a new IPv6 header for *config*. *Config* must a be a table
which may contain the following keys:

* `dst` - Destination IPv6 address (binary representation). Default is
  `0::0`.
* `src` - Source IPv6 address (binary representation). Default is
  `0::0`.
* `traffic_class` - "Traffic Class" field (8 bit unsigned
   integer). Default is 0.
* `flow_label` - "Flow Label" field (20 bit unsigned
   integer). Default is 0.
* `next_header` - "Next Header" field (8 bit unsigned
   integer). Default is 0.
* `hop_limit` - "Hop Limit" field  (8 bit unsigned
   integer). Default is 0.

— Method **ipv6:dst** *ip*

— Method **ipv6:src** *ip*

— Method **ipv6:traffic_class** *traffic_class*

— Method **ipv6:flow_label** *flow_label*

— Method **ipv6:next_header** *next_header*

— Method **ipv6:hop_limit** *hop_limit*

Combined accessor and setter methods. These methods set the values of the
instance fields (see `new`) of an IPv6 header. If no argument is given
the current value is returned.

— Method **ipv6:version** *version*

Combined accessor and setter method for the version field (4 bit unsigned
integer). Defaults to 6 (set automatically by `new`). Sets the "Version"
field to *version*. If no argument is given the current value is returned.

— Method **ipv6:dscp** *dscp*

Combined accessor and setter method for the "Differentiated Services Code
Point" field (6 bit unsigned integer). Default is 0. This is a sub-field
of the "Traffic Class" field. Sets the "Differentiated Services Code
Point" field to *dscp*. If no argument is given the current value is
returned.

— Method **ipv6:ecn** *ecn*

Combined accessor and setter method for the "Explicit Congestion
Notification" (2 bit unsigned integer). Default is 0. This is a sub-field
of the "Traffic Class" field. Sets the "Explicit Congestion Notification"
field to *ecn*. If no argument is given the current value is returned.

— Method **ipv6:payload_length** *length*

Combined accessor and setter method for the "Payload Length" field (16
bit unsigned integer). Default is 0. Sets the "Payload Length" field to
*length*. If no argument is given the current value is returned.

— Method **ipv6:dst_eq** *ip*

— Method **ipv6:src_eq** *ip*

Predicate methods to test if *ip* is equal to the source or destination
addresses individually.

— Function **ipv6:pton** *string*

Returns the binary representation of IPv6 address denoted by *string*.

— Function **ipv6:ntop** *ip*

Returns the string representation of *ip* address.

— Function **ipv6:pton_cidr** *string*

Returns the binary representation of the IPv6 address prefix and prefix length
encoded denoted by *string* of the form `<ipv6address>/<length>`.
See [CIDR notation](https://en.wikipedia.org/wiki/Classless_Inter-Domain_Routing).

— Function **ipv6:solicited_node_mcast** *ip*

Returns the solicited-node multicast address from the given unicast
*ip*.


### TCP (lib.protocol.tcp)

The `lib.protocol.tcp` module contains a class for representing *TCP
headers*.

— Method **tcp:new** *config*

Returns a new TCP header for *config*. *Config* must a be a table
which may contain the following keys:

* `src_port` - "Source Port Number" field (16 bit unsigned
  integer). Default is 0.
* `dst_port` - "Destination Port Number" field (16 bit unsigned
  integer). Default is 0.
* `seq_num` - "Sequence Number" field (32 bit unsigned integer). Default
  is 0.
* `ack_num` - "Acknowledgement Number" field (32 bit unsigned
  integer). Default is 0.
* `window_size` - "Window Size" field (16 bit unsigned integer). Default
  is 0.
* `offset` - "Data Offset" field (4 bit unsigned integer). Default is 0.
* `ns` - "NS" flag (1 bit). Default is 0.
* `cwr` - "CWR" flag (1 bit). Default is 0.
* `ece` - "ECE" flag (1 bit). Default is 0.
* `urg` - "URG" flag (1 bit). Default is 0.
* `ack` - "ACK" flag (1 bit). Default is 0.
* `psh` - "PSH" flag (1 bit). Default is 0.
* `rst` - "RST" flag (1 bit). Default is 0.
* `syn` - "SYN" flag (1 bit). Default is 0.
* `fin` - "FIN" flag (1 bit). Default is 0.

— Method **tcp:src_port** *port*

— Method **tcp:dst_port** *port*

— Method **tcp:seq_num** *seq_num*

— Method **tcp:ack_num** *ack_num*

— Method **tcp:window_size** *window_size*

— Method **tcp:offset** *offset*

— Method **tcp:ns** *ns*

— Method **tcp:cwr** *cwr*

— Method **tcp:ece** *ece*

— Method **tcp:urg** *urg*

— Method **tcp:ack** *ack*

— Method **tcp:psh** *psh*

— Method **tcp:rst** *rst*

— Method **tcp:syn** *syn*

— Method **tcp:fin** *fin*

Combined accessor and setter methods. These methods set the values of the
instance fields (see `new`) of a TCP header. If no argument is given the
current value is returned.

— Method **tcp:flags** *flags*

Combined accessor and setter method for the TCP header flags (NS, CRW,
ECE, URG, ACK, PSH, RST, SYN and FIN). Sets the header's flags accoring
to *flags* (9 bit unsigned intetger). If no argument is given the current
flags are returned.

— Method **tcp:checksum** *payload*, *length*, *ip*

Computes and sets the "Checksum" field for *length* bytes of *payload*
and optionally *ip*. If no argument is given the current value of the
"Checksum" field is returned.


### UDP (lib.protocol.udp)

The `lib.protocol.udp` module contains a class for representing *UDP
headers*.

— Method **udp:new** *config*

Returns a new UDP header for *config*. *Config* must a be a table
which may contain the following keys:

* `src_port` - "Source Port Number" field (16 bit unsigned
  integer). Default is 0. 
* `dst_port` - "Destination Port Number" field (16 bit unsigned
  integer). Default is 0.

— Method **udp:src_port** *port*

— Method **udp:dst_port** *port*

Combined accessor and setter methods for the source and destination port
fields. Sets the source or destination port individually. Returns the
current port if called without arguments. Default is 8 (the UDP header
length).

— Method **udp:length** *length*

Combined accessor and setter method for the "Length" field. Sets the
"Length" field* to *length* (a 16 bit unsigned integer). If no argument
is given the current value of the "Length" field is returned.

— Method **udp:checksum** *payload*, *length*, *ip*

Computes and sets the "Checksum" field for *length* bytes of *payload*
and optionally *ip*. If no argument is given the current value of the
"Checksum" field is returned.


### GRE (lib.protocol.gre)

The `lib.protocol.gre` module contains a class for representing *GRE
headers*. The `gre` protocol class only supports the checksum and key
extensions and the `lib.protocol.ethernet` upper layer protocol.

— Method **gre:new** *config*

Returns a new GRE header for *config*. *Config* must a be a table
which may contain the following keys:

* `protocol` - Upper layer protocol. May be `0x6558` (Ethernet). Default
  is `nil`.
* `checksum` - Set to `true` to enable checksumming. Default is `false`.
* `key` - 32 bit unsigned integer. Enables keying if supplied. Default is
  `nil`.

— Method **gre:checksum** *payload*, *length*

Combined accessor and setter method for the checksum field. Computes and
sets the checksum field for *length* bytes of *payload*. If no argument
is given the current checksum is returned. Returns `nil` if checksumming
is disabled.

— Method **gre:checksum_check** *payload*, *length*

Predicate to verify *length* bytes of *payload* against the header
checkum. Return `nil` if checksumming is disabled.

— Method **gre:key** *key*

Combined accessor and setter method for the key field. Sets the key field
to *key*. If no argument is given the current key is returned. Returns
`nil` if keying is disabled.

— Method **gre:protocol** *protocol*

Combined accessor and setter method for the upper layer protocol. Sets
the upper layer protocol to *protocol*. If no argument is given the
current upper layer protocol is returned.


### ICMP (lib.protocol.icmp.header)

The `lib.protocol.icmp.header` module contains a class for representing
*ICMP headers*.  The `icmp` protocol class currently supports two upper
layer protocols: `lib.protocol.icmp.nd.ns` and `lib.protocol.icmp.nd.na`.
These upper layer protocols implement the headers necessary to perform
"Neighbor Discovery".

— Method **icmp:new** *type*, *code*

Returns a new ICMP header of *type* which may be either 135 or 136 for
`lib.protocol.icmp.nd.ns` or `lib.protocol.icmp.nd.na`
respectively. Optionally *code* can be supplied to set the "Code" field
for the type.

— Method **icmp:type** *type*

— Method **icmp:code** *code*

Combined accessor and setter methods. These methods set the values of the
instance fields (see `new`) of an ICMP header. If no argument is given
the current value is returned.

— Method **icmp:checksum** *payload*, *length*, *ipv6*


Computes and sets the "Checksum" field for *length* bytes of
*payload*. If the lower protocol layer is `lib.protocol.ipv6` then *ipv6*
must be set to a true value.

— Method **icmp:checksum_check** *payload*, *length*, *ipv6*

Predicate to test if the header's "Checksum" field matches *length* bytes
of *payload*. If the lower protocol layer is `lib.protocol.ipv6` then
*ipv6* must be set to a true value.


#### Neighbor Solicitation (lib.protocol.icmp.nd.ns)

— Method **ns:new** *target*

Returns a new *Neighbor Solicitation* header. *Target* is the IP address
used for the "Target Address" field.

— Method **ns:target** *target*

Combined accessor and setter method for the "Target Address" field. Sets
the "Target Address" field to *target*. If no argument is given the
current value is returned.

— Method **ns:target_eq** *target*

Predicate to test if the header's value in the "Target Address" field is
equivalent to *target*.


#### Neighbor Advertisement (lib.protocol.icmp.nd.na)

— Method **na:new** *target*, *router*, *solicited*, *override*

Returns a new *Neighbor Advertisement* header. *Target* is the IP address
used for the "Target Address" field. *Router*, *solicited* and *override*
can be boolean values to set the "Router", "Solicited" and "Override"
flags respectively. The default for the flags is 0.

— Method **ns:target** *target*

— Method **ns:router** *router*

— Method **ns:solicited** *solicited*

— Method **ns:override** *override*

Combined accessor and setter methods. These methods set the values of the
instance fields (see `new`) of an Neighbor Advertisement header. If no
argument is given the current value is returned.

— Method **ns:target_eq** *target*

Predicate to test if the header's value in the "Target Address" field is
equivalent to *target*.


#### Neighbor Discovery Options (lib.protocol.icmp.nd.header)

Both Neighbor Solicitation and Advertisement (`lib.protocol.icmp.nd.ns`
and `lib.protocol.icmp.nd.na`) headers implement an `options` method for
parsing *TLV Options* contained in the their payloads.

Example:

```
 -- Parse datagram with ICMP/NA packet
local na = dgram:parse()
 -- Parse TLV Options
local options = na:options(dgram:payload())
```

— Method **nd:options** *payload*, *length*

Parses and returns an array of TLV Options (see
`lib.protocol.icmp.nd.options.tlv`) from *length* bytes of *payload*.


#### TLV Option (lib.protocol.icmp.nd.options.tlv)

The `lib.protocol.icmp.nd.options.tlv` module contains a class for
representing TLV Options. Currently only two types of options are
implemented: "Source Link-Layer Address" (`"src_ll_addr"`) and "Target
Link-Layer Address" (`"tgt_ll_address"`). Both are represented by the
`lladdr` class (see `lib.protocol.icmp.nd.options.lladdr`).

— Method **tlv:new** *type*, *data*

Returns a new TLV Option object for *data* of *type*. *Type* may be
either 1 for "Source Link-Layer Address" or 2 for "Target Link-Layer
Address". *Data* must be a `lladdr` object.

— Method **tlv:name**

Returns a string denoting the type of the option. Either `"src_ll_addr"`
for "Source Link-Layer Address" or `"tgt_ll_address"` for "Target
Link-Layer Address".

— Method **tlv:length**

Returns the the size of the TLV Option as multiples of 8 bytes.

— Method **tlv:type** *type*

Combined accessor and setter method. Sets the type field (see `new`) to
*type*. If no argument is given the current value of the type field is
returned.

— Method **tlv:option**

Returns an object of the class denoted by the type field. Currently that
only includes `lladdr` instances.

#### Link-Layer Address Option (lib.protocol.icmp.nd.options.lladdr)

The `lib.protocol.icmp.nd.options.lladdr` module contains a class for
representing Link-Layer Address Options.

— Method **lladdr:new** *address*

Returns a new Link-Layer Option object for MAC *address* in binary
representation.

— Method **lladdr:name**

Returns the string `"ll_addr"`.

— Method **lladdr:addr** *address*

Combined accessor and setter method. Sets the address field (see `new`)
to *address*. If no argument is given the current value of the address
field is returned.


### Datagram (lib.protocol.datagram)

The `lib.protocol.datagram` module provides basic mechanisms for parsing,
building and manipulating a hierarchy of protocol headers and the
associated payload contained in a data packet.  In particular, it
supports:

* Parsing and in-place manipulation of protocol headers in a received
  packet
* In-place decapsulation by removing leading protocol headers
* Adding headers to an existing packet
* Creation of a new packet
* Appending payload to a packet

It mediates between packets as defined in `core.packet` and *protocol
classes* which are defined as classes derived from the protocol header
base class in the `lib.protocol.header` module.

The contents of a datagram instance are logically divided into three
areas: The payload, parsed headers and pushed headers. The datagram
payload is a sequence of bytes either inherited from the packet given to
`datagram:new` or appended using `datagram:payload`. The headers in the
payload can be parsed using `datagram:parse_match`, which will shrink the
payload by the header. Finally, synthetic headers can be prepended to the
datagram using `datagram:push`.  To get the whole datagram as a packet
use `datagram:packet`.

    DIAGRAM: Datagram
    datagram packet
    +------------------+
    |packet            |
    |                  |
    |+------=---------+|
    || Pushed headers ||
    |+----------------+|
    |+------=---------+|<---Beginning of initial packet
    || Parsed headers ||
    ||------=---------||
    ||    Payload     ||
    |+----------------+|
    +------------------+

A datagram can be used in two modes of operation, called "immediate
commit" and "delayed commit".  In immediate commit mode, the `push`
and `pop` methods immediately modify the underlying packet.  However,
this can be undesireable.

Even though the manipulations are relatively fast by using SIMD
instructions to move and copy data when possible, performance-aware
applications usually try to avoid as much of them as possible.
This creates a conflict if the caller performs operations to push
or parse a sequence of protocol headers in immediate commit mode.

This problem can be avoided by using delayed commit mode.  In this
mode, the `push` methods add the data to a separate buffer as
intermediate storage.  The buffer is prepended to the actual packet in
a single operation by calling `datagram:commit`.

The `pop` methods are made light-weight in delayed commit mode as well
by keeping track of an additional offset that indicates where the
actual packet starts in the packet buffer.  Each call to one of the
`pop` methods simply increases the offset by the size of the popped
piece of data.  The accumulated actions will be applied as a single
operation by `datagram:commit`.

The `push` and `pop` methods can be freely mixed in delayed commit
mode.

Due to the destructive nature of these methods in immediate commit
mode, they cannot be applied when the parse stack is not empty,
because moving the data in the packet buffer will invalidate the
parsed headers.  The `push` and `pop` methods will raise an error in
that case.

The buffer used in delayed commit mode has a fixed size of 512
bytes.  This limits the size of data that can be pushed in a single
operation.  A sequence of push/commit operations can be used to
push an arbitrary amount of data in chunks of up to 512 bytes.


— Method **datagram:new** *packet*, *protocol*, *options*

Creates a datagram for *packet* or from scratch if *packet* is `nil`.
*Protocol* will be used by `parse_match` to parse the packet
payload. If *protocol* is not `nil` it is set as the initial upper
layer protocol.  If *options* is not `nil` it must be a table that
selects configurable properties of the class.  Currently, the only
option is the selection of immediate or delayed commit mode by setting
the key `delayed_commit` to `false` or `true`, respectively.  The
default is immediate commit mode.

— Method **datagram:push** *header*

Prepends *header* to the front of the datagram. This method
destructively modifies the underlying packet in immediate commit mode
and raises an error if the parse stack is not empty.

In delayed commit mode, *header* is prepended to an intermediate buffer.

— Method **datagram:push_raw** *data*, *length*

This method behaves like the *datagram:push* method for an arbitrary
chunk of memory of length *length* located at the address pointed to
by *data*.

— Method **datagram:parse_match** *protocol*, *check*

Attempts to parse the next header in the datagram, thereby removing it
from the payload. Returns a header instance of class *protocol* on
success. If *protocol* is `nil` the current upper layer protocol as set
by `datagram:new` or previous calls to `parse_match` is used.

If neither *protocol* nor the upper layer protocol is set or the
constructor of the protocol class returns `nil`, the parsing operation
has failed and `parse_match` returns `nil`.  The datagram remains
unchanged.

If the protocol class instance has been created successfully, it is
passed as single argument to the anonymous function *check*.

If *check* returns a false value, the parsing has failed and
`parse_match` returns `nil`.  The packet remains unchanged.

If *check* is not supplied or if it returned a true value, the parsing
has succeeded and the current upper layer protocol of the datagram is set
to the value returned by `header:upper_layer`.

— Method **datagram:parse** *protocols_and_checks*

A wrapper around `parse_match` that allows parsing of a sequence of
headers with a single method call.

If *protocols_and_checks* is a sequence of protocol class and check
function pairs, `parse_match` is called for each pair. Returns the header
object of the last header parsed or `nil` if any of the calls to
`parse_match` return `nil`.

If called with a `nil` argument, this method is equivalent to
`parse_match` called without arguments.

— Method **datagram:parse_n** *n*

A wrapper around `parse_match` that parses the next *n* protocol headers
using the current upper layer protocol and subsequent values of
`header:upper_layer`. It returns the last header object or `nil` if less
than *n* headers could be parsed successfully.

— Method **datagram:unparse** *n*

Undoes the last *n* calls to `parse_match` on the datagram. E.g. prepends
*n* parsed headers back to the payload. The sequence of parsed headers
can be obtained by calling `stack`.

— Method **datagram:pop** *n*

Removes the leading *n* parsed headers from the datagram. Note that
headers added via `push` can not be removed using `pop`. The caller
has to ensure that the datagram contains at least *n* headers that
were parsed using `parse_match`.  The sequence of parsed headers can
be obtained by calling `stack`. This method destructively modifies the
underlying packet in immediate commit mode and raises an error if the
parse stack is not empty.

In delayed commit mode, the packet is not modified and the parse stack
remains valid.

For instance let *d* be an datagram with an Ethernet header followed by
an IPv6 header. Assuming we have parsed both headers using
`d:parse_n(2)`, we could call `d:pop(1)` to decapsulate the IPv6 packet
from its Ethernet header.

— Method **datagram:pop_raw** *length*, *ulp*

Removes *length* bytes from the beginning of the datagram. If *ulp* is
given it is set as the current upper layer protocol. This method
destructively modifies the underlying packet in immediate commit mode
and raises an error if the parse stack is not empty.

In delayed commit mode, the packet is not modified and the parse stack
remains valid.

— Method **datagram:stack**

Returns the parsed header objects as a sequence.

— Method **datagram:packet**

Returns a packet (see `core.packet`) containing the datagram (including
pushed headers).

— Method **datagram:payload** *pointer*, *length*

Combined payload accessor and setter method. Returns a pointer to the
datagram payload and its byte size.

If *pointer* and *length* are supplied then *length* bytes starting from
*pointer* are appended to the datagram's payload.

— Method **datagram:data**

Returns `data` and `length` of the underlying packet.

- Method **datagram:commit**

If called in delayed commit mode, the operations accumulated by the
`push` and `pop` methods since the creation of the datagram or the
last invocation of *datagram:commit* are commited to the underlying
packet.  An error is raised if the parse stack is not empty.

The method can be safely called in immediate commit mode.
