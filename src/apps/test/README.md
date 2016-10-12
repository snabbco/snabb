# Test Apps

## Match (apps.test.match)

The `Match` app compares packets received on its `input` port with those
received on the `comparator` port, and reports mismatches as well as packets
from `comparator` that were not matched.

    DIAGRAM: Match
                  +----------+
                  |          |
        input ----*          |
                  |   Match  |
    comparator ---*          |
                  |          |
                  +----------+

— Method **Match:errors**

Returns the recorded errors as an array of strings.

### Configuration

The `Match` app accepts a table as its configuration argument. The following
keys are defined:

— Key **fuzzy**

*Optional.* If this key is `true` packets from `input` that do not match the
next packet from `comparator` are ignored. The default is `false`.

— Key **modest**

*Optional.* If this key is `true` unmatched packets from `comparator` are
ignored if at least one packet from `input` was successfully matched. The
default is `false`.


## Synth (apps.test.synth)

The `Synth` app generates synthetic packets with Ethernet headers and
alternating payload sizes. On each breath it fills each attached output link
with new packets.

    DIAGRAM: Synth
    +-------+
    |       |
    |       *---- (any)
    |       |
    | Synth *---- (any)
    |       |
    |       *---- (any)
    |       |
    +-------+

### Configuration

The `Synth` app accepts a table as its configuration argument. The following
keys are defined:

— Key **src**

— Key **dst**

Source and destination MAC addresses in human readable from. The default is
`"00:00:00:00:00:00"`.

— Key **sizes**

An array of numbers designating the packet payload sizes. The default is
`{64}`.
