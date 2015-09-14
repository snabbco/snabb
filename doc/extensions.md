# Pflang extensions

Pflua implements "pflang", the language that libpcap uses to express
packet filters.  Pflua also optionally provides some experimental
extensions to pflang.  These extensions are experimental, and naturally
are not supported by the libpcap pipeline.  Please let us know if you
find them to be useful to you.

## The address-of operator: `&`

By default, this operator is enabled.  To disable, include this code
somewhere in your app before parsing:

```lua
require('pf.parse').allow_address_of = false
```

An AddressExpression is a new kind of arithmetic expression.  The
grammar is as follows:

```
AddressExpression := '&' Addressable
Addressable := PayloadAccessor '[' ArithmeticExpression [ ':' (1|2|4) ] ']'
PayloadAccessor := 'ip' | 'ip6' | 'tcp' | 'udp' | 'icmp' |
   'arp' | 'rarp' | 'wlan' | 'ether' | 'fddi' | 'tr' | 'ppp' |
   'slip' | 'link' | 'radio' | 'ip' | 'ip6' | 'tcp' | 'udp' |
   'igmp' | 'pim' | 'igrp' | 'vrrp' | 'sctp'
```

The semantics are that `&foo` returns the address of `foo`, as a byte
offset from the beginning of the packet.  Therefore if a packet is TCP
and the first byte of the packet is the first byte of the ethernet
header, then `ether[&tcp[0]] = tcp[0]` will always be true.

If the packet is not of the correct kind, then the comparison in which
the AddressExpression is embedded fails to match.  This would be the
case, for example, if you asked for `&udp[0]` but the packet isn't UDP.

Likewise, if the address isn't within the packet, the containing
comparison will fail to match.  An example would be `&udp[64]` on a UDP
packet whose size, including the UDP header but excluding the IP or
other L2 header is less than 64 bytes.  Note that this behavior differs
from `udp[64]` on a short packet; such an access causes the whole filter
to abort (see the
[pflang](https://github.com/Igalia/pflua/blob/master/doc/pflang.md)
documentation).

## The pfmatch language

See [the pfmatch
page](https://github.com/Igalia/pflua/blob/master/doc/pfmatch.md), for
more.
