# crafting packets via scapy

The scapy tool can be used to craft packets (http://www.secdev.org/projects/scapy/).
If using scapy, please make sure to run at minimum version 2.3.2 - versions below did not work smoothly with the lw4o6 packets.

For below commands, please have scapy installed and started via "scapy".
Note: if you intend to send crafted packets to wire, start scapy via "sudo" or as root.

## starting scapy
```
lab@cgrafubuntu2:~/cg-ubuntu2/testing1.0$ scapy
INFO: Can't import python gnuplot wrapper . Won't be able to plot.
INFO: Can't import PyX. Won't be able to use psdump() or pdfdump().
INFO: Can't import python Crypto lib. Won't be able to decrypt WEP.
INFO: Can't import python Crypto lib. Disabled certificate manipulation tools
Welcome to Scapy (2.3.2)
>>>
```

### define IP packet**
Scapy allows to craft any layer of a packet. Below variable a_ip defines an IP Header. Scapy will any required field prepopulate if not defined otherwise.
```
a_ip=IP()
```

To see how the actual packets look like, several commands can be used. The list below is not a complete reference:

- ls(pkt)	have the list of fields values
- pkt.summary()	for a one-line summary
- pkt.show()	for a developped view of the packet
- pkt.show2()	same as show but on the assembled packet (checksum is calculated, for instance)

**several options to display the crafted packet**

ls(pkt)
```
>>> ls (a_ip)
version    : BitField (4 bits)         = 4               (4)
ihl        : BitField (4 bits)         = None            (None)
tos        : XByteField                = 0               (0)
len        : ShortField                = None            (None)
id         : ShortField                = 1               (1)
flags      : FlagsField (3 bits)       = 0               (0)
frag       : BitField (13 bits)        = 0               (0)
ttl        : ByteField                 = 64              (64)
proto      : ByteEnumField             = 0               (0)
chksum     : XShortField               = None            (None)
src        : SourceIPField (Emph)      = '127.0.0.1'     (None)
dst        : IPField (Emph)            = '127.0.0.1'     ('127.0.0.1')
options    : PacketListField           = []              ([])
```

pkt.summary()
```
>>> a_ip.summary()
'192.168.1.1 > 127.0.0.1 hopopt'
```

pkt.show()
```
>>> a_ip.show()
###[ IP ]###
  version= 4
  ihl= None
  tos= 0x0
  len= None
  id= 1
  flags=
  frag= 0
  ttl= 64
  proto= hopopt
  chksum= None
  src= 192.168.1.1
  dst= 127.0.0.1
  \options\
  ```
  
  pkt.show2()
  ```
  >>> a_ip.show2()
###[ IP ]###
  version= 4L
  ihl= 5L
  tos= 0x0
  len= 20
  id= 1
  flags=
  frag= 0L
  ttl= 64
  proto= hopopt
  **chksum= 0x3a3f**
  src= 192.168.1.1
  dst= 127.0.0.1
  \options\
  ```
  
## change packet fields
a_ip holds the complete IP-header. Based on the output below the "src" does contain the src-address.
Any part can be changed as seen:
```
>>> a_ip.src='192.168.1.1'
>>> a_ip.show()
###[ IP ]###
  version= 4
  ihl= None
  tos= 0x0
  len= None
  id= 1
  flags=
  frag= 0
  ttl= 64
  proto= hopopt
  chksum= None
  src= 192.168.1.1     <<< got modified via a_ip.src=192.168.1.1
  dst= 127.0.0.1
  \options\
```

## crafting complete ethernet-frame (ICMP echo-request)
Lw4o6 requires to to look into the UDP/TCP ports to define the software the packets belongs to.
For ICMP the icmp-id field is being looked up to assign the correct softwire. Below iptables show how the B4-device is  src-nat'ing subscribers packet by  with overwriting the src udp,tcp and icmp-id field.

**exemplary iptables rules as done by the B4-device**
```
-A POSTROUTING -o mytun -p tcp -j SNAT --to-source 193.5.1.2:1024-2047
-A POSTROUTING -o mytun -p udp -j SNAT --to-source 193.5.1.2:1024-2047
-A POSTROUTING -o mytun -p icmp -j SNAT --to-source 193.5.1.2:1024-2047
```

**ICMP echo-request with icmp-id 1024**
In the initial example only the IP-header is created. Scapy allows as well to define all layers in a single step.
```
>>> a_l2l3=Ether(src='90:e2:ba:94:2a:bc', dst='5c:45:27:15:a0:0d')/IP(src='10.0.1.100',dst='10.10.0.0')/ICMP(type=8, code=0, id=1024)

>>> a_l2l3.show()
###[ Ethernet ]###
  dst= 5c:45:27:15:a0:0d
  src= 90:e2:ba:94:2a:bc
  type= IPv4
###[ IP ]###
     version= 4
     ihl= None
     tos= 0x0
     len= None
     id= 1
     flags=
     frag= 0
     ttl= 64
     proto= icmp
     chksum= None
     src= 10.0.1.100
     dst= 10.10.0.0
     \options\
###[ ICMP ]###
        type= echo-request
        code= 0
        chksum= None
        id= 0x400
        seq= 0x0
>>>
```

## sending the frame to wire
Please make sure you have started scapy as root, otherwise sending the frame will lead into an error (error: [Errno 1] Operation not permitted).
Scapy provides a "send" and "sendp" function. Sendp requires to craft the l2-header accordingly and requires the interface to sent-out the packets.

```
>>> sendp(a_l2l3,iface='p4p1')
.
Sent 1 packets.
```

checking the result via tcpdump
```
lab@cgrafubuntu2:~/cg-ubuntu2/testing1.0$ sudo tcpdump -n -i p4p1 -e
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on p4p1, link-type EN10MB (Ethernet), capture size 262144 bytes
04:33:23.800977 90:e2:ba:94:2a:bc > 5c:45:27:15:a0:0d, ethertype IPv4 (0x0800), length 42: 10.0.1.100 > 10.10.0.0: ICMP echo request, id 1024, seq 0, length 8
```

## crafting lw4o6 encapsulated packet

scapy allows to craft as well the lw4o6 encapsulated packet.
This time a udp-packet with src-port 1024 is crafted:

```
lw4o6=Ether(src='90:e2:ba:94:2a:bc', dst='5c:45:27:15:a0:0d')/IPv6(src='2a02:587:f710::40',dst='2a02:587:f700::100')/IP(src='10.0.1.100',dst='10.10.0.0')/UDP(sport=1024)

>>> lw4o6.summary()
'Ether / IPv6 / IP / UDP 10.0.1.100:1024 > 10.10.0.0:domain'

>>> lw4o6.show()
###[ Ethernet ]###
  dst= 5c:45:27:15:a0:0d
  src= 90:e2:ba:94:2a:bc
  type= IPv6
###[ IPv6 ]###
     version= 6
     tc= 0
     fl= 0
     plen= None
     nh= IP
     hlim= 64
     src= 2a02:587:f710::40
     dst= 2a02:587:f700::100
###[ IP ]###
        version= 4
        ihl= None
        tos= 0x0
        len= None
        id= 1
        flags=
        frag= 0
        ttl= 64
        proto= udp
        chksum= None
        src= 10.0.1.100
        dst= 10.10.0.0
        \options\
###[ UDP ]###
           sport= 1024
           dport= domain
           len= None
           chksum= None
           
```

sending this packet
```
>>> sendp(lw4o6,iface='p4p1')
.
Sent 1 packets.
```

checking the result via tcpdump
```
lab@cgrafubuntu2:~/cg-ubuntu2/testing1.0$ sudo tcpdump -n -i p4p1 -e
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on p4p1, link-type EN10MB (Ethernet), capture size 262144 bytes
04:40:27.745410 90:e2:ba:94:2a:bc > 5c:45:27:15:a0:0d, ethertype IPv6 (0x86dd), length 82: 2a02:587:f710::40 > 2a02:587:f700::100: 10.0.1.100.1024 > 10.10.0.0.53: [|domain]
```


## Fragmentation

### sample python script to create IPv4 and lw4o6 frags
scapy allows to generate overlapping, overwriting, incomplete and just valid fragments.
Below code just generates plain non-overlapping IPv4 and IPv6 fragments. It is important to notice the added Fragmentheader, otherwise scapy will not fragment the packet.

### writing directly to a pcap instead of sending to wire
Below script uses the pcapwriter function to write the fragmented packets directly into a pcap instead of sending them to wire.

```
lab@cgrafubuntu2:~/cg-ubuntu2/testing1.0$ cat send-v4-v6-frags.py
#!/usr/bin/python

from scapy.all import *
payload="A"*500+"B"*500

pktdump = PcapWriter("scapy.pcap", append=True, sync=False)

a_lw4o6=Ether(src='90:e2:ba:94:2a:bc', dst='5c:45:27:15:a0:0d')/IPv6(src='2a02:587:f710::40',dst='2a02:587:f700::100',nh=44)/IPv6ExtHdrFragment(nh=4)/IP(src='10.0.1.100',dst='10.10.0.0')/UDP(sport=1024,dport=2000)/payload
a_ipv4=Ether(src='90:e2:ba:94:2a:bc', dst='5c:45:27:15:a0:0d')/IP(src='10.0.1.100',dst='10.10.0.0')/ICMP(type=8, code=0, id=1024)/payload

a_lw4o6.summary()
a_ipv4.summary()

frags4=fragment(a_ipv4,fragsize=500)
frags6=fragment6(a_lw4o6,500)


# IPv4
counter=1
for fragment4 in frags4:
    print "Packet no#"+str(counter)
    print "==================================================="
    fragment4.show() #displays each fragment
    counter+=1
    #sendp(fragment4,iface='p4p1')   <<< uncomment to sent to wire...
    pktdump.write(fragment4)

# IPv6
counter=1
for fragment6 in frags6:
    print "Packet no#"+str(counter)
    print "==================================================="
    fragment6.show() #displays each fragment
    counter+=1
    #sendp(fragment6,iface='p4p1')   <<< uncomment to sent to wire...
    pktdump.write(fragment6)


```

The resulting IPv6 packet:
```
>>> a_lw4o6.summary()
'Ether / IPv6 / IPv6ExtHdrFragment / IP / UDP 10.0.1.100:1024 > 10.10.0.0:cisco_sccp / Raw'
```

The resulting IPv4 packet
```
>>> a_ipv4.summary()
'Ether / IP / ICMP 10.0.1.100 > 10.10.0.0 echo-request 0 / Raw'
```

**verify generated IPv4 and IPv6 fragments**
When the above script is started, both the IPv4 packet and the IPv6 packet get fragmented and sent to wire:

```
lab@cgrafubuntu2:~/cg-ubuntu2/testing1.0$ tcpdump -n -e -r scapy.pcap
reading from file scapy.pcap, link-type EN10MB (Ethernet)
10:13:30.938939 90:e2:ba:94:2a:bc > 5c:45:27:15:a0:0d, ethertype IPv4 (0x0800), length 538: 10.0.1.100 > 10.10.0.0: ICMP echo request, id 1024, seq 0, length 504
10:13:30.939553 90:e2:ba:94:2a:bc > 5c:45:27:15:a0:0d, ethertype IPv4 (0x0800), length 538: 10.0.1.100 > 10.10.0.0: ip-proto-1
10:13:30.944438 90:e2:ba:94:2a:bc > 5c:45:27:15:a0:0d, ethertype IPv6 (0x86dd), length 494: 2a02:587:f710::40 > 2a02:587:f700::100: frag (0|432) truncated-ip - 596 bytes missing! 10.0.1.100.1024 > 10.10.0.0.2000: UDP, length 1000
10:13:30.945226 90:e2:ba:94:2a:bc > 5c:45:27:15:a0:0d, ethertype IPv6 (0x86dd), length 494: 2a02:587:f710::40 > 2a02:587:f700::100: frag (432|432)
10:13:30.946022 90:e2:ba:94:2a:bc > 5c:45:27:15:a0:0d, ethertype IPv6 (0x86dd), length 226: 2a02:587:f710::40 > 2a02:587:f700::100: frag (864|164)
```

## usecase for scapy
Please see the README.troubleshooting.md. This doc requires pcap-files to run end-to-end tests. Scapy allows to generate such pcaps.



