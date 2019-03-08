Generate IPv6 B4 and IPv4 Internet traffic towards lightweight 4o6 AFTR server
and report MPPS, Gbps and packet loss on received traffic.

Usage: packetblaster lwaftr [OPTIONS]

  --pci PCI             Interface PCI address, e.g. 0000:05:00.0

  --tap TAP_INTERFACE   Linux tap interface name, e.g. tap0

  --int                 Linux network interface, e.g. eth0

  --pcap PCAP_FILE      Write packets into the pcap file. Program terminates
                        after one cycle of packets (COUNT x SIZES per protocol)

  --sock <SOCKET>       Socket name for virtio interface

  --vlan4 VLANID        Encapsulate IPv4 traffic with IEEE 802.1Q with the given VLANID
  --vlan6 VLANID        Encapsulate IPv6 traffic with IEEE 802.1Q with the given VLANID
  --vlan VLANID         Same as --vlan4 VLANID --vlan6 VLANID

  --src_mac4 SOURCE     Local MAC Address for IPv4 traffic
  --src_mac6 SOURCE     Local MAC Address for IPv6 traffic
  --src_mac SOURCE      Same as --src_mac4 SOURCE --src_mac6 SOURCE
                        Default: 00:00:00:00:00:00

  --dst_mac4 DEST       Remote MAC Address for IPv4 traffic
  --dst_mac6 DEST       Remote MAC Address for IPv6 traffic
  --dst_mac DESTINATION Same as --dst_mac4 DEST --dst_mac6 DEST
                        Default: 00:00:00:00:00:00

  --size SIZES          A comma separated list of numbers. Send packets whose
                        frames are SIZES bytes long.  The frame size includes
                        the size of the packet, including its ethernet
                        headers, and additionally a 4-byte CRC that is written
                        and read by the NIC.

                        Note that the minimum ethernet frame size is 64
                        bytes.  While it's technically possible to make
                        smaller frames, the NIC will pad it up to the
                        minimum before sending, so it's a bit pointless.
                        We signal an error if the user requests a packet
                        size that's smaller than 64 bytes, to avoid
                        misinterpreted benchmarks.

                        Packets will consist of 14 bytes for the
                        ethernet header, 4 additional bytes for the
                        ethernet checksum, a possible 4 bytes for a VLAN
                        tag, 20 for the IPv4 header, 8 for the UDP
                        header, and then a payload.  The payload
                        includes a unique identifier in the first 8
                        bytes.  IPv6 packets include an additional 40
                        bytes for the IPv6 header.

                        Default: 64,64,64,64,64,64,64,594,594,594,1500

  --b4 IPV6,IPV4,PORT   First B4 Client IPv6 mapped to IPv4 and UDP Port.
                        B4 IPv6,IPv4 and Port are incremented for every count, 
                        then rolled over.  Port is incremented by the port number: 
                        e.g. 1024 -> 1024, 2048, 3096 .. 64512 (63 in total)
                        Default: 2001:db8::,10.0.0.0,1024

  --aftr IPV6           IPv6 address of lwaftr server (softwire tunnel endpoint)
                        Default: 2001:db8:ffff::100

  --ipv4 IPV4           Public IPv4. Used as source for IPv4 traffic and
                        as destination in IPv6 packets from B4
                        Default: 8.8.8.8

  --count COUNT         Number of B4 clients to simulate. 
                        Default: 1

  --rate RATE           Rate in MPPS for the generated traffic. Fractions are
                        allowed (e.g. 3.148 for IMIX line rate). If set too high,
                        the actual transmitted rate depends on the interfaces capacity.
                        Setting rate to 0 turns it to listening only mode while
                        reporting on incoming packets
                        Default: 1 MPPS

  --v4only, -4          Generate only IPv4 packets from the Internet towards lwaftr

  --v6only, -6          Generate only IPv6 packets from B4 to lwaftr

  --duration DURATION   Run for DURATION seconds.
			Default: unlimited

  -V, --verbose         Display verbose link information every second

  -h, --help            Print usage information.


