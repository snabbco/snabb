# Tap app (apps.tap.tap)

The `Tap` app is used to interact with a Linux [tap](https://www.kernel.org/doc/Documentation/networking/tuntap.txt)
device. Packets transmitted on the `input` port will be sent over the tap
device, and packets that arrive on the tap device can be received on the
`output` port.

    DIAGRAM: Tap
              +-------+
              |       |
    input --->*  Tap  *----> output
              |       |
              +-------+

## Configuration

The `Tap` app accepts a string that identifies an existing tap interface.

The Tap device can be configured using standard Linux tools:

```
ip tuntap add Tap345 mode tap
ip link set up dev Tap345
ip link set address 02:01:02:03:04:08 dev Tap0
```
