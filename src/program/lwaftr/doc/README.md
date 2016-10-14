# Snabb lwAFTR

## What's a lwAFTR?

Lightweight 4-over-6 (lw4o6) is an IPv6 transition mechanism, specified
as [RFC 7596](https://tools.ietf.org/html/rfc7596).  An lwAFTR is the
internet-facing component of an lw4o6 implementation.

Snabb lwAFTR allows a network operator to run a pure IPv6 network
internally, while providing interoperability with the IPv4 internet.
Each customer IPv6 address may be associated with a limited range of
ports on an IPv4 address.  Restricting port ranges allows an ISP to
serve more customers with a smaller IPv4 address space, which keeps
legacy IPv4 costs low.

The mapping between IPv4 addresses and customers is done in such a way
that the lwAFTR instance only needs to know about the mapping between
each assigned IPv6 address and an IPv4 address and port range.  In
particular, an lwAFTR doesn't need to keep per-flow state, lowering
complexity and cost. This also means that lwAFTR scales horizontally;
multiple lwAFTR functions can service the same set of customers, and any
flow can be processed by any lwAFTR function in the node.

## See a talk!

Katerina Barone-Adesi and Andy Wingo gave a talk on Snabb and the lwAFTR
at [FOSDEM 2016](http://fosdem.org/2016/)!  Eventually there will be a
video here: https://fosdem.org/2016/schedule/event/snabbswitch/

In the meantime, you might like to check out [the
slides](https://wingolog.org/pub/fosdem-2016-lwaftr-slides.pdf).

## Status

The Snabb lwAFTR has a fully functional data plane that can encapsulate
and decapsulate traffic at line rate over two 10 Gb NICs.  It supports
arbitrarily large binding tables, IPv4 address sharing using the
port-set ID scheme, VLAN tagging, fragmentation, reassembly, NDP,
and implements all of RFC 7596 including hairpinning and configurable
ICMP error handling.

An lwAFTR is just one part of a lw4o6 deployment.  The routers that
directly serve the users (the customer premise equipment, or CPE boxes;
e.g. running OpenWRT) need to do the job of terminating a softwire to the
lwAFTR.  The piece of software on the CPE that does this is called the
*B4*, or in the case of lw4o6 the *lwB4*.  Each B4 needs to be deployed
with the IPv6 address of the lwAFTR, the IPv6 address of the B4, and the
corresponding IPv4 address and PSID.  In a real deployment, probably you
will use DHCPv6 or some big NETCONF management system to configure both
the lwAFTR and the CPE.

The lwAFTR only has a data plane for now; you need some external control
plane to update its configuration.  Or, you do what we do now, and you
configure it all at the command like with little text files :)  

## Getting started

### Building the lwAFTR

Building the lwAFTR is pretty simple.  At a shell, just check out the
right branch of Snabb, type make, and you're done!

```bash
git clone https://github.com/Igalia/snabb.git
cd snabb
git checkout lwaftr_starfruit
make
```

That's all!  You'll find a self-contained `snabb` binary in your current
directory that you can copy whereever you like.

We're working on merging to upstream snabb; follow the progress in [this GitHub issue](https://github.com/Igalia/snabb/issues/215).

### Run the end-to-end tests

The Snabb lwAFTR has a set of tests which run the lwAFTR, feeding it in
packets on its IPv4 and IPv6 interfaces and recording the packets that
it gets in reply, checking that the output is exactly what we expect.

To run these tests:

```bash
( cd src/program/lwaftr/tests/end-to-end; sudo ./end-to-end.sh && sudo ./end-to-end-vlan.sh )
```

This test suite includes tests for traffic class mapping, hairpinning
(including for ICMP), fragmentation, and so on.  They do not require
access to a NIC.

### Configuration

There are a lot of configuration knobs!  See the
[Configuration](./README.configuration.md) page, for general configuration, and 
[Binding table](./README.bindingtable.md) page, for more on binding tables.

### Running the lwAFTR

You have a binding table and a configuration: great, you're finally
ready to run the lwAFTR!  The only tricky part is making sure you're
using the right network interfaces.  See [Running](./README.running.md),
and be sure to check [Performance](./README.performance.md) to make sure
you're getting all the lwAFTR can give.

The lwAFTR processes traffic between any NIC supported by Snabb, which
mainly means Intel 82599 10 Gb adapters.  It's also possible to run on
virtualized adapters using the `virtio-net` support that just landed in
Snabb.  See [Virtualization](./README.virtualization.md), for more on how to
get the lwAFTR working on virtualized network interfaces.

## Troubleshooting

[Troubleshooting](./README.troubleshooting.md)

[Counters](./README.counters.md)

## Performance

[Benchmarking](./README.benchmarking.md)

[Performance](./README.performance.md)

## Compatibility and interoperability

[RFC Compliance](./README.rfccompliance.md)

[Discovery of next-hop L2 addresses via NDP](./README.ndp.md)

[Change Log](./CHANGELOG.md)