This tool generates two types of traffic according to RFC7596:

 - B4 IPv4-in-IPv6 traffic towards lwAFTR (left to right)
 - Internet IPv4 to IPv4 traffic towards lwAFTR (right to left)

Topology From RFC7596, Figure 1:

+--------+   +---------+  IPv4-in-IPv6  +------+   +-------------+
|IPv4 LAN|---|lwB4/NAPT|================|lwAFTR|---|IPv4 Internet|
+--------+   +---------+                +------+   +-------------+
lw4o6 NAPT model: subscriber state in the lwAFTR, NAPT state in the lwB4


Example 1: Measure performance of single stick LWAFTR (handling IPv4 and IPv6
traffic over a single interface). Packetblaster lwaftr generates 50% IPv4 and
50% IPv6 encapsulated traffic of IMIX line traffic:

  $ sudo ./snabb packetblaster lwaftr --rate 3.2 --count 100000 --pci 0000:05:00.0
  packetblaster lwaftr: Sending 1000000 clients at 3.200 MPPS to 0000:05:00.0

  IPv6: 2001:db8:: > 2001:db8:ffff::100: 10.0.0.0:1024 > 8.8.8.8:12345
        source IPv6 and source IPv4/Port adjusted per client
  IPv6 packet sizes: 104,104,104,104,104,104,104,634,634,634,1540

  IPv4: 8.8.8.8:12345 > 10.0.0.0:1024
        destination IPv4 and Port adjusted per client
  IPv4 packet sizes: 64,64,64,64,64,64,64,594,594,594,1500

  v6+v4: 1.416+1.416 = 2.833 MPPS, 4.445+3.983 = 8.428 Gbps, lost 190697 pkts
  v6+v4: 1.574+1.574 = 3.148 MPPS, 4.949+4.446 = 9.395 Gbps, lost 46 pkts
  v6+v4: 1.574+1.574 = 3.148 MPPS, 4.950+4.446 = 9.395 Gbps, lost 0 pkts
  v6+v4: 1.574+1.574 = 3.148 MPPS, 4.950+4.446 = 9.395 Gbps, lost 0 pkts
  v6+v4: 1.574+1.574 = 3.148 MPPS, 4.950+4.446 = 9.395 Gbps, lost 0 pkts
  v6+v4: 1.574+1.574 = 3.148 MPPS, 4.950+4.446 = 9.395 Gbps, lost 0 pkts
  v6+v4: 1.574+1.574 = 3.148 MPPS, 4.950+4.446 = 9.395 Gbps, lost 0 pkts


