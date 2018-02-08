Usage:
  unhexdump [-hta] FILE.PCAP

  -h, --help
                     Print usage information
  -t, --truncate
                     Truncate the output file if it already exists
  -a, --append
                     Append packets to the output file if it already exists

Read "hexdump" packet representations from stdin and write out binary
packets to a pcap savefile.  Useful when you need to get some data to
wireshark but you only have it in text format for some reason.

Blank lines delimit packets.  Packet data is a non-empty sequence of hex
pairs.  Hex pairs may be separated by sequences of whitespace,
punctuation, 'x' or 'X' characters.

Example:

  $ snabb unhexdump foo.pcap <<EOF
      52:54:00:02:02:02 52:54:00:01:01:01 08 00 45 00
      00 34 59 1a 40 00 40 06 00 00 c0 a8 14 a9 6b 15
      f0 b4 de 0b 01 bb e7 db 57 bc 91 cd 18 32 80 10
      05 9f 00 00 00 00 01 01 08 0a 06 0c 5c bd fa 4a
      e1 65

      52:54:00:02:02:02 52:54:00:01:01:01 08 00 45 00
      00 34 59 1a 40 00 40 06 00 00 c0 a8 14 a9 6b 15
      f0 b4 de 0b 01 bb e7 db 57 bc 91 cd 18 32 80 10
      05 9f 00 00 00 00 01 01 08 0a 06 0c 5c bd fa 4a
      e1 65
  EOF
  Wrote 2 packets to 'foo.pcap'.
  $
