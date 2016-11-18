# IPsec Apps

## AES128gcm (apps.ipsec.esp)

The `AES128gcm` implements ESP in transport mode using the AES-GCM-128
cipher. It encrypts packets received on its `decapsulated` port and transmits
them on its `encapsulated` port, and vice-versa. Packets arriving on the
`decapsulated` port must have an IPv6 header, and packets arriving on the
`encapsulated` port must have an IPv6 header followed by an ESP header,
otherwise they will be discarded.

    DIAGRAM: AES128gcm
                   +-----------+
    encapsulated   |           |
              ---->* AES128gcm *<----
              <----*           *---->
                   |           |   decapsulated
                   +-----------+
    
    encapsulated
              --------\   /----------
              <-------|---/ /------->
                      \-----/      decapsulated

References:

 - `lib.ipsec.esp`

### Configuration

The `AES128gcm` app accepts a table as its configuration argument. The
following keys are defined:

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
