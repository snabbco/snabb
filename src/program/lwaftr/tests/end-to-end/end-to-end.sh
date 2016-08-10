#!/usr/bin/env bash

SNABB_LWAFTR="../../../../snabb lwaftr"
TEST_BASE=../data
TEST_OUT=/tmp
EMPTY=${TEST_BASE}/empty.pcap
COUNTERS=${TEST_BASE}/counters

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

function quit_with_msg {
   echo $1; exit 1
}

function scmp {
    if ! cmp $1 $2 ; then
        ls -l $1
        ls -l $2
        quit_with_msg "$3"
    fi
}

function snabb_run_and_cmp {
   if [ -z $6 ]; then
      echo "not enough arguments to snabb_run_and_cmp"
      exit 1
   fi
   conf=$1; v4_in=$2; v6_in=$3; v4_out=$4; v6_out=$5; counters_path=$6;
   endoutv4="${TEST_OUT}/endoutv4.pcap"; endoutv6="${TEST_OUT}/endoutv6.pcap";
   rm -f $endoutv4 $endoutv6
   ${SNABB_LWAFTR} check \
      $conf $v4_in $v6_in \
      $endoutv4 $endoutv6 $counters_path || quit_with_msg \
         "Failure: ${SNABB_LWAFTR} check $*"
   scmp $v4_out $endoutv4 \
      "Failure: ${SNABB_LWAFTR} check $*"
   scmp $v6_out $endoutv6 \
      "Failure: ${SNABB_LWAFTR} check $*"
   echo "Test passed"
}

echo "Testing: from-internet IPv4 packet found in the binding table."
snabb_run_and_cmp ${TEST_BASE}/icmp_on_fail.conf \
   ${TEST_BASE}/tcp-frominet-bound.pcap ${EMPTY} \
   ${EMPTY} ${TEST_BASE}/tcp-afteraftr-ipv6.pcap \
   ${COUNTERS}/in-1p-ipv4-out-1p-ipv6-1.lua

echo "Testing: from-internet IPv4 packet found in the binding table with vlan tag."
snabb_run_and_cmp ${TEST_BASE}/vlan.conf \
   ${TEST_BASE}/tcp-frominet-bound-vlan.pcap ${EMPTY} \
   ${EMPTY} ${TEST_BASE}/tcp-afteraftr-ipv6-vlan.pcap \
   ${COUNTERS}/in-1p-ipv4-out-1p-ipv6-1.lua

echo "Testing: NDP: incoming NDP Neighbor Solicitation"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${EMPTY} ${TEST_BASE}/ndp_incoming_ns.pcap \
   ${EMPTY} ${TEST_BASE}/ndp_outgoing_solicited_na.pcap \
   ${COUNTERS}/empty.lua

echo "Testing: NDP: incoming NDP Neighbor Solicitation, non-lwAFTR IP"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${EMPTY} ${TEST_BASE}/ndp_incoming_ns_nonlwaftr.pcap \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/empty.lua

echo "Testing: NDP: IPv6 but not eth addr of next IPv6 hop set, do Neighbor Solicitation"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp_withoutmac.conf \
   ${EMPTY} ${EMPTY} \
   ${EMPTY} ${TEST_BASE}/ndp_outgoing_ns.pcap \
   ${COUNTERS}/empty.lua

echo "Testing: ARP: incoming ARP request"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${TEST_BASE}/arp_request_recv.pcap ${EMPTY} \
   ${TEST_BASE}/arp_reply_send.pcap ${EMPTY} \
   ${COUNTERS}/empty.lua

echo "Testing: ARP: IPv4 but not eth addr of next IPv4 hop set, send an ARP request"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp_without_mac4.conf \
   ${EMPTY} ${EMPTY} \
   ${TEST_BASE}/arp_request_send.pcap ${EMPTY} \
   ${COUNTERS}/empty.lua

# mergecap -F pcap -w ndp_without_dst_eth_compound.pcap tcp-fromb4-ipv6.pcap tcp-fromb4-tob4-ipv6.pcap
# mergecap -F pcap -w ndp_ns_and_recap.pcap recap-ipv6.pcap ndp_outgoing_ns.pcap
echo "Testing: NDP: Without receiving NA, next_hop6_mac not set"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp_withoutmac.conf \
   ${EMPTY} ${TEST_BASE}/ndp_without_dst_eth_compound.pcap \
   ${TEST_BASE}/decap-ipv4.pcap ${TEST_BASE}/ndp_outgoing_ns.pcap \
   ${COUNTERS}/ndp-no-na-next-hop6-mac-not-set.lua

