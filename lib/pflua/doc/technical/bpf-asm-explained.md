Explanation of BPF asm generated code
-------------------------------------

ETHER PROTO
-----------

Implements: ```ether proto protocol```, ```ip6```, ```arp```, ```rarp```, ```atalk```, ```aarp```, ```decnet```, ```sca```, ```lat```, ```mopdl```, ```moprc```, ```iso```, ```stp```, ```ipx```, ```netbeui```.

Example:

```
> ether proto 1540
```

```
(000) ldh      [12]
(001) jeq      #0x604           jt 2    jf 3
(002) ret      #65535
(003) ret      #0

```

```
> ether proto 100
```

```
(000) ldh      [12]
(001) jgt      #0x5dc           jt 5    jf 2
(002) ldb      [14]
(003) jeq      #0x64            jt 4    jf 5
(004) ret      #65535
(005) ret      #0
```

There are two possible interpretations of an ethernet frame. As an Ethernet II frame or as a 802.3 frame [1].

The type field of an ethernet frame can carry either the **EtherType** identifier or a **Length**. EtherType identifiers start from 0x600 (1536). This means that when the protocol identifier is >=1536, the value in the Type/Length field ({'[ether]', 12, 2 }) is interpreted as protocol type, as we have been doing so far.

When the protocol identifier is <1536 the value in Type/Length field is interpreted as Length. The IEEE 802.3 specification determines that this value cannot be higher than 1500 (maxValidFrame, see [1]). That explains why "ether proto 1500" emits the following BPF asm: (applies to any value <1500)

```
(000) ldh 12 jgt #0x5dc jt 5 jf 2
```

In fact there's a gray area between values 1500 and 1536. They cannot be valid 802.3 frames (length is higher than 1500), but they are not Ethernet frames either (ethertypes should be >=1536). The spec doesn't define what to do and leaves it to the implementators (tcpdump considers anything >1500 as an Ethernet frame) [2].

Once this is clarified, now there's still the question of what's the meaning of the first byte after the Type/Length field, when the Type/Length field is interpreted as Length. In this case (<1500), the frame is interpreted as a 802.3 frame, or derivatives. The derivatives include LLC (802.2) and SNAP which prefix the data field with an LLC header. The article in Wikipedia about 802.3 [3] defines the IEEE 802.3 standard as:

"10BASE5 10 Mbit/s (1.25 MB/s) over thick coax. Same as Ethernet II (above) except Type field is replaced by Length, and an 802.2 LLC header follows the 802.3 header. Based on the CSMA/CD Process".

So the first bytes in the payload field are a 802.2 LLC header. The structure of a LLC data header starts with two eight-bit address fields, called service access points. They are the DSAP (Destination SAP) and SSAP (Source SAP). Possible values for a SAP are:

| Value | Hex | Description |
| 0 | 0x00 | Null LSAP |
| 2 | 0x02 | Individual LLC Sublayer Mgt |
| 3 | 0x03 | Group LLC Sublayer Mgt |
| 4 | 0x04 | SNA Path Control |
| 6 | 0x06 | Reserved for DoD IP |
| 14 | 0x0e | ProWay-LAN |
| 78 | 0x4e | EIA-RS 511 |
| 94 | 0x5e | ISI IP |
| 142 | 0x8e | ProWay-LAN |
| 170 | 0xaa | SNAP Extension Used |
| 224 | 0xe0 | Novell Netware |
| 254 | 0xfe | OSI protocols ISO CLNS IS 8473[2] |
| 255 | 0xff | Global DSAP (cannot be used for SSAP) |

In conclusion, the first byte after the Type/Length field, when the ethernet frame is interpreted as 802.3 data frame, is a SAP. At this level (Link-Layer Control) the concept of SAP is similar to an Ethertype value [4].

What the command ```ether proto protocol``` does when number <1500 is to check the length of the packet and in case it is lower than 1500 compares the first byte after the length ({'[ether]', 14, 1}) against the protocol number.

With regard to SNAP protocol, the structure is the same but adds new fields at the end of the LLC header [5].

