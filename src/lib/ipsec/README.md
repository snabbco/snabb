### Encapsulating Security Payload (lib.ipsec.esp)

The `lib.ipsec.esp` module contains two classes `encrypt` and `decrypt` which
implement packet encryption and decryption with IPsec ESP in both tunnel and
transport modes. Currently, the only supported cipher is AES-GCM with 128‑bit
keys, 4 bytes of salt, and a 16 byte authentication code. These classes do not
implement any key exchange protocol.

Note: the classes in this module do not reject IP fragments of any sort.

References:

- [IPsec Wikipedia page](https://en.wikipedia.org/wiki/IPsec).
- [RFC 4303](https://tools.ietf.org/html/rfc4303) on IPsec ESP.
- [RFC 4106](https://tools.ietf.org/html/rfc4106) on using AES-GCM with IPsec ESP.
- [LISP Data-Plane Confidentiality](https://tools.ietf.org/html/draft-ietf-lisp-crypto-02) example of a software layer above these apps that includes key exchange.

— Method **encrypt:new** *config*

— Method **decrypt:new** *config*

Returns a new encryption/decryption context respectively. *Config* must a
be a table with the following keys:

* `aead` - AEAD identifier (string). The only accepted value is
  `"aes-gcm-16-icv"` (AES-GCM with a 16 byte ICV).
* `spi` - A 32 bit integer denoting the “Security Parameters Index” as
  specified in RFC 4303.
* `key` - Hexadecimal string of 32 digits (two digits for each byte, most
  significant digit first) that denotes 16 bytes of high-entropy key material
  as specified in RFC 4106.
* `salt` - Hexadecimal string of eight digits (two digits for each byte) that
  denotes four bytes of salt as specified in RFC 4106.
* `window_size` - *Optional*. Minimum width of the window in which out of order
  packets are accepted as specified in RFC 4303. The default is 128.
  (`decrypt` only.)
* `resync_threshold` - *Optional*. Number of consecutive packets allowed to
  fail decapsulation before attempting “Re-synchronization” as specified in
  RFC 4303. The default is 1024. (`decrypt` only.)
* `resync_attempts` - *Optional*. Number of attempts to re-synchronize
  a packet that triggered “Re-synchronization” as specified in RFC 4303. The
  default is 8. (`decrypt` only.)
* `auditing` - *Optional.* A boolean value indicating whether to enable or
  disable “Auditing” as specified in RFC 4303. The default is `nil` (no
  auditing). (`decrypt` only. Note: source address, destination address and
  flow ID are only logged when using `decapsulate_transport6`.)

#### Tunnel mode

In tunnel mode, encapsulation accepts packets of any format and wraps them in
an ESP frame, encrypting the original packet contents. Decapsulation reverses
the process: it removes the ESP frame and returns the original input packet.

    DIAGRAM: ESP-Tunnel
         BEFORE ENCAPSULATION
    +-------------+------------+
    | orig IP Hdr |            |
    |(any options)|  Payload   |
    +-------------+------------+
    
         AFTER ENCAPSULATION
    +-----+-------------+------------+---------+----+
    | ESP | orig IP Hd  |            |   ESP   | ESP|
    | Hdr |(any options)|  Payload   | Trailer | ICV|
    +-----+-------------+------------+---------+----+
           <------------encryption------------>
     <---------------integrity---------------->


— Method **encrypt:encapsulate_tunnel** *packet*, *next_header*

Encapsulates *packet* and encrypts its payload. The ESP header’s *Next Header*
field is set to *next_header*. Takes ownership of *packet* and returns a new
packet.

— Method **decrypt:decapsulate_transport6** *packet*

Decapsulates *packet* and decrypts its payload. On success, takes ownership of
*packet* and returns a new packet and the value of the ESP header’s
*Next Header* field. Otherwise returns `nil`.


#### Transport mode

In transport mode, encapsulation accepts IPv6 packets and inserts a new
ESP header between the outer IPv6 header and the inner protocol header (e.g.
TCP, UDP, L2TPv3) and also encrypts the contents of the inner protocol header.
Decapsulation does the reverse: it decrypts the inner protocol header and
removes the ESP protocol header. In this mode it is expected that an Ethernet
header precedes the outer IPv6 header.

    DIAGRAM: ESP-Transport
         BEFORE ENCAPSULATION
    +-----------+-------------+------------+
    |orig Ether‑| orig IP Hdr |            |
    |net Hdr    |(any options)|  Payload   |
    +-----------+-------------+------------+
    
         AFTER ENCAPSULATION
    +-----------+-------------+-----+------------+---------+----+
    |orig Ether‑| orig IP Hd  | ESP |            |   ESP   | ESP|
    |net Hdr    |(any options)| Hdr |  Payload   | Trailer | ICV|
    +-----------+-------------+-----+------------+---------+----+
                                     <-----encryption----->
                               <---------integrity-------->


— Method **encrypt:encapsulate_transport6** *packet*

Encapsulates *packet* and encrypts its payload. On success, takes ownership of
*packet* and returns a new packet. Otherwise returns `nil`.

— Method **decrypt:decapsulate_transport6** *packet*

Decapsulates *packet* and decrypts its payload. On success, takes ownership of
*packet* and returns a new packet. Otherwise returns `nil`.
