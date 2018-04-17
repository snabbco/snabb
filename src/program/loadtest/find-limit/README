Usage: find-limit [OPTIONS] <PCAP-FILE> <TX-NAME> <RX-NAME> <PCI> [<PCAP-FILE> <TX-NAME> <RX-NAME> <PCI>]...
       find-limit [OPTIONS] <PCAP-FILE> <PCI>

  -b BITRATE, --bitrate BITRATE
                             Test bitrates up to BITRATE bits/second.
                             Default: 10e9.
  -D DURATION, --duration DURATION
                             Linger on each step for DURATION seconds.
                             Default: 1.
  -p PRECISION, --precision PRECISION
                             Measure to PRECISION bits/second.
                             Default: 0.001e9.
  -r RETRY-COUNT, --retry-count RETRY-COUNT
                             If a step fails, retry it RETRY-COUNT times.
                             Default: 3.
  --cpu CPU
                             Bind to the given CPU.
  --exec EXEC
                             Run EXEC in a shell after every step to
                             determine if the step succeeded.  Otherwise
                             a successful step is one that receives as
                             many packets on its interface as it sends.
  -h, --help
                             Print usage information.

Apply load by replaying packets from PCAP-FILE to the corresponding PCI network
adaptors. It will attempt to determin the highest bitrate at which a test passes.
If no script is supplied then find-limit will attempt to see if packets are being
dropped by checking the traffic sent vs traffic recieved.

If you specify only a PCI address and PCAP file it will configure itself to work
the same as specifying a single device as both the recieve and transmit interface.

Examples:
  find-limit 01:00.0 cap1.pcap
  find-limit cap1.pcap tx tx 01:00.0
  find-limit cap1.pcap "NIC 0" "NIC 1" 01:00.0 cap2.pcap "NIC 1" "NIC 0" 01:00.0
