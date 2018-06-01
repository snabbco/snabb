Next hop forwarder
------------------

Implements two network classificators: nh_fwd4 and nh_fwd6, for IPv4 and IPv6 traffic respectivally.

A Next-hop forwarder redirects traffic coming from one input link, normally the wire,  to two different output links, a service and a VM.  The decision is based on examining the headers of packets and applying heuristics.

The common use case of this app is when we need to forward incoming traffic to a specialized service, for instance the lwAFTR, and forward the rest of the traffic to a VM.
