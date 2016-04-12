# RFC 7596 compliance

**Snabb lwAFTR** aims to be fully [RFC 7596](https://tools.ietf.org/html/rfc7596)
compliant. As alpha software, there are a number of limitations, and it does
not aim to be compliant with all other relevant RFCs.

Here are the RFC 7596 **MUSTs**, along with an assessment of the lwaftr with
respect to them. Following that, there is a listing of limitations. Any errors
or discrepencies between RFC 7596, the documented behavior, and the code will
be treated as a high-priority issue; please contact the developers if one is
found.

## MUSTS

### 6.1. Binding Table Maintenance

_"The lwAFTR MUST synchronize the binding information with the port-
restricted address provisioning process. If the lwAFTR does not particip-
ate in the port-restricted address provisioning process, the binding MUST
be synchronized through other methods (e.g., out-of-band static update).
If the lwAFTR participates in the port-restricted provisioning process,
then its binding table MUST be created as part of this process.
For all provisioning processes, the lifetime of binding table entries MUST
be synchronized with the lifetime of address allocations."_

Snabb lwAFTR alpha does not participate in provisioning process. Its binding
table information is found in a text file, which could be updated out of
band by the user.

### 6.2. lwAFTR Data Plane Behavior

_"Several sections of RFC 6333 provide background information on the
AFTR’s data plane functionality and MUST be implemented by the lwAFTR
as they are common to both solutions. The relevant sections are:
6.2 Encapsulation: Covering encapsulation and de-capsulation of tunneled
traffic
6.3 Fragmentation and Reassembly: Fragmentation and re-assembly con-
siderations (referencing RFC 2473)
7.1 Tunneling: Covering tunneling and Traffic Class mapping between
IPv4 and IPv6 (referencing RFC 2473). Also see RFC 2983"._

It is believed that Snabb lwAFTR alpha is fully compatible with this.
It does not change its internal state (such as MTU settings or TTL settings)
in response to incoming ICMP, but it is not required to by [RFC 2473](https://tools.ietf.org/html/rfc2473).
IPv6 fragments are reassembled before being processed, as required.
Fragmentation is performed on the basis of configured MTUs.
IPv6 packets are fragmented if required by the configured IPv6 MTU.
Traffic class mapping is performed.

----

_"If no match is found [for an IPv4-in-IPv6 packet from the lwB4] (e.g.,
no matching IPv4 address entry, port out of range), the lwAFTR MUST
discard or implement a policy (such as redirection) on the packet."_

Snabb lwAFTR alpha discards these packets.

----

_"An ICMPv6 type 1, code 5 (source address failed ingress/egress policy)
error message MAY be sent back to the requesting lwB4. The ICMP
policy SHOULD be configurable."_

This is implemented. It is configurable via `policy_icmpv6_outgoing`, which
can be set to _'ALLOW'_ or _'DENY'_. A more specific configuration option will
be provided if requested.

----

_"If no match is found [for an incoming IPv4 packet], the lwAFTR MUST
discard the packet. An ICMPv4 type 3, code 1 (Destination unreachable,
host unreachable) error message MAY be sent back. The ICMP policy
SHOULD be configurable."_

This is implemented. It is configurable via `policy_icmpv4_outgoing`, which
can be set to _'ALLOW'_ or _'DENY'_. A more specific configuration option will
be provided if requested.

----

_"The lwAFTR MUST support hairpinning of traffic between two lwB4s,
by performing decapsulation and re-encapsulation of packets from one
lwB4 that need to be sent to another lwB4 associated with the same
AFTR. The hairpinning policy MUST be configurable."_

This is implemented. It is configurable via the configuration variable
`hairpinning`,  which can be set to _'true'_ or _'false'_.

----

_"For both the lwAFTR and the lwB4, ICMPv6 MUST be handled as
described in RFC 2473."_

It is, including hairpinning considerations.

RFC 2473 mentions 4 incoming ICMPv6 types: _hop limit exceeded_, _unreachable
node_, _parameter problem_, and _packet too big_. Not all of these correspond
exactly to anything found in [ICMPv6 Parameters](http://www.iana.org/assignments/icmpv6-parameters/icmpv6-parameters.xhtml).

_Hop limit exceeded_ is interpreted by this implementation to strictly be
(3, 0) (type, code). _Packet too big_ is interpreted to be strictly (2, 0).
_Unreachable node_ is interpreted to be type 1, regardless of code.
_Parameter problem_ is interpreted to be anything with type 4, regardless of code.

### 8.1. ICMPv4 Processing by the lwAFTR

_"For inbound ICMP messages The following behavior SHOULD be imple-
mented by the lwAFTR to provide ICMP error handling and basic remote
IPv4 service diagnostics for a port-restricted CPE:
1. Check the ICMP Type field.
2. If the ICMP type is set to 0 or 8 (echo reply or request), then the
lwAFTR MUST take the value of the ICMP identifier field as the source
port, and use this value to lookup the binding table for an encapsulation
destination. If a match is found, the lwAFTR forwards the ICMP packet
to the IPv6 address stored in the entry; otherwise it MUST discard the
packet.
3. If the ICMP type field is set to any other value, then the lwAFTR
MUST use the method described in REQ-3 of RFC 5508 8 to locate the
source port within the transport layer header in ICMP packet’s data field.
The destination IPv4 address and source port extracted from the ICMP
packet are then used to make a lookup in the binding table. If a match
is found, it MUST forward the ICMP reply packet to the IPv6 address
stored in the entry; otherwise it MUST discard the packet.
Otherwise the lwAFTR MUST discard all inbound ICMPv4 messages.
The ICMP policy SHOULD be configurable."_

This is implemented. It is configurable via `policy_icmpv4_incoming`, which
can be set to _'ALLOW'_ or _'DENY'_. A more specific configuration option will
be provided if requested.

----

"The lwAFTR MUST rate limit ICMPv6 error messages (see Section 5.1)
to defend against DoS attacks generated by an abuse user."_

This is implemented, and configurable via the configuration variables
`icmpv6_rate_limiter_n_packets` and `icmpv6_rate_limiter_n_seconds`, which
allow at most x outgoing ICMPv6 packets per y seconds.

## Additional RFC considerations

ICMPv4 packets are [RFC 1812](https://tools.ietf.org/html/rfc1812) compliant:
that is, they contain up to 576 bytes, rather than having an
[RFC 792](https://tools.ietf.org/html/rfc792) style IPv4 header + 8 octets
payload.

ICMPv6 packets are up to 1280 bytes.

----

While not an RFC, Snabb lwAFTR allows the lwaftr to have multiple IPv6
addresses associated with various B4s, as described in
[draft-farrer-softwire-br-multiendpoints-01](https://tools.ietf.org/html/draft-farrer-softwire-br-multiendpoints-01).

## Limitations

[RFC 2473](https://tools.ietf.org/html/rfc2473) says:

_"The tunnel entry-point node performs Path MTU discovery on the path
between the tunnel entry-point and exit-point nodes [PMTU-Spec], [ICMP-Spec]."_

Snabb lwAFTR alpha does not do Path MTU discovery.

Snabb lwAFTR alpha is to be run in controlled environments, where the whole
IPv6 network it connects to shares one MTU, mitigating the impact of the lack
of path MTU discovery. This will be addressed in a future release.

However, correct IPv4 ICMP messages ought to let external hosts do path MTU
discovery that goes through the lwaftr, and the lwaftr respects the Do Not
Fragment bit of IPv4 packets.

----

Snabb lwAFTR alpha is assumed to connect to exactly one host with a known MAC
address on each interface. Later work will include ARP/NDP support and remove
this limitation.

----

Packets (including reassembled ones) are limited to 10240 bytes.
This is due to a Snabb default, and will be addressed upon request.

----

IPv6 fragmentation and reassembly works, and reassembly only occurs if it is
valid (no overlapping fragments, fragment data lengths are a multiple of 8,
identifiers match, etc), but there are limitations. For instance, no
timeout message is sent if packet reassembly takes more than 60 seconds.

----

It is assumed that no extra IPv6 headers other than for fragmentation are present.