[1] Extended Ethernet Frame Size Support https://tools.ietf.org/html/draft-ietf-isis-ext-eth-01)
[2] EtherType http://en.wikipedia.org/wiki/EtherType
[3] IEE_802.3 http://en.wikipedia.org/wiki/IEEE_802.3
[4] SAP Numbers http://www.wildpackets.com/resources/compendium/reference/sap_numbers
[5] SNAP Protocol http://en.wikipedia.org/wiki/Subnetwork_Access_Protocol


ISO
---

Implements: ```iso proto protocol```, ```isis```, ```esis```, ```clnp```.

Example:

```
> clnp
```

```
(000) ldh      [12]
(001) jgt      #0x5dc           jt 7    jf 2
(002) ldh      [14]
(003) jeq      #0xfefe          jt 4    jf 7
(004) ldb      [17]
(005) jeq      #0x81            jt 6    jf 7
(006) ret      #65535
(007) ret      #0
```

The frame contains an encapsulated ISO PDU. This PDU is prepended by a LLC header that identifies the frame encapsulating an ISO PDU. The value 0xFEFE03 is used to identify the frame carries an encapsulated ISO PDU. The first byte of the PDU contains a protocol identifer (CLNP, ISIS, ESIS) [1].

The routed PDU if prefixed by a IEEE 802.2 LLC Header. This header has the following format:

```
+------+------+------+
| DSAP | SSAP | Ctrl |
+------+------+------+
```

Each field is 1 octet. The LLC header value 0xFE-FE-03 identifies that a routed ISO PDU follows. This corresponds to the following BPF-asm:

```
(002) ldh      [14]
(003) jeq      #0xfefe          jt 4    jf 7
```

(03 is not checked, but should be byte [16]).

The routed ISO protocol is identified by a one octet NLPID field that is part of Protocol Data. Protocol identifiers are defined in Appendix C of rfc1483.txt.

```
0x81    ISO CLNP
0x82    ISO ESIS
0x83    ISO ISIS
```

[1] Multiprotocol Encapsulation over ATM Adaptation Layer 5 https://www.ietf.org/rfc/rfc1483.txt.


DECNET
------

Implements: ```decnet src host```, ```decnet dst host```, ```decnet host host```.

Example:

```
> decnet src host 10.12
```

```
(000) ldh      [12]
(001) jeq      #0x6003          jt 2    jf 23
(002) ldb      [16]
(003) and      #0x7
(004) jeq      #0x2             jt 5    jf 7
(005) ldh      [19]
(006) jeq      #0xc28           jt 22   jf 7
(007) ldh      [16]
(008) and      #0xff07
(009) jeq      #0x8102          jt 10   jf 12
(010) ldh      [20]
(011) jeq      #0xc28           jt 22   jf 12
(012) ldb      [16]
(013) and      #0x7
(014) jeq      #0x6             jt 15   jf 17
(015) ldh      [31]
(016) jeq      #0xc28           jt 22   jf 17
(017) ldh      [16]
(018) and      #0xff07
(019) jeq      #0x8106          jt 20   jf 23
(020) ldh      [32]
(021) jeq      #0xc28           jt 22   jf 23
(022) ret      #65535
(023) ret      #0
```

This code checks DECNET Phase IV addresses encapsulated in an ethernet data frame.

There are two possible DECNET Phase IV headers: a long header and a short header [1]. For each case, the generated BPF is the same, but the offset changes. The code generated checks both types of headers.

The first octet of the header is a control field. It has the following format:

```
| P | V | IL | RTS | RQR | Format |
```

   * P: If set, indicates that padding is added to the beginning of the packet.
   * Format: Indicates whether the packet is in long (0x6) or short format (0x2).

Firstly, what the BPF code does is to check whether the packet is in short format. If that's the case, it fetches the source address at 19 and compares it against the address passed as argument (0xc28).

```
(002) ldb      [16]
(003) and      #0x7
(004) jeq      #0x2             jt 5    jf 7
(005) ldh      [19]
(006) jeq      #0xc28           jt 22   jf 7
```

