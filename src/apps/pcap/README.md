# Pcap Savefile Apps

## PcapReader and PcapWriter Apps (apps.pcap.pcap)

The `PcapReader` and `PcapWriter` apps can be used to inject and log raw
packet data into and out of the app network using the
[Libpcap File Format](http://wiki.wireshark.org/Development/LibpcapFileFormat/).
`PcapReader`reads raw packets from a PCAP file and transmits them on its
`output` port while `PcapWriter` writes packets received on its `input`
port to a PCAP file.

    DIAGRAM: PcapReader and PcapWriter
    +------------+                          +------------+
    |            |                          |            |
    | PcapReader *---> output    input ---->* PcapWriter |
    |            |                          |            |
    +------------+                          +------------+

### Configuration

Both `PcapReader` and `PcapWriter` expect a filename string as their
configuration arguments to read from and write to respectively. `PcapWriter`
will alternatively accept an array as its configuration argument, with the
first element being the filename and the second element being a *mode* argument
to `io.open`.

## Tap (apps.pcap.tap)

The `Tap` app is a simple in-band packet tap that writes packets that it
sees to a pcap savefile.  It can optionally only write packets that pass
a pcap filter, and optionally subsample so it can write only every /n/th
packet.

    DIAGRAM: pcaptap
               +-------------------+
       input   |                   |   output
          ---->* apps.pcap.tap.Tap *---->
               |                   |
               +-------------------+

### Configuration

The `Tap` app accepts a table as its configuration argument. The
following keys are defined:

— Key **filename**

*Required*.  The name of the file to which to write the packets.

— Key **mode**

*Optional*.  Either `"truncate"` or `"append"`, indicating whether the
savefile will be truncated (the default) or appended to.

— Key **filter**

*Optional*.  A pflang filter expression to select packets for tapping.
Only packets that pass this filter will be sampled for the packet tap.

— Key **sample**

*Optional*.  A sampling period.  Defaults to 1, indicating that every
packet seen by the tap and passing the optional filter string will be
written.  Setting this value to 2 will capture every second packet, and
so on.