# mergecap -F pcap -w ndp_getna_compound.pcap tcp-fromb4-ipv6.pcap \
# ndp_incoming_solicited_na.pcap tcp-fromb4-tob4-ipv6.pcap
# mergecap -F pcap -w ndp_ns_and_recap.pcap ndp_outgoing_ns.pcap recap-ipv6.pcap
echo "Testing: NDP: With receiving NA, next_hop6_mac not initially set"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp_withoutmac.conf \
   ${EMPTY} ${TEST_BASE}/ndp_getna_compound.pcap \
   ${TEST_BASE}/decap-ipv4.pcap ${TEST_BASE}/ndp_ns_and_recap.pcap \
   ${COUNTERS}/ndp-no-na-next-hop6-mac-not-set.lua

echo "Testing: IPv6 packet, next hop NA, packet, eth addr not set in configuration."
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp_withoutmac.conf \
   ${EMPTY} ${EMPTY} \
   ${EMPTY} ${TEST_BASE}/ndp_outgoing_ns.pcap \
   ${COUNTERS}/empty.lua

echo "Testing: from-internet IPv4 fragmented packets found in the binding table."
snabb_run_and_cmp ${TEST_BASE}/icmp_on_fail.conf \
   ${TEST_BASE}/tcp-ipv4-3frags-bound.pcap ${EMPTY} \
   ${EMPTY} ${TEST_BASE}/tcp-afteraftr-ipv6-reassembled.pcap \
   ${COUNTERS}/in-1p-ipv4-out-1p-ipv6-2.lua

echo "Testing: traffic class mapping"
snabb_run_and_cmp ${TEST_BASE}/icmp_on_fail.conf \
   ${TEST_BASE}/tcp-frominet-trafficclass.pcap ${EMPTY} \
   ${EMPTY} ${TEST_BASE}/tcp-afteraftr-ipv6-trafficclass.pcap \
   ${COUNTERS}/in-1p-ipv4-out-1p-ipv6-1.lua

echo "Testing: from-internet IPv4 packet found in the binding table, original TTL=1."
snabb_run_and_cmp ${TEST_BASE}/icmp_on_fail.conf \
   ${TEST_BASE}/tcp-frominet-bound-ttl1.pcap ${EMPTY} \
   ${TEST_BASE}/icmpv4-time-expired.pcap ${EMPTY} \
   ${COUNTERS}/tcp-frominet-bound-ttl1.lua

echo "Testing: from-B4 IPv4 fragmentation (2)"
snabb_run_and_cmp ${TEST_BASE}/small_ipv4_mtu_icmp.conf \
   ${EMPTY} ${TEST_BASE}/tcp-ipv6-fromb4-toinet-1046.pcap \
   ${TEST_BASE}/tcp-ipv4-toinet-2fragments.pcap ${EMPTY} \
   ${COUNTERS}/in-1p-ipv6-out-1p-ipv4-1.lua

echo "Testing: from-B4 IPv4 fragmentation (3)"
snabb_run_and_cmp ${TEST_BASE}/small_ipv4_mtu_icmp.conf \
   ${EMPTY} ${TEST_BASE}/tcp-ipv6-fromb4-toinet-1500.pcap \
   ${TEST_BASE}/tcp-ipv4-toinet-3fragments.pcap ${EMPTY} \
   ${COUNTERS}/in-1p-ipv6-out-1p-ipv4-2.lua

echo "Testing: from-internet IPv4 packet found in the binding table, needs IPv6 fragmentation (2)."
snabb_run_and_cmp ${TEST_BASE}/small_ipv6_mtu_no_icmp.conf \
   ${TEST_BASE}/tcp-frominet-bound1494.pcap ${EMPTY} \
   ${EMPTY} ${TEST_BASE}/tcp-afteraftr-ipv6-2frags.pcap \
   ${COUNTERS}/in-1p-ipv4-out-1p-ipv6-3.lua

echo "Testing: from-internet IPv4 packet found in the binding table, needs IPv6 fragmentation (3)."
snabb_run_and_cmp ${TEST_BASE}/small_ipv6_mtu_no_icmp.conf \
   ${TEST_BASE}/tcp-frominet-bound-2734.pcap ${EMPTY} \
   ${EMPTY} ${TEST_BASE}/tcp-afteraftr-ipv6-3frags.pcap \
   ${COUNTERS}/in-1p-ipv4-out-1p-ipv6-4.lua

