Usage: check [-r] CONF V4-IN.PCAP V6-IN.PCAP V4-OUT.PCAP V6-OUT.PCAP [COUNTERS.LUA]
       check -h

  -h, --help
                             Print usage information.
  -r, --regen
                             Regenerate counter files, instead of checking.
  --on-a-stick
                             Run in on-a-stick mode.
  -D, --duration
                             Time to run Snabb for (default 0.10 seconds)

Without -r:
Run the lwAFTR with input from IPV4-IN.PCAP and IPV6-IN.PCAP, and record
output to IPV4-OUT.PCAP and IPV6-OUT.PCAP. COUNTERS.LUA contains a table that
defines the counters and by how much each should increment.
Exit when finished.  This program is used in the lwAFTR test suite.

With -r:
Regenerate the counter files for the test suite. This is useful after
extensive changes to implementation details of counters.
