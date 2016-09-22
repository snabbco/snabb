# PcapReader and PcapWriter Apps (apps.pcap.pcap)

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

## Configuration

Both `PcapReader` and `PcapWriter` expect a filename string as their
configuration arguments to read from and write to respectively. `PcapWriter`
will alternatively accept an array as its configuration argument, with the
first element being the filename and the second element being a *mode* argument
to `io.open`.
