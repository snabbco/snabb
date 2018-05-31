# User guide

This guide teaches you how to get SnabbVMX up-and-running, including references
to concepts and terms not covered yet.  Please refer to other sections in this
manual in case of doubt.

## SnabbVMX lwaftr

`snabbvmx lwaftr` is the main program. It sets up the app network design, and
passes it to the Snabb's engine to run it.

```bash
$ sudo ./snabb snabbvmx lwaftr
$ sudo ./snabb snabbvmx lwaftr | head -12
Usage: lwaftr --help

lwaftr --conf <config-file> --id <port-id> --pci <pci-addr> --mac <mac-address> \
       --sock <socket-path> [-D <seconds>] [-v]

Arguments:

  --conf    <config-file>   configuration file for lwaftr service
  --id      <port-id>       port_id for virtio socket
  --pci     <pci-addr>      PCI device number for NIC (or Linux interface name)
  --mac     <mac address>   Ethernet address of virtio interface
  --sock    <socket-path>   Socket path for virtio-user interfaces
```

The example below uses static next-hop resolution, so a VM is not needed.  This
setup is useful to test a lwAFTR data-plane.

**snabbvmx-lwaftr-xe0.cfg**

```lua
return {
   lwaftr = "snabbvmx-lwaftr-xe0.conf",
   ipv6_interface = {
      cache_refresh_interval = 1,
      mtu = 9500,
   },
   ipv4_interface = {
      ipv4_address = "10.0.1.1",
      cache_refresh_interval = 1,
      mtu = 1460,
   },
   settings = {
      vlan = false,
      ingress_drop_monitor = 'flush',
      ingress_drop_threshhold = 100000,
      ingress_drop_wait = 15,
      ingress_drop_interval = 1e8,
   },
}
```

**snabbvmx-lwaftr-xe.conf**

```
binding_table = binding_table.txt.s,
aftr_ipv4_ip = 172.20.1.16,
aftr_ipv6_ip = 2001:db8::1,
aftr_mac_b4_side = 02:42:df:27:05:00,
aftr_mac_inet_side = 02:42:df:27:05:00,
inet_mac = 02:02:02:02:02:02,
ipv4_mtu = 9000,
ipv6_mtu = 9000,
next_hop6_mac = 02:02:02:02:02:02,
vlan_tagging = false,
```

**binding_table.txt.s**

```
psid_map {
    193.5.1.100 { psid_length=6, shift=10 }
}
br_addresses {
    fc00::100
}
softwires {
    { ipv4=193.5.1.100, psid=1, b4=fc00:1:2:3:4:5:0:7e }
    { ipv4=193.5.1.100, psid=2, b4=fc00:1:2:3:4:5:0:7f }
    { ipv4=193.5.1.100, psid=3, b4=fc00:1:2:3:4:5:0:80 }
    { ipv4=193.5.1.100, psid=4, b4=fc00:1:2:3:4:5:0:81 }
    ...
    { ipv4=193.5.1.100, psid=63, b4=fc00:1:2:3:4:5:0:bc }
}
```

Now we are ready to run SnabbVMX:

```bash
$ sudo ./snabb snabbvmx lwaftr --id xe0 --conf snabbvmx-lwaftr-xe0.cfg \
    --pci 82:00.0 --mac 02:42:df:27:05:00
Ring buffer size set to 2048
loading compiled binding table from ./binding_table_60k.txt.s.o
compiled binding table ./binding_table_60k.txt.s.o is up to date.
Hairpinning: yes
nic_xe0 ether 02:42:df:27:05:00
IPv6 fragmentation and reassembly: no
IPv4 fragmentation and reassembly: no
lwAFTR service: enabled
Running without VM (no vHostUser sock_path set)
nh_fwd6: cache_refresh_interval set to 1 seconds
loading compiled binding table from ./binding_table_60k.txt.s.o
compiled binding table ./binding_table_60k.txt.s.o is up to date.
nh_fwd4: cache_refresh_interval set to 1 seconds
Ingress drop monitor: flush (threshold: 100000 packets;
    wait: 15 seconds; interval: 0.01 seconds)
```

Now we should send valid lwAFTR traffic to SnabbVMX. One way of doing it is
using a Snabb tool called **packetblaster**. Packetblaster has a *lwaftr* mode
that generates valid lwAFTR packets for a given binding table configuration.