echo "Testing: IPv6 reassembly (followed by decapsulation)."
snabb_run_and_cmp ${TEST_BASE}/small_ipv6_mtu_no_icmp.conf \
   ${EMPTY} ${TEST_BASE}/tcp-ipv6-2frags-bound.pcap \
   ${TEST_BASE}/tcp-ipv4-2ipv6frags-reassembled.pcap ${EMPTY} \
   ${COUNTERS}/in-1p-ipv6-out-1p-ipv4-3.lua

echo "Testing: from-internet IPv4 packet found in the binding table, needs IPv6 fragmentation, DF set, ICMP-3,4, drop policy."
snabb_run_and_cmp ${TEST_BASE}/small_ipv6_mtu_no_icmp.conf \
   ${TEST_BASE}/tcp-frominet-bound1494-DF.pcap  ${EMPTY} \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/from-inet-ipv4-in-binding-big-packet-df-set-drop.lua

echo "Testing: from-internet IPv4 packet found in the binding table, needs IPv6 fragmentation, DF set, ICMP-3,4, allow policy."
snabb_run_and_cmp ${TEST_BASE}/small_ipv6_mtu_no_icmp_allow.conf \
   ${TEST_BASE}/tcp-frominet-bound1494-DF.pcap  ${EMPTY} \
   ${TEST_BASE}/icmpv4-fromlwaftr-replyto-tcp-frominet-bound1494-DF.pcap ${EMPTY} \
   ${COUNTERS}/from-inet-ipv4-in-binding-big-packet-df-set-allow.lua

echo "Testing: from-internet IPv4 packet NOT found in the binding table, no ICMP."
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${TEST_BASE}/tcp-frominet-unbound.pcap ${EMPTY} \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/in-1p-ipv4-out-none-1.lua

echo "Testing: from-internet IPv4 packet NOT found in the binding table (IPv4 matches, but port doesn't), no ICMP."
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${TEST_BASE}/tcp-frominet-ip-bound-port-unbound.pcap ${EMPTY} \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/in-1p-ipv4-out-none-1.lua

echo "Testing: from-internet IPv4 packet NOT found in the binding table (ICMP-on-fail)."
snabb_run_and_cmp ${TEST_BASE}/icmp_on_fail.conf \
   ${TEST_BASE}/tcp-frominet-unbound.pcap ${EMPTY} \
   ${TEST_BASE}/icmpv4-dst-host-unreachable.pcap ${EMPTY} \
   ${COUNTERS}/in-1p-ipv4-out-1p-icmpv4.lua

echo "Testing: from-internet IPv4 packet NOT found in the binding table (IPv4 matches, but port doesn't) (ICMP-on-fail)."
snabb_run_and_cmp ${TEST_BASE}/icmp_on_fail.conf \
   ${TEST_BASE}/tcp-frominet-ip-bound-port-unbound.pcap ${EMPTY} \
   ${TEST_BASE}/icmpv4-dst-host-unreachable-ip-bound-port-unbound.pcap ${EMPTY} \
   ${COUNTERS}/in-1p-ipv4-out-1p-icmpv4.lua

echo "Testing: from-to-b4 IPv6 packet NOT found in the binding table, no ICMP."
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${EMPTY} ${TEST_BASE}/tcp-afteraftr-ipv6.pcap \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/drop-no-source-softwire-ipv6.lua

echo "Testing: from-b4 to-internet IPv6 packet found in the binding table."
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-ipv6.pcap \
   ${TEST_BASE}/decap-ipv4.pcap ${EMPTY} \
   ${COUNTERS}/in-1p-ipv6-out-1p-ipv4-4.lua

echo "Testing: from-b4 to-internet IPv6 packet found in the binding table with vlan tag."
snabb_run_and_cmp ${TEST_BASE}/vlan.conf \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-ipv6-vlan.pcap \
   ${TEST_BASE}/decap-ipv4-vlan.pcap ${EMPTY} \
   ${COUNTERS}/in-1p-ipv6-out-1p-ipv4-4.lua

echo "Testing: from-b4 to-internet IPv6 packet NOT found in the binding table, no ICMP"
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-ipv6-unbound.pcap \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/in-1p-ipv6-out-none-1.lua

