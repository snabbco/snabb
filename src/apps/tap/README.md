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

This app accepts either a single string or a table as its
configuration argument.  A single string is equivalent to the default
configuration with the `name` attribute set to the string.

— Key **name**

*Required*.  The name of the tap device.

If the device does not exist yet, which is inferred from the absence
of the directory `/sys/class/net/`**name**, it will be created by the
app and removed when the process terminates.  Such a device is called
_ephemeral_ and its operational state is set to _up_ after creation.

If the device already exists, it is called _persistent_.  The app can
attach to a persistent tap device and detaches from it when it
terminates.  The operational state is not changed.  By default, the
MTU is also not changed by the app, see the **mtu_set** option below.

One manner in which a persistent tap device can be created is by using
the `ip` tool

```
ip tuntap add Tap345 mode tap
ip link set up dev Tap345
ip link set address 02:01:02:03:04:08 dev Tap0
```

— Key **mtu**

*Optional*. The L2 MTU of the device. The default is 1514.

By definition, the L2 MTU includes the size of the L2 header, e.g. 14
bytes in case of Ethernet without VLANs. However, the Linux `ioctl`
methods only expose the L3 (IP) MTU, which does not include the L2
header.  The following configuration options are used to correct this
discrepancy.

— Key **mtu_fixup**

*Optional*. A boolean that indicates whether the **mtu** option should
be corrected for the difference between the L2 and L3 MTU.  The
default is _true_.

— Key **mtu_offset**

*Optional*.  The value by which the **mtu** is reduced when
**mtu_fixup** is set to _true_.  The default is 14.

The resulting MTU is called the _effective_ MTU.

— Key **mtu_set**

*Optional*. Either _nil_ or a boolean that indicates whether the MTU
of the tap device should be set or checked.  If **mtu_set** is _true_,
the MTU of the tap device is set to the effective MTU.  If **mtu_set**
is false, the effective MTU is compared with the current value of the
MTU of the tap device and an error is raised in case of a mismatch.

If **mtu_set** is _nil_, the MTU is set or checked if the tap device
is ephemeral or persistent, respectively.  The rationale is that if
the device is persistent, the entity that created the device is
responsible for the configuration and might not expect or react well
to a change of the MTU.
