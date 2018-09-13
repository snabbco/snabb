# IPsec Apps

## ESP Transport6 and Tunnel6 (apps.ipsec.esp)

The `Transport6` and `Tunnel6` apps implement ESP in transport and tunnel mode
respectively. they encrypts packets received on their `decapsulated` port and
transmit them on their `encapsulated` port, and vice-versa. Packets arriving on
the `decapsulated` port must have Ethernet and IPv6 headers, and packets
arriving on the `encapsulated` port must have an Ethernet and IPv6 headers
followed by an ESP header, otherwise they will be discarded.

    DIAGRAM: Transport6
                   +------------+
    encapsulated   |            |
              ---->* Transport6 *<----
              <----*  Tunnel6   *---->
                   |            |   decapsulated
                   +------------+
    
    encapsulated
              --------\   /----------
              <-------|---/ /------->
                      \-----/      decapsulated

References:

 - `lib.ipsec.esp`

### Configuration

The `Transport6` and `Tunnel6` apps accepts a table as its configuration
argument. The following keys are defined:

— Key **self_ip** (`Tunnel6` only)

*Required*. Source address of the encapsulating IPv6 header.

— Key **nexthop_ip** (`Tunnel6` only)

*Required*. Destination address of the encapsulating IPv6 header.

— Key **aead**

*Optional*. The identifier of the AEAD to use for encryption and
authentication. For now, only the default `"aes-gcm-16-icv"` (AES-GCM with a 16
octet ICV) is supported.

— Key **spi**

*Required*. A 32 bit integer denoting the “Security Parameters Index” as
specified in RFC 4303.

— Key **transmit_key**

*Required*. Hexadecimal string of 32 digits (two digits for each byte) that
denotes a 128-bit AES key as specified in RFC 4106 used for the encryption of
outgoing packets.

— Key **transmit_salt**

*Required*. Hexadecimal string of eight digits (two digits for each byte) that
denotes four bytes of salt as specified in RFC 4106 used for the encryption of
outgoing packets.

— Key **receive_key**

*Required*. Hexadecimal string of 32 digits (two digits for each byte) that
denotes a 128-bit AES key as specified in RFC 4106 used for the decryption of
incoming packets.

— Key **receive_salt**

*Required*. Hexadecimal string of eight digits (two digits for each byte) that
denotes four bytes of salt as specified in RFC 4106 used for the decryption of
incoming packets.

— Key **receive_window**

*Optional*. Minimum width of the window in which out of order packets are
accepted as specified in RFC 4303. The default is 128.

— Key **resync_threshold**

*Optional*. Number of consecutive packets allowed to fail decapsulation before
attempting “Re-synchronization” as specified in RFC 4303. The default is 1024.

— Key **resync_attempts**

*Optional*. Number of attempts to re-synchronize a packet that triggered
“Re-synchronization” as specified in RFC 4303. The default is 8.

— Key **auditing**

*Optional.* A boolean value indicating whether to enable or disable “Auditing”
as specified in RFC 4303. The default is `nil` (no auditing).