echo "Testing: from-b4 to-internet IPv6 packet NOT found in the binding table, (IPv4 matches, but port doesn't), no ICMP"
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-ipv6-bound-port-unbound.pcap \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/in-1p-ipv6-out-none-1.lua

echo "Testing: from-b4 to-internet IPv6 packet NOT found in the binding table (ICMP-on-fail)"
snabb_run_and_cmp ${TEST_BASE}/icmp_on_fail.conf \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-ipv6-unbound.pcap \
   ${EMPTY} ${TEST_BASE}/icmpv6-nogress.pcap \
   ${COUNTERS}/in-1p-ipv6-out-1p-icmpv6-1.lua

echo "Testing: from-b4 to-internet IPv6 packet NOT found in the binding table (IPv4 matches, but port doesn't) (ICMP-on-fail)"
snabb_run_and_cmp ${TEST_BASE}/icmp_on_fail.conf \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-ipv6-bound-port-unbound.pcap \
   ${EMPTY} ${TEST_BASE}/icmpv6-nogress-ip-bound-port-unbound.pcap \
   ${COUNTERS}/in-1p-ipv6-out-1p-icmpv6-1.lua

echo "Testing: from-to-b4 IPv6 packet, no hairpinning"
# The idea is that with hairpinning off, the packet goes out the inet interface
# and something else routes it back for re-encapsulation. It's not clear why
# this would be desired behaviour, but it's my reading of the RFC.
snabb_run_and_cmp ${TEST_BASE}/no_hairpin.conf \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-tob4-ipv6.pcap \
   ${TEST_BASE}/decap-ipv4-nohair.pcap ${EMPTY} \
   ${COUNTERS}/in-1p-ipv6-out-1p-ipv4-4.lua

echo "Testing: from-to-b4 IPv6 packet, with hairpinning"
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-tob4-ipv6.pcap \
   ${EMPTY} ${TEST_BASE}/recap-ipv6.pcap \
   ${COUNTERS}/from-to-b4-ipv6-hairpin.lua

echo "Testing: from-to-b4 tunneled ICMPv4 ping, with hairpinning"
# Ping from 127:11:12:13:14:15:16:128 / 178.79.150.233+7850 to
# 178.79.150.1, which has b4 address 127:22:33:44:55:66:77:127 and is
# not port-restricted.
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${EMPTY} ${TEST_BASE}/hairpinned-icmpv4-echo-request.pcap \
   ${EMPTY} ${TEST_BASE}/hairpinned-icmpv4-echo-request-from-aftr.pcap \
   ${COUNTERS}/from-to-b4-tunneled-icmpv4-ping-hairpin.lua

echo "Testing: from-to-b4 tunneled ICMPv4 ping reply, with hairpinning"
# As above, but a reply instead.
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${EMPTY} ${TEST_BASE}/hairpinned-icmpv4-echo-reply.pcap \
   ${EMPTY} ${TEST_BASE}/hairpinned-icmpv4-echo-reply-from-aftr.pcap \
   ${COUNTERS}/from-to-b4-tunneled-icmpv4-ping-hairpin.lua

echo "Testing: from-to-b4 tunneled ICMPv4 ping, with hairpinning, unbound"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${EMPTY} ${TEST_BASE}/hairpinned-icmpv4-echo-request-unbound.pcap \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/from-to-b4-tunneled-icmpv4-ping-hairpin-unbound.lua

echo "Testing: from-to-b4 tunneled ICMPv4 ping reply, with hairpinning, port 0 not bound"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${EMPTY} ${TEST_BASE}/hairpinned-icmpv4-echo-reply-unbound.pcap \
   ${EMPTY} ${TEST_BASE}/hairpinned-icmpv4-echo-reply-unbound-from-aftr.pcap \
   ${COUNTERS}/in-1p-ipv6-out-1p-icmpv6-2.lua

echo "Testing: from-to-b4 TCP packet, with hairpinning, TTL 1"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-tob4-ipv6-ttl-1.pcap \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-tob4-ipv6-ttl-1-reply.pcap \
   ${COUNTERS}/in-ipv4-ipv6-out-icmpv4-ipv6-hairpin-1.lua

echo "Testing: from-to-b4 TCP packet, with hairpinning, TTL 1, drop policy"
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-tob4-ipv6-ttl-1.pcap \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/in-ipv4-ipv6-out-icmpv4-ipv6-hairpin-1-drop.lua

