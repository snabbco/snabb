# Pflang resources

"Pflang" is what we are calling the language that libpcap uses to
express packet filters.  It's easier to say than "the pcap-filter
language".

On the plus side, pflang is widely used, works pretty well, is
pleasantly terse and expressive, and has a huge amount of
domain-specific knowledge baked into it.

At the same time, to a language professional, pflang can be infuriating.
This page documents some less-known aspects of pflang.

## Specification

https://www.wireshark.org/docs/man-pages/pcap-filter.html

If you have libpcap installed on your system, you might also have the
pcap-filter man page installed.  Try `man pcap-filter`.

## Syntactic corner-cases

### Implicit OR

Quoth the documentation:

> If an identifier is given without a keyword, the most recent keyword is assumed. For example,
>
> > not host vs and ace
>
> is short for
>
> > not host vs and host ace
>
> which should not be confused with
>
> > not ( host vs or ace )

This is bizarre and ambiguous; what if you have a host whose name is a
pflang keyword, or a symbolic constant?

Also note a further example from the documentation:

> host helios and ( hot or ace )

Grrr.

### Use of `-` both as a name component and as a delimiter

These are all valid port ranges:

```
portrange ftp-data-90
portrange 80-ftp-data
portrange ftp-data-iso-tsap
portrange echo-ftp-data
```

In each of these examples, one of the hyphens delimits the two parts.
Whether it's the first or second depends on the set of known symbolic
port names (!).

Port names are a particular case, as they can only be seen after `port`
or `portrange`.  Arithmetic expressions are more tricky, as there is a
larger set of symbolic constants, and `-` may appear in more places.

### Extraneous backslashes

Under the documentation for `ip proto _proto_`, the documentation says:

> True if the packet is an IPv4 packet (see ip(4P)) of protocol type
> protocol. Protocol can be a number or one of the names icmp, icmp6,
> igmp, igrp, pim, ah, esp, vrrp, udp, or tcp. Note that the identifiers
> tcp, udp, and icmp are also keywords and must be escaped via backslash
> (\\), which is \\\\ in the C-shell.

This note does not make sense.  The context is unambiguous; `ip proto`
_needs_ something to follow it, and can interpret the next token as it
likes.

Also, what could the shell have to do with this?  We don't know.

See also later in the document when it says, when discussing grouping
via parentheses:

> parentheses are special to the Shell and must be escaped

Wat.

## Semantic corner cases

Some parts of pflang are quite surprising.

### Packet access

One set of restrictions is for packet accessors, e.g. the `ip[0]` in
`ip[0] == 42`.

* If the packet is not an IPv4 or IPv6 packet, the filter will
  immediately fail.

* If the index (e.g. 0 in this case) is not within the packet, then the
  filter immediately fails.

There is an interesting bug in libpcap's implementation of length
checking: https://github.com/the-tcpdump-group/libpcap/issues/379

### Numeric range

All numbers in pflang are unsigned 32-bit values.  Operations on these
numbers follows C's semantics.  Notably, arithmetic is modulo 2^32.

Bit shifts are an interesting case.  The C99 draft standard says,
regarding bit shifts:

> The integer promotions are performed on each of the operands. The type
> of the result is that of the promoted left operand. If the value of
> the right operand is negative or is *greater than or equal to the
> width of the promoted left operand*, the behavior is undefined.

But, none of the BPF implementations actually check that the RHS is less
than 32, so they all may execute undefined behavior.

### Division by zero

Including division in pflang was an odd choice, but it's there.  If the
right-hand-side is zero, the filter fails immediately.

### Some selectors assume IPv4

In libpcap, `tcp port 80` only matches IPv4 packets.
