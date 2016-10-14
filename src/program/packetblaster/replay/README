Usage: packetblaster replay [OPTIONS] <PCAPFILE> <PCI>...

  -D DURATION, --duration DURATION
                             Run for DURATION seconds.
                             Default: unlimited
  --no-loop                  Do not loop through <PCAPFILE>.
                             Duration is one second if not set.
  -h, --help
                             Print usage information.

packetblaster transmits packets continuously to one or more network adapters.
The PCI arguments are Lua pattern strings that are used to match the network
adapters to use. The packets are extracted from PCAPFILE.

Examples:
  packetblaster replay myfile.cap 0000:01:00.0
