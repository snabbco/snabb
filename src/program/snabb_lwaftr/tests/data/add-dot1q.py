#! /usr/bin/env python2

import sys
from scapy.all import rdpcap, wrpcap, NoPayload, Ether, Dot1Q

if len(sys.argv) not in (3, 4):
    raise SystemExit("Usage: " + sys.argv[0]
            + " input.pcap output.pcap [vlan-id]")

VLAN_ID = 42
if len(sys.argv) == 4:
    try:
        VLAN_ID = int(sys.argv[3])
    except:
        raise SystemExit("'" + sys.argv[3]
            + "' is not a valid VLAN identifier")

packets = []
for packet in rdpcap(sys.argv[1]):
    layer = packet.firstlayer()
    while not isinstance(layer, NoPayload):
        if 'chksum' in layer.default_fields:
            del layer.chksum
        if type(layer) is Ether:
            # adjust ether type
            layer.type = 0x8100
            # add 802.1q layer between Ether and IP
            dot1q = Dot1Q(vlan=VLAN_ID)
            dot1q.add_payload(layer.payload)
            layer.remove_payload()
            layer.add_payload(dot1q)
            layer = dot1q
        layer = layer.payload
    packets.append(packet)

wrpcap(sys.argv[2], packets)
