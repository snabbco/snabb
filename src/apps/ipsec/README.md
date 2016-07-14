# IPsec Apps

## AES128gcm (apps.ipsec.esp)

The `AES128gcm` implements an ESP transport tunnel using the AES-GCM-128
cipher. It encrypts packets received on its `decapsulated` port and transmits
them on its `encapsulated` port, and vice-versa. Packets arriving on the
`decapsulated` port must have an IPv6 header, and packets arriving on the
`encapsulated` port must have an IPv6 header followed by an ESP header,
otherwise they will be discarded.

References:

 - `lib.ipsec.esp`

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

### Configuration

The `AES128gcm` app accepts a table as its configuration argument. The
following keys are defined:

— Key **spi**

*Required*. Security Parameter Index. A 32 bit integer.

— Key **key**

*Required*. 20 bytes in form of a hex encoded string.

— Key **replay_window**

*Optional*. Size of the “Anti-Replay Window”. Defaults to 128.