Example 2: Uni-directional througput test with two instances. 
Run one client1 with 0 MPPS and on client2 on the other end of the wire
with the desired packet rate. The first instance will report on received
traffic:

  client1$ sudo ./snabb packetblaster lwaftr --rate 0 --pci 0000:05:00 --size 40
  packetblaster lwaftr: Sending 1 clients at 0.000 MPPS to 0000:05:00.0

  IPv6: 2001:db8:: > 2001:db8:ffff::100: 10.0.0.0:1024 > 8.8.8.8:12345
        source IPv6 and source IPv4/Port adjusted per client
  IPv6 packet sizes: 80

  IPv4: 8.8.8.8:12345 > 10.0.0.0:1024
        destination IPv4 and Port adjusted per client
  IPv4 packet sizes: 40

  v6+v4: 2.364+2.370 = 4.734 MPPS, 1.778+1.137 = 2.915 Gbps, lost 1513191 pkts
  v6+v4: 2.499+2.499 = 4.999 MPPS, 1.880+1.200 = 3.079 Gbps, lost 1073 pkts
  v6+v4: 2.500+2.500 = 5.000 MPPS, 1.880+1.200 = 3.080 Gbps, lost 0 pkts
  v6+v4: 2.500+2.500 = 4.999 MPPS, 1.880+1.200 = 3.080 Gbps, lost 633 pkts
  v6+v4: 2.500+2.500 = 5.000 MPPS, 1.880+1.200 = 3.080 Gbps, lost 0 pkts
  v6+v4: 2.500+2.500 = 5.000 MPPS, 1.880+1.200 = 3.080 Gbps, lost 54 pkts
  v6+v4: 2.500+2.500 = 5.000 MPPS, 1.880+1.200 = 3.080 Gbps, lost 0 pkts
  v6+v4: 2.500+2.500 = 5.000 MPPS, 1.880+1.200 = 3.080 Gbps, lost 0 pkts
  v6+v4: 2.500+2.500 = 5.000 MPPS, 1.880+1.200 = 3.080 Gbps, lost 0 pkts
  v6+v4: 2.500+2.500 = 5.000 MPPS, 1.880+1.200 = 3.080 Gbps, lost 0 pkts

  client2$ sudo ./snabb packetblaster lwaftr --rate 5 --size 40 --pci 0000:04:00.0
  packetblaster lwaftr: Sending 1 clients at 5.000 MPPS to 0000:04:00.0

  IPv6: 2001:db8:: > 2001:db8:ffff::100: 10.0.0.0:1024 > 8.8.8.8:12345
        source IPv6 and source IPv4/Port adjusted per client
  IPv6 packet sizes: 80

  IPv4: 8.8.8.8:12345 > 10.0.0.0:1024
        destination IPv4 and Port adjusted per client
  IPv4 packet sizes: 40

  v6+v4: 0.000+0.000 = 0.000 MPPS, 0.000+0.000 = 0.000 Gbps, lost 0 pkts
  v6+v4: 0.000+0.000 = 0.000 MPPS, 0.000+0.000 = 0.000 Gbps, lost 0 pkts
  v6+v4: 0.000+0.000 = 0.000 MPPS, 0.000+0.000 = 0.000 Gbps, lost 0 pkts
  v6+v4: 0.000+0.000 = 0.000 MPPS, 0.000+0.000 = 0.000 Gbps, lost 0 pkts
  v6+v4: 0.000+0.000 = 0.000 MPPS, 0.000+0.000 = 0.000 Gbps, lost 0 pkts
  v6+v4: 0.000+0.000 = 0.000 MPPS, 0.000+0.000 = 0.000 Gbps, lost 0 pkts


Example with Linux tap interface:

  $ sudo ip tuntap add dev tap0 mode tap
  $ sudo ifconfig tap0 mtu 9000 up
  $ sudo tcpdump -n -i tap0 -e -s 1500 -c 12 &
  $ sudo ./snabb packetblaster lwaftr --rate 0.001 --pci tap0 -v4only -D 1
  packetblaster lwaftr: Sending 1 clients at 0.001 MPPS to tap0

  IPv4: 8.8.8.8:12345 > 10.0.0.0:1024
        destination IPv4 and Port adjusted per client
  IPv4 packet sizes: 64,64,64,64,64,64,64,594,594,594,1500

  14:04:43.572712 00:00:00:00:00:00 > 00:00:00:00:00:00, ethertype IPv4 (0x0800), length 78: 8.8.8.8.12345 > 0.0.0.0.1024: UDP, length 28
  14:04:43.572733 00:00:00:00:00:00 > 00:00:00:00:00:00, ethertype IPv4 (0x0800), length 78: 8.8.8.8.12345 > 0.0.0.0.1024: UDP, length 28
  14:04:43.572741 00:00:00:00:00:00 > 00:00:00:00:00:00, ethertype IPv4 (0x0800), length 78: 8.8.8.8.12345 > 0.0.0.0.1024: UDP, length 28
  14:04:43.572749 00:00:00:00:00:00 > 00:00:00:00:00:00, ethertype IPv4 (0x0800), length 78: 8.8.8.8.12345 > 0.0.0.0.1024: UDP, length 28
  14:04:43.572756 00:00:00:00:00:00 > 00:00:00:00:00:00, ethertype IPv4 (0x0800), length 78: 8.8.8.8.12345 > 0.0.0.0.1024: UDP, length 28
  14:04:43.572780 00:00:00:00:00:00 > 00:00:00:00:00:00, ethertype IPv4 (0x0800), length 78: 8.8.8.8.12345 > 0.0.0.0.1024: UDP, length 28
  14:04:43.572788 00:00:00:00:00:00 > 00:00:00:00:00:00, ethertype IPv4 (0x0800), length 78: 8.8.8.8.12345 > 0.0.0.0.1024: UDP, length 28
  14:04:43.572866 00:00:00:00:00:00 > 00:00:00:00:00:00, ethertype IPv4 (0x0800), length 608: 8.8.8.8.12345 > 0.0.0.0.1024: UDP, length 558
  14:04:43.573019 00:00:00:00:00:00 > 00:00:00:00:00:00, ethertype IPv4 (0x0800), length 608: 8.8.8.8.12345 > 0.0.0.0.1024: UDP, length 558
