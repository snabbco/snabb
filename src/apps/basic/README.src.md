# Basic Apps (apps.basic.basic_apps)

The module *apps.basic.basic_apps* provides apps with general
functionality for use in you app networks.

## Source

The `Source` app is a synthetic packet generator. On each breath it fills
each attached output link with new packets. The packet data is
uninitialized garbage and each packet is 60 bytes long.

    DIAGRAM: Source
    +--------+
    |        |
    |        *---- (any)
    |        |
    | Source *---- (any)
    |        |
    |        *---- (any)
    |        |
    +--------+

## Join

The `Join` app joins together packets from N input links onto one
output link. On each breath it outputs as many packets as possible
from the inputs onto the output.

    DIAGRAM: Join
              +--------+
              |        |
    (any) ----*        |
              |        |
    (any) ----*  Join  *----- out
              |        |
    (any) ----*        |
              |        |
              +--------+

## Sample
The `Sample` app forwards packets every `n`th packet from `input`
to `output` all others are dropped.

    DIAGRAM: Sample
              +--------+
              |        |
    input ----* Sample *---- output
              |        |
              +--------+

## Split

The `Split` app splits packets from multiple inputs across multiple
outputs. On each breath it transfers as many packets as possible from
the input links to the output links.

    DIAGRAM: Split
              +--------+
              |        |
    (any) ----*        *----- (any)
              |        |
    (any) ----* Split  *----- (any)
              |        |
    (any) ----*        *----- (any)
              |        |
              +--------+

## Sink

The `Sink` app receives all packets from any number of input links and
discards them. This can be handy in combination with a `Source`.

    DIAGRAM: Sink
              +--------+
              |        |
    (any) ----*        |
              |        |
    (any) ----*  Sink  |
              |        |
    (any) ----*        |
              |        |
              +--------+

## Tee

The `Tee` app receives all packets from any number of input links and
transfers each received packet to all output links. It can be used to
merge and/or duplicate packet streams

    DIAGRAM: Tee
              +--------+
              |        |
    (any) ----*        *----- (any)
              |        |
    (any) ----*  Tee   *----- (any)
              |        |
    (any) ----*        *----- (any)
              |        |
              +--------+

## Truncate
The `Truncate` app sends all packets received on `input` to `output`
and truncates or zero pads packets to length `n` in the process

    DIAGRAM: Sample
              +----------+
              |          |
    input ----* Truncate *---- output
              |          |
              +----------+

## Repeater

The `Repeater` app collects all packets received from the `input` link
and repeatedly transfers the accumulated packets to the `output`
link. The packets are transmitted in the order they were received.

    DIAGRAM: Repeater
              +----------+
              |          |
              |          |
    input ----* Repeater *----- output
              |          |
              |          |
              +----------+

