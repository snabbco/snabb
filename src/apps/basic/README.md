# Basic Apps (apps.basic.basic_apps)

The module *apps.basic.basic_apps* provides apps with general
functionality for use in you app networks.

## Source

The `Source` app is a synthetic packet generator. On each breath it
outputs 1,000 new packets to each attached output port. The packet
data is uninitialized garbage and each packet is 60 bytes long.

![Source](.images/Source.png)

## Join

The `Join` app joins together packets from N input links onto one
output link. On each breath it outputs as many packets as possible
from the inputs onto the output.

![Join](.images/Join.png)

## Split

The `Split` app splits packets from multiple inputs across multiple
outputs. On each breath it transfers as many packets as possible from
the input links to the output links.

![Split](.images/Split.png)

## Sink

The `Sink` app receives all packets from any number of input links and
discards them. This can be handy in combination with a `Source`.

![Sink](.images/Sink.png)

## Tee

The `Tee` app receives all packets from any number of input links and
transfers each received packet to all output links. It can be used to
merge and/or duplicate packet streams

![Tee](.images/Tee.png)

## Repeater

The `Repeater` app collects all packets received from the `input` link
and repeatedly transfers the accumulated packets to the `output`
link. The packets are transmitted in the order they were received.

![Repeater](.images/Repeater.png)