In case the packet were not in short format, it could be the case that, in fact, it was but because there was padding, the test resulted in a false negative. The BPF generated code only considers the case when there's 1 byte of padding [2]. When there's padding the padding is put in front of the header and is indicated by having the top bit set in the first byte and the length of the padding indicated by the remainder first byte [2]. So that means that [16] should be equals to 0x81, and [17] is the control byte. The generated code checks again the control byte is in short format.

```
(007) ldh 16 and #0xff07
(009) jeq #0x8102 jt 10 jf 12
(010) ldh 20 jeq #0xc28 jt 22 jf 12
```

The case for the long header is analog to the explained above but with the only difference that the starting offset is different.

[1] http://books.google.es/books?id=AIRitf5C-QQC&pg=PA229&lpg=PA229&dq=ethernet+%22decnet+header%22+rfc&source=bl&ots=2FXDeh1A7_&sig=7vFM25hs82g_n0Cn3A6qouRpq24&hl=en&sa=X&ei=xtVCVIL8JNPy7AaVzYGwDg&ved=0CCEQ6AEwAA#v=onepage&q=ethernet%20%22decnet%20header%22%20rfc&f=false
[2] libpcap/gencode.c https://github.com/the-tcpdump-group/libpcap/blob/master/gencode.c#L4501
[3] http://books.google.es/books?id=AIRitf5C-QQC&pg=PA238&lpg=PA238&dq=decnet+padding&source=bl&ots=2FXDeh3z9W&sig=WJ4adVfPY9my1T-uByHeP5s91NQ&hl=en&sa=X&ei=Qt1CVK7-Cuzg7Qa6q4CICw&ved=0CCEQ6AEwAA#v=onepage&q=decnet%20padding&f=false

ISIS
----

Implements: ```iih```, ```lsp```, ```snp```, ```csnp```, ```psnp```.

Example:

```
> csnp
```

```
(000) ldh      [12]
(001) jgt      #0x5dc           jt 10   jf 2
(002) ldh      [14]
(003) jeq      #0xfefe          jt 4    jf 10
(004) ldb      [17]
(005) jeq      #0x83            jt 6    jf 10
(006) ldb      [21]
(007) jeq      #0x1a            jt 9    jf 8
(008) jeq      #0x1b            jt 9    jf 10
(009) ret      #65535
(010) ret      #0

```

ISIS is a routing protocol designed to move information efficiently within a computer network, similar to OSPF [1]. ISIS protocols operate at two levels: L1 (intra-area) and L2 (inter-area). ISIS is an ISO protocol [2].

The packets used in IS-IS routing protocol fall into three main classes: (i) Hello Packets; (ii) Link State Packets (LSPs); and (iii) Sequence Number Packets (SNPs) [3].

   i. There are 3 types of Hello packets: L1_IIH, L2_IIH and P2P_IIH.
   ii. There are 2 types of LSPs: L1_LSP, L2_LSP.
   iii. There are 4 types of sequence number packets: L1_CSNP, L2_CSNP, L1_PSNP, L2_PSNP.

The following document describes the structure of an ISIS PDU [4]. The type of ISIS protocol starts at offset 5 [4].

The BPF asm generated is quite simple. It first checks the packet is an ISO packet, and if that's the case inspects offset 5 ([21]) to check whether the PDU matches the correspondent ID. For instance, valid l1 packets include L1_IIH, PTP_IIH, L1_LSP, L1_CSNP and L1_PSNP.

   * L1: L1_IIH , PTP_IIH, L1_LSP, L1_CSNP, L1_PSNP.
   * L2: L2_IIH , PTP_IIH, L2_LSP, L2_CSNP, L2_PSNP.
   * IIH: L1_IIH, L2_IIH, P2P_IIH (3).
   * LSP: L1_LSP, L2_LSP (2).
   * SNP: L1_CSNP, L2_CSNP, L1_PSNP, L2_PSNP (4).
      * CSNP: L1_CSNP, L2_CSNP.
      * PSNP: L1_PSNP, L2_PSNP.
.
[1] http://en.wikipedia.org/wiki/IS-IS
[2] http://wiki.wireshark.org/IsoProtocolFamily
[3] http://www.ietf.org/rfc/rfc1195.txt
[4] http://www.itcertnotes.com/2012/03/is-is-protocol-data-units-pdus.html
