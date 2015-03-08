Usage: solarflare <npackets> <packet-size>

Send the given number of packets through a Solarflare NIC.  The test
assumes that the first two Solarflare NICs are connected back-to-back.

Example usage with 10 million packets, packet size 128 bytes:
  solarflare 10e6 128