echo "Testing: from-to-b4 IPv6 packet, with hairpinning, with vlan tag"
snabb_run_and_cmp ${TEST_BASE}/vlan.conf \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-tob4-ipv6-vlan.pcap \
   ${EMPTY} ${TEST_BASE}/recap-ipv6-vlan.pcap \
   ${COUNTERS}/from-to-b4-ipv6-hairpin.lua

echo "Testing: from-b4 IPv6 packet, with hairpinning, to B4 with custom lwAFTR address"
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-tob4-customBRIP-ipv6.pcap \
   ${EMPTY} ${TEST_BASE}/recap-tocustom-BRIP-ipv6.pcap \
   ${COUNTERS}/from-to-b4-ipv6-hairpin.lua

echo "Testing: from-b4 IPv6 packet, with hairpinning, from B4 with custom lwAFTR address"
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-customBRIP-tob4-ipv6.pcap \
   ${EMPTY} ${TEST_BASE}/recap-fromcustom-BRIP-ipv6.pcap \
   ${COUNTERS}/from-to-b4-ipv6-hairpin.lua

echo "Testing: from-b4 IPv6 packet, with hairpinning, different non-default lwAFTR addresses"
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-customBRIP1-tob4-customBRIP2-ipv6.pcap \
   ${EMPTY} ${TEST_BASE}/recap-customBR-IPs-ipv6.pcap \
   ${COUNTERS}/from-to-b4-ipv6-hairpin.lua

echo "Testing: sending non-IPv6 traffic to the IPv6 interface"
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${TEST_BASE}/tcp-afteraftr-ipv6.pcap ${EMPTY} \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/non-ipv6-traffic-to-ipv6-interface.lua

echo "Testing: sending non-IPv4 traffic to the IPv4 interface"
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${EMPTY} ${TEST_BASE}/tcp-frominet-bound.pcap \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/non-ipv4-traffic-to-ipv4-interface.lua

# Test UDP packets

echo "Testing: from-internet bound IPv4 UDP packet"
snabb_run_and_cmp ${TEST_BASE}/icmp_on_fail.conf \
   ${TEST_BASE}/udp-frominet-bound.pcap ${EMPTY} \
   ${EMPTY} ${TEST_BASE}/udp-afteraftr-ipv6.pcap \
   ${COUNTERS}/in-1p-ipv4-out-1p-ipv6-6.lua

echo "Testing: unfragmented IPv4 UDP -> outgoing IPv6 UDP fragments"
snabb_run_and_cmp ${TEST_BASE}/small_ipv6_mtu_no_icmp.conf \
   ${TEST_BASE}/udp-frominet-bound.pcap ${EMPTY} \
   ${EMPTY} ${TEST_BASE}/udp-afteraftr-ipv6-2frags.pcap \
   ${COUNTERS}/in-1p-ipv4-out-1p-ipv6-6.lua

echo "Testing: IPv6 incoming UDP fragments -> unfragmented IPv4"
snabb_run_and_cmp ${TEST_BASE}/icmp_on_fail.conf \
   ${EMPTY} ${TEST_BASE}/udp-fromb4-2frags-bound.pcap \
   ${TEST_BASE}/udp-afteraftr-reassembled-ipv4.pcap ${EMPTY} \
   ${COUNTERS}/in-1p-ipv6-out-1p-ipv4-5.lua

echo "Testing: IPv6 incoming UDP fragments -> outgoing IPv4 UDP fragments"
snabb_run_and_cmp ${TEST_BASE}/small_ipv4_mtu_icmp.conf \
   ${EMPTY} ${TEST_BASE}/udp-fromb4-2frags-bound.pcap \
   ${TEST_BASE}/udp-afteraftr-ipv4-3frags.pcap ${EMPTY} \
   ${COUNTERS}/in-1p-ipv6-out-1p-ipv4-5.lua

echo "Testing: IPv4 incoming UDP fragments -> outgoing IPv6 UDP fragments"
snabb_run_and_cmp ${TEST_BASE}/small_ipv6_mtu_no_icmp.conf \
   ${TEST_BASE}/udp-frominet-3frag-bound.pcap ${EMPTY} \
   ${EMPTY} ${TEST_BASE}/udp-afteraftr-reassembled-ipv6-2frags.pcap \
   ${COUNTERS}/in-1p-ipv4-out-1p-ipv6-6.lua

# Test ICMP inputs (with and without drop policy)

