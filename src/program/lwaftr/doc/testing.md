# Testing

The lwAFTR and associated software is tested in several ways. Igalia uses unit
tests, integration tests ("selftest.sh"), end-to-end tests, and does an
increasing amount of automated performance analysis with Hydra.

An example of our testing is how ARP support is tested. ARP is implemented in a
small app, independently of the lwAFTR, and included with the lwAFTR an app
network within Snabb. It has unit tests (in the function 'selftest()', following
the convention to run unit tests automatically), which check how the request is
formed, and the reply the library gives to that request. We also have two
end-to-end tests for ARP; these specify an incoming packet, pass it through the
whole app network, and make sure that the end result is byte for byte identical
with what is expected. Both the implementation and the testing were done with
careful attention paid to RFC 826 throughout, as well as to dumps of ARP packets
from the live network the developer was on.

ARP has two main parts: resolving a remote address, and providing the address of
the lwAFTR on request. The first one can be tested in a network by specifying
only the remote IP of the next IPv4 hop (not the ethernet address), then sending
packets through the lwAFTR and confirming on the remote host that they are
arriving. The latter can be tested by issuing an ARP request to the lwaftr from
another machine; if the other machine runs Linux, `arp -n` should then show a
new entry corresponding to the lwAFTR.  The end to end tests simulate both of
these cases, but with captured packets rather than a live network.

There are a hierarchy of tests. Unit tests are internally orientedf, and make
sure that basic functionality and some edge cases are tested. By convention,
they are found in functions called selftest().

Integration tests tend to be called selftest.sh, or invoked by selftesh.sh.
These test larger components of the system. The end to end tests have IPv4 and
IPv6 packet captures, run them through the lwaftr app network, and compare the
results with predetermined captures and counter values, making sure everything
works as expected. These test a large variety of RFC-mandated behaviours.

We also have some 'soak tests', which repeatedly do the same thing a large
number of times; these show that the system holds up under the tested heavy
workloads, without errors like memory corruption or memory leaks, which would
cause them to fail.

Igalia is following the lead of upstream Snabb in automated performance testing.
This is a work in progress, and can be seen at
https://hydra.snabb.co/project/igalia . We are also developing property-based
tests to stress-test our yang infrastructure, and have written a load tester for
our yang implementation as well, verifying that it is performant.
