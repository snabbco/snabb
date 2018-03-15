# lwAFTR's alarms

This document describes the alarms defined in the lwAFTR.

An alarm signifies an undesirable state in a resource that requires corrective
action.  An alarm is identified by a triple formed by the fields: `resource`,
`alarm-type-id`, `alarm-type-qualifier`.  The latter value is optional, so it's
empty for most alarms.  As for the `resource`, its value is always the PID of
the worker process running the lwAFTR function.

## Alarms

The lwAFTR function can signal the following alarms:

### Next-hop for IPv4 packets not yet known (ARP)

- alarm-type-id: arp-resolution.
- description:
    Make sure you can resolve external-interface.next-hop.ip address manually.
    If it cannot be resolved, consider setting the MAC address of the next-hop
    directly.  To do it so, set external-interface.next-hop.mac to the value of
    the MAC address.

### Next-hop for IPv6 packets not yet known (NDP)

- alarm-type-id: ndp-resolution.
- description:
    Make sure you can resolve internal-interface.next-hop.ip address manually.
    If it cannot be resolved, consider setting the MAC address of the next-hop
    directly.  To do it so, set internal-interface.next-hop.mac to the value
    of the MAC address.

### Ingress bandwidth exceeds 1e9 bytes/s

- alarm-type-id: ingress-bandwith.
- description:
    Ingress bandwith exceeds 1e9 bytes/s which can cause packet drops.

### Ingress packet rate exceeds 2 MPPS

- alarm-type-id: ingress-packet-rate
- description:
    Ingress packet-rate exceeds 2MPPS which can cause packet drops.

### Ingress packet drop rate exceeds 3333 PPS

- alarm-type-id: ingress-packet-drop
- description:
    More than <threshold> packets.  See https://github.com/snabbco/snabb/blob/master/src/doc/performance-tuning.md
    for performance tuning tips.

### Bad softwire matches more than 20K softwires/s

- alarm-type-id: bad-ipv4-softwires-matches.
- description:
    lwAFTR's bad softwires matches due to non matching destination address for
    incoming packets (IPv4) has reached over 100,000 softwires binding-table.
    Please review your lwAFTR's configuration binding-table.

- alarm-type-id: bad-ipv6-softwires-matches.
- description:
    lwAFTR's bad softwires matches due to non matching source address for
    outgoing packets (IPv6) has reached over 100,000 softwires binding-table.
    Please review your lwAFTR's configuration binding-table."

### Incoming ipv4 fragments over 10 KPPS

- alarm-type-id: incoming-ipv4-fragments
- description:
    More than 10,000 incoming IPv4 fragments per second.

### Incoming ipv6 fragments over 10 KPPS

- alarm-type-id: incoming-ipv6-fragments
- description:
    More than 10,000 incoming IPv6 fragments per second.

### Outgoing ipv4 fragments over 10 KPPS

- alarm-type-id: outgoing-ipv4-fragments
- description:
    More than 10,000 outgoing IPv4 fragments per second.

### Outgoing ipv6 fragments over 10 KPPS

- alarm-type-id: outgoing-ipv6-fragments
- description:
    More than 10,000 outgoing IPv6 fragments per second.

### Ingress filter v4 rejects over 1 MPPS

- alarm-type-id: filtered-packets
- alarm-type-qualifier: ingress-v4
- description:
    More than 1,000,000 packets filtered per second

### Ingress filter v6 rejects over 1 MPPS

- alarm-type-id: filtered-packets
- alarm-type-qualifier: ingress-v6
- description:
    More than 1,000,000 packets filtered per second

### Egress filter v6 rejects over 1 MPPS

- alarm-type-id: filtered-packets
- alarm-type-qualifier: egress-v4
- description:
    More than 1,000,000 packets filtered per second

### Egress filter v6 rejects over 1 MPPS

- alarm-type-id: filtered-packets
- alarm-type-qualifier: egress-v6
- description:
    More than 1,000,000 packets filtered per second

All alarms becomes cleared after the corrective action has been taken.

## Alarm types

Together with alarms, the lwAFTR also defines several alarm types.  Alarm types
are loaded on running the lwAFTR.  They are stored at /alarms/alarm-inventory/type.

The lwAFTR defines the following alarm-types:

- arp-resolution.
- ndp-resolution.
- ingress-bandwith.
- ingress-packet-rate.
- ingress-packet-drop.
- bad-ipv4-softwires-matches.
- bad-ipv6-softwires-matches.
- outgoing-ipv6-fragments.
- outgoing-ipv4-fragments.
- incoming-ipv6-fragments.
- incoming-ipv4-fragments.
- filtered-packets/ingress-ipv4.
- filtered-packets/ingress-ipv6.
- filtered-packets/egresss-ipv4.
- filtered-packets/egresss-ipv6.
