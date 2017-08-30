#! /usr/bin/env nix-shell
#! nix-shell -i python -p pythonPackages.scapy
# A script for generating N flows with particular packet sizes

from random import *
from scapy.all import *

import argparse

parser = argparse.ArgumentParser(description = "Pcap generator")
parser.add_argument("count", type = int)
parser.add_argument("output", type = str)
parser.add_argument("--size", type = int, nargs = "?", default = 64)
parser.add_argument("--seed", type = int, nargs = "?", default = None)
args = parser.parse_args()

# header sizes
eth_size = 18 # includes CRC 4 octets
ip_size  = 20
udp_size = 8

payload_size = args.size - eth_size - ip_size - udp_size
payload = "0" * payload_size
packets = []

seed(args.seed)

for i in range(0, args.count):
    udp = UDP(sport = randrange(1, 65536), dport = randrange(1, 65536))
    pkt = Ether() / IP() / udp / payload
    packets.append(pkt)

wrpcap(args.output, packets)
