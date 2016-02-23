Usage: firehose [OPTION]... <callback.so>

Firehose: Execute C callback functions directly on live traffic.

The callback function is provided as a shared library (.so file) and
is called with each packet received from one or more 10-Gigabit (Intel
82599) network interfaces.

Receive overhead is very low. firehose can process tens of millions of
packets per second with one CPU core.

Print the example (-e option) and header file (-H option) for
instructions on how to write a callback library.

Options:

  -H, --print-header   Print a copy of firehose.h.
                       You need this to compile your callback library.
  -e, --example        Print instructions for compiling an example library.
  -i PCI, --input PCI  Receive packets from port with PCI address.
  -t SECONDS, --time SECONDS
  -r N, --ring-size N  Set the number of packets in the NIC DMA receive queue.
                       The ring size must be a power of two up to 32768.
