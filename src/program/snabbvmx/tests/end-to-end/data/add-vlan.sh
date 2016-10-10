#!/usr/bin/env bash

# https://en.wikipedia.org/wiki/IEEE_802.1Q 
# 802.1q payload:
# | TPID   | PRI   | CFI   | TAG |
# | 0x8100 | 3-bit | 1-bit | 12-bit |

# Intentionally do not add to the list:
# icmpv4-fromlwaftr-replyto-tcp-frominet-bound1494-DF.pcap
# It needs to be 576 bytes, so requires truncation after the VLAN tag is added
# Do not automatically regenerate it.

V4=(
)

V6=(
    "regressiontest-signedntohl-frags.pcap"
)

IPV4_TAG=1092 # 0x444
IPV6_TAG=1638 # 0x666
DIR=vlan

if [[ -d "$DIR" ]]; then
    rm -f "$DIR/*.pcap"
else
    mkdir "$DIR"
fi

# Create IPv4 packets tagged
for file in ${V4[@]}; do
    echo "Create $DIR/$file"
    tcprewrite --enet-vlan=add --enet-vlan-pri=0 --enet-vlan-cfi=0  --enet-vlan-tag=$IPV4_TAG --infile=$file --outfile=$DIR/$file
done
# Create IPv6 packets tagged
for file in ${V6[@]}; do
    echo "Create $DIR/$file"
    tcprewrite --enet-vlan=add --enet-vlan-pri=0 --enet-vlan-cfi=0  --enet-vlan-tag=$IPV6_TAG --infile=$file --outfile=$DIR/$file
done