echo "Testing: incoming ICMPv4 echo request, matches binding table"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${TEST_BASE}/incoming-icmpv4-echo-request.pcap ${EMPTY} \
   ${EMPTY} ${TEST_BASE}/ipv6-tunneled-incoming-icmpv4-echo-request.pcap \
   ${COUNTERS}/in-1p-ipv4-out-1p-ipv6-7.lua

echo "Testing: incoming ICMPv4 echo request, matches binding table, bad checksum"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${TEST_BASE}/incoming-icmpv4-echo-request-invalid-icmp-checksum.pcap ${EMPTY} \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/in-1p-ipv4-out-none-2.lua

echo "Testing: incoming ICMPv4 echo request, matches binding table, dropping ICMP"
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${TEST_BASE}/incoming-icmpv4-echo-request.pcap ${EMPTY} \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/in-1p-ipv4-out-none-3.lua

echo "Testing: incoming ICMPv4 echo request, doesn't match binding table"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${TEST_BASE}/incoming-icmpv4-echo-request-unbound.pcap ${EMPTY} \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/in-1p-ipv4-out-none-4.lua

echo "Testing: incoming ICMPv4 echo reply, matches binding table"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${TEST_BASE}/incoming-icmpv4-echo-reply.pcap ${EMPTY} \
   ${EMPTY} ${TEST_BASE}/ipv6-tunneled-incoming-icmpv4-echo-reply.pcap \
   ${COUNTERS}/in-1p-ipv4-out-1p-ipv6-7.lua

echo "Testing: incoming ICMPv4 3,4 'too big' notification, matches binding table"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${TEST_BASE}/incoming-icmpv4-34toobig.pcap ${EMPTY} \
   ${EMPTY} ${TEST_BASE}/ipv6-tunneled-incoming-icmpv4-34toobig.pcap \
   ${COUNTERS}/in-1p-ipv4-out-1p-ipv6-8.lua

echo "Testing: incoming ICMPv6 1,3 destination/address unreachable, OPE from internet"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${EMPTY} ${TEST_BASE}/incoming-icmpv6-13dstaddressunreach-inet-OPE.pcap \
   ${TEST_BASE}/response-ipv4-icmp31-inet.pcap ${EMPTY} \
   ${COUNTERS}/in-1p-ipv6-out-1p-icmpv4-1.lua

echo "Testing: incoming ICMPv6 2,0 'too big' notification, OPE from internet"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${EMPTY} ${TEST_BASE}/incoming-icmpv6-20pkttoobig-inet-OPE.pcap \
   ${TEST_BASE}/response-ipv4-icmp34-inet.pcap ${EMPTY} \
   ${COUNTERS}/in-1p-ipv6-out-1p-icmpv4-1.lua

echo "Testing: incoming ICMPv6 3,0 hop limit exceeded, OPE from internet"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${EMPTY} ${TEST_BASE}/incoming-icmpv6-30hoplevelexceeded-inet-OPE.pcap \
   ${TEST_BASE}/response-ipv4-icmp31-inet.pcap ${EMPTY} \
   ${COUNTERS}/in-1p-ipv6-out-1p-icmpv4-1.lua

echo "Testing: incoming ICMPv6 3,1 frag reassembly time exceeded, OPE from internet"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${EMPTY} ${TEST_BASE}/incoming-icmpv6-31fragreassemblytimeexceeded-inet-OPE.pcap \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/in-1p-ipv6-out-none-2.lua

echo "Testing: incoming ICMPv6 4,3 parameter problem, OPE from internet"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${EMPTY} ${TEST_BASE}/incoming-icmpv6-43paramprob-inet-OPE.pcap \
   ${TEST_BASE}/response-ipv4-icmp31-inet.pcap ${EMPTY} \
   ${COUNTERS}/in-1p-ipv6-out-1p-icmpv4-1.lua

echo "Testing: incoming ICMPv6 3,0 hop limit exceeded, OPE hairpinned"
snabb_run_and_cmp ${TEST_BASE}/tunnel_icmp.conf \
   ${EMPTY} ${TEST_BASE}/incoming-icmpv6-30hoplevelexceeded-hairpinned-OPE.pcap \
   ${EMPTY} ${TEST_BASE}/response-ipv6-tunneled-icmpv4_31-tob4.pcap \
   ${COUNTERS}/in-1p-ipv6-out-1p-icmpv4-2.lua

