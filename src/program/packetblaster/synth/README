Usage: packetblaster synth [OPTIONS] <PCI>...

  -s SOURCE, --src SOURCE
                             Source MAC-Address.
                             Default: 00:00:00:00:00:00
  -d DESTINATION, --dst DESTINATION
                             Destination MAC-Address.
                             Default: 00:00:00:00:00:00
  -S SIZES, --sizes SIZES
                             A comma separated list of numbers. Send packets of
                             SIZES bytes.
                             Default: 64
  -D DURATION, --duration DURATION
                             Run for DURATION seconds.
                             Default: unlimited
  -h, --help
                             Print usage information.

packetblaster transmits packets continuously to one or more network adapters.
The PCI arguments are Lua pattern strings that are used to match the network
adapters to use. The packets are synthetisized according to SOURCE,
DESTINATION and SIZES.

Examples:
  packetblaster synth -d 22:22:22:22:22:22 -S 32,64,128 01:00.0