```bash
$ sudo ./snabb packetblaster lwaftr --src_mac 02:02:02:02:02:02 \
        --dst_mac 02:42:df:27:05:00 --b4 2001:db8::40,10.10.0.0,1024 \
        --aftr 2001:db8:ffff::100 --count 60001 --rate 3.1 \
        --pci 0000:02:00.0
```

## SnabbVMX query

SnabbVMX query prints out all the counters of a SnabbVMX instance in XML format:

```xml
<snabb>
  <instance>
   <id>0</id>
   <name>xe0</name>
   <pid>11958</pid>
   <next_hop_mac_v4>00:00:00:00:00:00</next_hop_mac_v4>
   <next_hop_mac_v6>00:00:00:00:00:00</next_hop_mac_v6>
   <monitor>0.0.0.0</monitor>
   <engine>
     <breaths>67198200</breaths>
     <configs>1</configs>
     <freebits>4663620304544</freebits>
     <freebytes>569220658720</freebytes>
     <frees>1525764372</frees>
   </engine>
   <pci>
   ...
   </pci>
   <apps>
     <lwaftr>
       <drop-all-ipv4-iface-bytes>4488858</drop-all-ipv4-iface-bytes>
       <drop-all-ipv4-iface-packets>12721</drop-all-ipv4-iface-packets>
       <drop-all-ipv6-iface-bytes>4997698</drop-all-ipv6-iface-bytes>
       <in-ipv4-bytes>269348948180</in-ipv4-bytes>
       <in-ipv4-frag-needs-reassembly>0</in-ipv4-frag-needs-reassembly>
       <in-ipv4-frag-reassembled>0</in-ipv4-frag-reassembled>
       <in-ipv4-frag-reassembly-unneeded>0</in-ipv4-frag-reassembly-unneeded>
     </lwaftr>
   </apps>
   <links>
     <vm_v4v6.v4----nh_fwd4.vm>
       <dtime>1476276089</dtime>
       <rxbytes>0</rxbytes>
       <rxpackets>0</rxpackets>
       <txbytes>0</txbytes>
       <txdrop>0</txdrop>
       <txpackets>0</txpackets>
     </vm_v4v6.v4----nh_fwd4.vm>
   </links>
  </instance>
</snabb>
```

It's useful for interacting with other systems in the network.

Snabb's lwAFTR also features a tool that queries lwAFTR's counters: Snabb's
`lwaftr query` is covered in the last section of this chapter.

## SnabbVMX check

`snabbvmx check` is a utility that validates lwAFTR correctness.
SnabbVMX has its own version of it.

```bash
$ sudo ./snabb snabbvmx check
Usage: check [-r] CONF V4-IN.PCAP V6-IN.PCAP V4-OUT.PCAP V6-OUT.PCAP
[COUNTERS.LUA]
```

Using `check` is the step prior to adding a new test to the end-to-end test suite.

**CONF** is a SnabbVMX configuration file, and **V4-IN** and **V6-IN** are the
incoming V4 and V6 interfaces. The tool reads packets from a pcap file. **V4-OUT**
and **V6-OUT** are the resulting packets after the lwAFTR processing. How the
packets are processed depends on the configuration file and the binding table.

Although SnabbVMX works on a single interface, `snabbvmx check` requires that
the packet split is already done and provides a split output too.

If you detected an error in the lwAFTR, the first step is to obtain the
configuration file that SnabbVMX was using, as well as a copy of lwAFTR's
configuration and binding table.  With that information and knowing the error
report (ping to lwAFTR but it doesn't reply, valid softwire packet doesn't get
decapsulated, etc), you craft a hand-made packet that meets the testing case.

Now we can check what the lwAFTR produces:

```bash
sudo ./snabb snabbvmx -r snabbvmx-lwaftr-xe0.cfg ipv4-pkt.pcap empty.pcap \
    /tmp/outv4.pcap /tmp/outv6.pcap counters.lua
```

The flag `-r` generates a counters file.

Check that your output matches what you expect:

```bash
$ tcpdump -qns 0 -ter empty.pcap
reading from file empty.pcap, link-type EN10MB (Ethernet)
```

Checking what values are in the counters can give you a hint about whether
things are working correctly or not.

Tip: packets always arrive only in one interface, but the output might be
empty for both interfaces, non-empty, and empty or non-empty for both cases.

## Other related tools

### Snabb's lwaftr query