# Ingress filters

echo "Testing: ingress-filter: from-internet (IPv4) packet found in binding table (ACCEPT)"
snabb_run_and_cmp ${TEST_BASE}/no_icmp_with_filters_accept.conf \
   ${TEST_BASE}/tcp-frominet-trafficclass.pcap ${EMPTY} \
   ${EMPTY} ${TEST_BASE}/tcp-afteraftr-ipv6-trafficclass.pcap \
   ${COUNTERS}/in-1p-ipv4-out-1p-ipv6-1.lua

echo "Testing: ingress-filter: from-internet (IPv4) packet found in binding table (DROP)"
snabb_run_and_cmp ${TEST_BASE}/no_icmp_with_filters_drop.conf \
   ${TEST_BASE}/tcp-frominet-trafficclass.pcap ${EMPTY} \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/empty.lua

echo "Testing: ingress-filter: from-b4 (IPv6) packet found in binding table (ACCEPT)"
snabb_run_and_cmp ${TEST_BASE}/no_icmp_with_filters_accept.conf \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-ipv6.pcap \
   ${TEST_BASE}/decap-ipv4.pcap ${EMPTY} \
   ${COUNTERS}/in-1p-ipv6-out-1p-ipv4-4.lua

echo "Testing: ingress-filter: from-b4 (IPv6) packet found in binding table (DROP)"
snabb_run_and_cmp ${TEST_BASE}/no_icmp_with_filters_drop.conf \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-ipv6.pcap \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/empty.lua

# Egress filters

echo "Testing: egress-filter: to-internet (IPv4) (ACCEPT)"
snabb_run_and_cmp ${TEST_BASE}/no_icmp_with_filters_accept.conf \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-ipv6.pcap \
   ${TEST_BASE}/decap-ipv4.pcap ${EMPTY} \
   ${COUNTERS}/in-1p-ipv6-out-1p-ipv4-4.lua

echo "Testing: egress-filter: to-internet (IPv4) (DROP)"
snabb_run_and_cmp ${TEST_BASE}/no_icmp_with_filters_drop.conf \
   ${EMPTY} ${TEST_BASE}/tcp-fromb4-ipv6.pcap \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/empty.lua

echo "Testing: egress-filter: to-b4 (IPv4) (ACCEPT)"
snabb_run_and_cmp ${TEST_BASE}/no_icmp_with_filters_accept.conf \
   ${TEST_BASE}/tcp-frominet-trafficclass.pcap ${EMPTY} \
   ${EMPTY} ${TEST_BASE}/tcp-afteraftr-ipv6-trafficclass.pcap \
   ${COUNTERS}/in-1p-ipv4-out-1p-ipv6-1.lua

echo "Testing: egress-filter: to-b4 (IPv4) (DROP)"
snabb_run_and_cmp ${TEST_BASE}/no_icmp_with_filters_drop.conf \
   ${TEST_BASE}/tcp-frominet-trafficclass.pcap ${EMPTY} \
   ${EMPTY} ${EMPTY} \
   ${COUNTERS}/empty.lua

echo "Testing: ICMP Echo to AFTR (IPv4)"
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${TEST_BASE}/ping-v4.pcap ${EMPTY} \
   ${TEST_BASE}/ping-v4-reply.pcap ${EMPTY} \
   ${COUNTERS}/empty.lua

echo "Testing: ICMP Echo to AFTR (IPv4) + data"
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${TEST_BASE}/ping-v4-and-data.pcap ${EMPTY} \
   ${TEST_BASE}/ping-v4-reply.pcap ${TEST_BASE}/tcp-afteraftr-ipv6.pcap \
   ${COUNTERS}/in-1p-ipv4-out-1p-ipv6-1.lua

echo "Testing: ICMP Echo to AFTR (IPv6)"
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${EMPTY} ${TEST_BASE}/ping-v6.pcap \
   ${EMPTY} ${TEST_BASE}/ping-v6-reply.pcap \
   ${COUNTERS}/empty.lua

echo "Testing: ICMP Echo to AFTR (IPv6) + data"
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${EMPTY} ${TEST_BASE}/ping-v6-and-data.pcap \
   ${TEST_BASE}/decap-ipv4.pcap ${TEST_BASE}/ping-v6-reply.pcap \
   ${COUNTERS}/in-1p-ipv6-out-1p-ipv4-4.lua

echo "All end-to-end lwAFTR tests passed."
