### Encapsulating Security Payload (lib.ipsec.esp)

The `lib.ipsec.esp` module contains two classes `esp_v6_encrypt` and
`esp_v6_decrypt` which implement implement packet encryption and
decryption with IPsec ESP using the AES-GCM-128 cipher in IPv6 transport
mode. Packets are encrypted with the key and salt provided to the classes
constructors. These classes do not implement any key exchange protocol.

The encrypt class accepts IPv6 packets and inserts a new [ESP
header](https://en.wikipedia.org/wiki/IPsec#Encapsulating_Security_Payload)
between the outer IPv6 header and the inner protocol header (e.g. TCP,
UDP, L2TPv3) and also encrypts the contents of the inner protocol
header. The decrypt class does the reverse: it decrypts the inner
protocol header and removes the ESP protocol header.

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

References:

- [IPsec Wikipedia page](https://en.wikipedia.org/wiki/IPsec).
- [RFC 4303](https://tools.ietf.org/html/rfc4303) on IPsec ESP.
- [RFC 4106](https://tools.ietf.org/html/rfc4106) on using AES-GCM with IPsec ESP.
- [LISP Data-Plane Confidentiality](https://tools.ietf.org/html/draft-ietf-lisp-crypto-02) example of a software layer above these apps that includes key exchange.

— Method **esp_v6_encrypt:new** *config*

— Method **esp_v6_decrypt:new** *config*

Returns a new encryption/decryption context respectively. *Config* must a
be a table with the following keys:

* `mode` - Encryption mode (string). The only accepted value is the
  string `"aes-128-gcm"`.
* `spi` - A 32 bit integer denoting the “Security Parameters Index” as
  specified in RFC 4303.
* `key` - Hexadecimal string of 32 digits (two digits for each byte) that
  denotes a 128-bit AES key as specified in RFC 4106.
* `salt` - Hexadecimal string of eight digits (two digits for each byte) that
  denotes four bytes of salt as specified in RFC 4106.
* `window_size` - *Optional*. Minimum width of the window in which out of order
  packets are accepted as specified in RFC 4303. The default is 128.
  (`esp_v6_decrypt` only.)
* `resync_threshold` - *Optional*. Number of consecutive packets allowed to
  fail decapsulation before attempting “Re-synchronization” as specified in
  RFC 4303. The default is 1024. (`esp_v6_decrypt` only.)
* `resync_attempts` - *Optional*. Number of attempts to re-synchronize
  a packet that triggered “Re-synchronization” as specified in RFC 4303. The
  default is 8. (`esp_v6_decrypt` only.)
* `auditing` - *Optional.* A boolean value indicating whether to enable or
  disable “Auditing” as specified in RFC 4303. The default is `nil` (no
  auditing). (`esp_v6_decrypt` only.)

— Method **esp_v6_encrypt:encapsulate** *packet*

Encapsulates *packet* and encrypts its payload. Returns `true` on success and
`false` otherwise.

— Method **esp_v6_decrypt:decapsulate** *packet*

Decapsulates *packet* and decrypts its payload. Returns `true` on success and
`false` otherwise.
