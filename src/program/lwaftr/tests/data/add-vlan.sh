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
    arp_reply_send.pcap
    arp_request_recv.pcap
    arp_request_send.pcap
    decap-ipv4-nohair.pcap
    decap-ipv4.pcap
    icmpv4-dst-host-unreachable-ip-bound-port-unbound.pcap
    icmpv4-dst-host-unreachable.pcap
    icmpv4-time-expired.pcap
    incoming-icmpv4-34toobig.pcap
    incoming-icmpv4-echo-reply.pcap
    incoming-icmpv4-echo-request-invalid-icmp-checksum.pcap
    incoming-icmpv4-echo-request-unbound.pcap
    incoming-icmpv4-echo-request.pcap
    regressiontest-endaddr-v4-input.pcap
    response-ipv4-icmp31-inet.pcap
    response-ipv4-icmp34-inet.pcap
    tcp-afteraftr-ipv6-wrongiface.pcap  
    tcp-frominet-bound-2734.pcap
    tcp-frominet-bound-ttl1.pcap
    tcp-frominet-bound.pcap
    tcp-frominet-bound1494-DF.pcap
    tcp-frominet-bound1494.pcap
    tcp-frominet-ip-bound-port-unbound.pcap
    tcp-frominet-trafficclass.pcap
    tcp-frominet-unbound.pcap
    tcp-ipv4-2ipv6frags-reassembled.pcap
    tcp-ipv4-2ipv6frags-reassembled-1p.pcap
    tcp-ipv4-3frags-bound.pcap
    tcp-ipv4-3frags-bound-reversed.pcap
    tcp-ipv4-toinet-2fragments.pcap
    tcp-ipv4-toinet-3fragments.pcap
    udp-afteraftr-ipv4-3frags.pcap
    udp-afteraftr-reassembled-ipv4.pcap
    udp-frominet-3frag-bound.pcap
    udp-frominet-bound.pcap
    ping-v4.pcap
    ping-v4-ttl-32.pcap
    ping-v4-reply.pcap
    ping-v4-and-data.pcap
)

V6=(
    hairpinned-icmpv4-echo-reply.pcap
    hairpinned-icmpv4-echo-reply-from-aftr.pcap
    hairpinned-icmpv4-echo-request.pcap
    hairpinned-icmpv4-echo-request-from-aftr.pcap
    hairpinned-icmpv4-echo-request-unbound.pcap
    icmpv6-nogress-ip-bound-port-unbound.pcap
    icmpv6-nogress.pcap
    incoming-icmpv6-13dstaddressunreach-inet-OPE.pcap
    incoming-icmpv6-20pkttoobig-inet-OPE.pcap
    incoming-icmpv6-30hoplevelexceeded-hairpinned-OPE.pcap
    incoming-icmpv6-30hoplevelexceeded-inet-OPE.pcap
    incoming-icmpv6-31fragreassemblytimeexceeded-inet-OPE.pcap
    incoming-icmpv6-43paramprob-inet-OPE.pcap
    ipv6-tunneled-incoming-icmpv4-34toobig.pcap
    ipv6-tunneled-incoming-icmpv4-echo-reply.pcap
    ipv6-tunneled-incoming-icmpv4-echo-request.pcap
    ndp_incoming_ns_secondary.pcap
    ndp_getna_compound.pcap
    ndp_incoming_ns.pcap
    ndp_incoming_ns_nonlwaftr.pcap
    ndp_ns_and_recap.pcap
    ndp_outgoing_ns.pcap
    ndp_outgoing_solicited_na.pcap
    ndp_without_dst_eth_compound.pcap
    recap-customBR-IPs-ipv6.pcap
    recap-fromcustom-BRIP-ipv6.pcap
    recap-ipv6.pcap
    recap-ipv6-n64.pcap
    recap-tocustom-BRIP-ipv6.pcap
    regressiontest-endaddr-v6-output.pcap
    regressiontest-signedntohl-frags.pcap
    regressiontest-signedntohl-frags-output.pcap
    response-ipv6-tunneled-icmpv4_31-tob4.pcap
    tcp-afteraftr-ipv6-2frags.pcap
    tcp-afteraftr-ipv6-3frags.pcap
    tcp-afteraftr-ipv6-reassembled.pcap
    tcp-afteraftr-ipv6-trafficclass.pcap
    tcp-afteraftr-ipv6.pcap
    tcp-frominet-bound-wrongiface.pcap
    tcp-fromb4-customBRIP-tob4-ipv6.pcap
    tcp-fromb4-customBRIP1-tob4-customBRIP2-ipv6.pcap
    tcp-fromb4-ipv6-bound-port-unbound.pcap
    tcp-fromb4-ipv6-unbound.pcap
    tcp-fromb4-ipv6.pcap
    tcp-fromb4-tob4-customBRIP-ipv6.pcap
    tcp-fromb4-tob4-ipv6.pcap
    tcp-fromb4-tob4-ipv6-n64.pcap
    tcp-ipv6-2frags-bound.pcap
    tcp-ipv6-2frags-bound-reverse.pcap
    tcp-fromb4-tob4-ipv6-ttl-1.pcap
    tcp-fromb4-tob4-ipv6-ttl-1-reply.pcap
    tcp-ipv6-fromb4-toinet-1046.pcap
    tcp-ipv6-fromb4-toinet-1500.pcap
    udp-afteraftr-ipv6-2frags.pcap
    udp-afteraftr-ipv6.pcap
    udp-afteraftr-reassembled-ipv6-2frags.pcap
    udp-fromb4-2frags-bound.pcap
    ping-v6.pcap
    ping-v6-hop-limit-32.pcap
    ping-v6-reply.pcap
    ping-v6-and-data.pcap
)

IPV4_TAG=1092 # 0x444
IPV6_TAG=1638 # 0x666
DIR=vlan

rmdir -f $DIR 2>/dev/null; mkdir $DIR
# Create IPv4 packets tagged
for file in ${V4[@]}; do
    echo "Create $DIR/$file"
    tcprewrite --enet-vlan=add --enet-vlan-pri=0 --enet-vlan-cfi=0  --enet-vlan-tag=$IPV4_TAG --infile=$file --outfile=$DIR/$file
done
# # Create IPv6 packets tagged
for file in ${V6[@]}; do
    echo "Create $DIR/$file"
    tcprewrite --enet-vlan=add --enet-vlan-pri=0 --enet-vlan-cfi=0  --enet-vlan-tag=$IPV6_TAG --infile=$file --outfile=$DIR/$file
done
