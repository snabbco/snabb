# Change Log

## [1.0] - 2015-10-01

### Added

- Static configuration of the provisioned set of subscribers and their mapping
to IPv4 addresses and port ranges from a text file (binding table).
- Static configuration of configurable options from a text file (lwaftr.conf).
- Feature-complete encapsulation and decapsulation of IPv4-in-IPv6.
- ICMPv4 handling: configurable as per RFC7596.
- ICMPv6 handling, as per RFC 2473.
- Feature-complete tunneling and traffic class mapping, with first-class support
for IPv4 packets containing UDP, TCP, and ICMP, as per RFCs 6333, 2473 and 2983.
- Feature-complete configurable error handling via ICMP messages, for example 
"destination unreachable", "host unreachable", "source address failed 
ingress/egress filter", and so on as specified.
- Association of multiple IPv6 addresses for an lwAFTR, as per draft-farrer-
softwire-br-multiendpoints.
- Full fragmentation handling, as per RFCs 6333 and 2473.
- Configurable (on/off) hairpinning support for B4-to-B4 packets.
- A static mechanism for rate-limiting ICMPv6 error messages.
- 4 million packets per second (4 MPPS) in the following testing configuration:
   - Two dedicated 10G NICs: one internet-facing and one subscriber facing (2 MPPS per NIC)
   - 550-byte packets on average.
   - A small binding table.
   - "Download"-like traffic that stresses encapsulation speed
   - Unfragmented packets
   - Unvirtualized lwAFTR process
   - A single configured IPv6 lwAFTR address.
- Source:
   - apps/lwaftr: Implementation of the lwAFTR.
- Programs:
   - src/program/snabb_lwaftr/bench: Used to get an idea of the raw speed of the
lwaftr without interaction with NICs
   - src/program/snabb_lwaftr/check: Used in the lwAFTR test suite. 
   - src/program/snabb_lwaftr/run: Runs the lwAFTR.
   - src/program/snabb_lwaftr/transient: Transmits packets from a PCAP-FILE to 
the corresponding PCI network adaptors. Starts at zero bits per second, ramping 
up to BITRATE bits per second in increments of STEP bits per second.
- Tests:
   - src/program/tests:
      - end-to-end/end-to-end.sh: Feature tests.
      - data: Different data samples, binding tables and lwAFTR configurations.
      - benchdata: Contains IPv4 and IPv6 pcap files of different sizes.
