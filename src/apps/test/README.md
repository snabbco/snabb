# Test Apps

## Match (apps.test.match)

The `Match` app compares packets received on its input port `rx` with those
received on the reference input port `comparator`, and reports mismatches as
well as packets from `comparator` that were not matched.

    DIAGRAM: Match
                  +----------+
                  |          |
           rx ----*          |
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

*Optional.* If this key is `true` packets from `rx` that do not match the next
packet from `comparator` are ignored. The default is `false`.

— Key **modest**

*Optional.* If this key is `true` unmatched packets from `comparator` are
ignored if at least one packet from ´rx´ was successfully matched. The default
is `false`.


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

— Key **random_payload**

Generate a random payload for each packet in `sizes`.

— Key **packet_id**

Insert the packet number (32bit uint) directly after the ethertype. The packet
number starts at 0 and is sequential on each output link.

— Key **packets**

Emit *packets* (an array of *packets*) instead of synthesizing packets. When
this option is used *src*, *dst*, *sizes*, and *random_payload* are ignored.

## Npackets (apps.test.npackets)

The `Npackets` app allows are most N packets to flow through it. Any further
packets are never dequeued from input.

    DIAGRAM: Npackets
    		+-----------+
input ->     	| Npackets  | -> output
    		+-----------+

### Configuration

The `Npackets` app accepts a table as its configuration argument. The following
keys are defined:

— Key **npackets**
The number of packets to forward, further packets are never dequeued from
input.