14:04:43.573161 00:00:00:00:00:00 > 00:00:00:00:00:00, ethertype IPv4 (0x0800), length 608: 8.8.8.8.12345 > 0.0.0.0.1024: UDP, length 558
  14:04:43.573297 00:00:00:00:00:00 > 00:00:00:00:00:00, ethertype IPv4 (0x0800), length 1514: 8.8.8.8.12345 > 0.0.0.0.1024: UDP, length 1464
  14:04:43.573430 00:00:00:00:00:00 > 00:00:00:00:00:00, ethertype IPv4 (0x0800), length 78: 8.8.8.8.12345 > 0.0.0.0.1024: UDP, length 28


Example of using it in place of the removed `lwaftr generator` command:

  $ sudo ./snabb packetblaster lwaftr \
    --src_mac 02:02:02:02:02:02 --dst_mac 02:42:df:27:05:00 \
    --b4 2001:db8::40,193.5.1.100,1024 --aftr 2001:db8:ffff::100 \
    --count 60000 --pcap lwaftr-traffic.pcap --size 550
  packetblaster lwaftr: Sending 60000 clients at 1.000 MPPS to lwaftr-traffic.pcap

  IPv6: 2001:db8::40 > 2001:db8:ffff::100: 193.5.1.100:1024 > 8.8.8.8:12345
        source IPv6 and source IPv4/Port adjusted per client
  IPv6 packet sizes: 590

  IPv4: 8.8.8.8:12345 > 193.5.1.100:1024
        destination IPv4 and Port adjusted per client
  IPv4 packet sizes: 550
  v6+v4: 0.000+0.000 = 0.000000 MPPS, 0.000+0.000 = 0.000000 Gbps, lost nan%
  v6+v4: 0.000+0.000 = 0.000000 MPPS, 0.000+0.000 = 0.000000 Gbps, lost nan%
  v6+v4: 0.000+0.000 = 0.000000 MPPS, 0.000+0.000 = 0.000000 Gbps, lost nan%
  v6+v4: 0.000+0.000 = 0.000000 MPPS, 0.000+0.000 = 0.000000 Gbps, lost nan%
  v6+v4: 0.000+0.000 = 0.000000 MPPS, 0.000+0.000 = 0.000000 Gbps, lost nan%
  v6+v4: 0.000+0.000 = 0.000000 MPPS, 0.000+0.000 = 0.000000 Gbps, lost nan%
  v6+v4: 0.000+0.000 = 0.000000 MPPS, 0.000+0.000 = 0.000000 Gbps, lost nan%
  generated 60000 packets

To split out traffic, postprocess the generated .pcap file with tcpdump:

  $ tcpdump "ip" -r lwaftr-traffic.pcap -w from-inet.pcap
  reading from file lwaftr-traffic.pcap, link-type EN10MB (Ethernet)

To generate VLAN packets, postprocess the .pcap file with tcpreplay:

  $ tcprewrite --enet-vlan=add --enet-vlan-pri=0 \
    --enet-vlan-cfi=0 --enet-vlan-tag=444 \
    --infile=from-inet.pcap --outfile=from-inet-vlan.pcap