Snabb's `lwaftr query` command can be used to print out counter's values of
a running lwAFTR instance (that also includes a SnabbVMX instance).  When
querying a SnabbVMX instance, the instance can be referred to by its `id`.

Counters are useful to debug and understand what data paths are being taken.
Running `snabb lwaftr query <pid>` lists all non-zero counters of a lwAFTR's
instance:

```bash
$ sudo ./snabb lwaftr query xe0
lwAFTR operational counters (non-zero)
drop-all-ipv4-iface-bytes:            7,642,666
drop-all-ipv4-iface-packets:          21,653
drop-all-ipv6-iface-bytes:            8,508,786
drop-all-ipv6-iface-packets:          21,653
drop-no-dest-softwire-ipv4-bytes:     7,642,666
drop-no-dest-softwire-ipv4-packets:   21,653
drop-no-source-softwire-ipv6-bytes:   8,508,786
drop-no-source-softwire-ipv6-packets: 21,653
in-ipv4-bytes:                        458,034,561,846
in-ipv4-packets:                      1,297,289,752
in-ipv6-bytes:                        509,922,361,858
in-ipv6-packets:                      1,297,275,296
ingress-packet-drops:                 5,849,182
out-icmpv4-bytes:                     6,104,782
out-icmpv4-packets:                   21,653
out-icmpv6-bytes:                     8,942,294
out-icmpv6-packets:                   21,653
out-ipv4-bytes:                       458,029,812,134
out-ipv4-packets:                     1,297,275,296
out-ipv6-bytes:                       509,917,643,140
out-ipv6-packets:                     1,297,268,099
```

It is possible to pass a filter expression to query only the matching counters.
The example below prints out only the outgoing related counters.

```bash
$ sudo ./snabb lwaftr query 11958 out
lwAFTR operational counters (non-zero)
out-icmpv4-bytes:                     7,460,356
out-icmpv4-packets:                   26,460
out-icmpv6-bytes:                     10,928,022
out-icmpv6-packets:                   26,460
out-ipv4-bytes:                       559,187,260,900
out-ipv4-packets:                     1,583,779,666
out-ipv6-bytes:                       622,534,239,098
out-ipv6-packets:                     1,583,770,321
```

### Snabb's lwaftr monitor

`lwaftr monitor` is a tool that helps monitoring incoming and outgoing packets
to a lwAFTR.  This feature must be combined with running SnabbVMX with mirroring
enabled.

```bash
$ sudo ./snabb snabbvmx lwaftr --id xe0 --conf snabbvmx-lwaftr-xe0.cfg \
    --pci 82:00.0 --mac 02:42:df:27:05:00 --mirror tap0
```

The `mirror` parameter expects a tap interface.  The interface must be up
in order to receive packets:

```bash
$ sudo ip link set dev tap0 up
```

`lwaftr monitor` is set with a target IPv4 address.  All lwAFTR packets whose
IPv4 source matches the target address will be mirrored to the tap interface.
In addition, monitoring can be set with two special values:

- `all`: mirrors all packets to the tap interface.
- `none`: mirrors nothing to the tap interface.

### Snabb's packetblaster lwaftr

`snabb packetblaster` is a built-in Snabb utility which can blast packets to a
NIC very quickly.  It features several modes: `synth`, `replay` and `lwaftr`.

The `lwaftr` mode is especially suited to generating IPv4 and IPv6 packets that
match a binding table. Example:

```bash
$ sudo ./snabb packetblaster lwaftr --src_mac 02:02:02:02:02:02 \
        --dst_mac 02:42:df:27:05:00 --b4 2001:db8::40,10.10.0.0,1024 \
        --aftr 2001:db8:ffff::100 --count 60001 --rate 3.1 \
        --pci 0000:02:00.0
```

Parameters:

- `src_mac`: Source MAC-Address.
- `dst_mac`: Destination MAC-Address.  Must match a lwAFTR configuration file
MAC address.
- `b4`: IPV6, IPV4 and PORT values of the first softwire.
- `aftr`: IPv6 address of the lwaftr server.  Only one value can be specified.
- `count`: Number of B4 clients to simulate.
- `rate`: Rate in MPPS for the generated traffic.
- `pci`: Interface PCI address.

These are the main parameters to generate valid lwAFTR traffic to a SnabbVMX
instance.  `packetblaster lwaftr` features additional flags and options:
please refer to its section in the Snabb's manual for a more detailed
description.
