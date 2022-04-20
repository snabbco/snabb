#/usr/bin/env bash

COUNTERS="../data/counters"
EMPTY="../data/empty.pcap"
TEST_INDEX=0

export COUNTERS

function read_column {
    echo "${TEST_DATA[$1]}"
}

function read_column_pcap {
    index=$1
    column="${TEST_DATA[$index]}"
    if [[ ${#column} == 0 ]];  then
        echo "${EMPTY}"
    else
        echo "${TEST_BASE}/$column"
    fi
}

function print_test_name {
    test_name="$(read_column $TEST_INDEX)"
    echo "Testing: $test_name"
}

function read_test_data {
    conf="${TEST_BASE}/$(read_column $((TEST_INDEX + 1)))"
    in_v4=$(read_column_pcap $((TEST_INDEX + 2)))
    in_v6=$(read_column_pcap $((TEST_INDEX + 3)))
    out_v4=$(read_column_pcap $((TEST_INDEX + 4)))
    out_v6=$(read_column_pcap $((TEST_INDEX + 5)))
    counters="${COUNTERS}/$(read_column $((TEST_INDEX + 6)))"
    echo "$conf" "$in_v4" "$in_v6" "$out_v4" "$out_v6" "$counters"
}

function next_test {
    TEST_INDEX=$(($TEST_INDEX + 7))
    if [[ $TEST_INDEX -lt $TEST_SIZE ]]; then
        return 0
    else
        return 1
    fi
}

# Contains an array of test cases.
#
# A test case is a group of 7 data fields, structured as 3 rows:
#  - "test_name"
#  - "lwaftr_conf" "in_v4" "in_v6" "out_v4" "out_v6"
#  - "counters"
#
# Notice spaces and new lines are not taken into account.
TEST_DATA=(
"Regression test: make sure ntohl'd high-bit-set fragment IDs do not crash"
"no_icmp.conf" "" "regressiontest-signedntohl-frags.pcap" "" "regressiontest-signedntohl-frags-output.pcap"
"regressiontest-signedntohl-frags-counters.lua"

"Regression test: make sure end-addr works"
"icmp_endaddr.conf" "regressiontest-endaddr-v4-input.pcap" "" "" "regressiontest-endaddr-v6-output.pcap"
"regressiontest-endaddr.lua"

"from-internet IPv4 packet found in the binding table."
"icmp_on_fail.conf" "tcp-frominet-bound.pcap" "" "" "tcp-afteraftr-ipv6.pcap"
"in-1p-ipv4-out-1p-ipv6-1.lua"

"from-internet IPv4 packet found in the binding table with vlan tag."
"vlan.conf" "tcp-frominet-bound-vlan.pcap" "" "" "tcp-afteraftr-ipv6-vlan.pcap"
"in-1p-ipv4-out-1p-ipv6-1.lua"

"NDP: incoming NDP Neighbor Solicitation"
"tunnel_icmp.conf" "" "ndp_incoming_ns.pcap" "" "ndp_outgoing_solicited_na.pcap"
"nofrag6-sol.lua"

"NDP: incoming NDP Neighbor Solicitation, secondary IP"
"tunnel_icmp.conf" "" "ndp_incoming_ns_secondary.pcap" "" ""
"ndp-secondary.lua"

"NDP: incoming NDP Neighbor Solicitation, non-lwAFTR IP"
"tunnel_icmp.conf" "" "ndp_incoming_ns_nonlwaftr.pcap" "" ""
"nofrag6.lua"

"NDP: IPv6 but not eth addr of next IPv6 hop set, do Neighbor Solicitation"
"tunnel_icmp_withoutmac.conf" "" "" "" "ndp_outgoing_ns.pcap"
"ndp-ns-for-next-hop.lua"

"ARP: incoming ARP request"
"tunnel_icmp.conf" "arp_request_recv.pcap" "" "arp_reply_send.pcap" ""
"nofrag4.lua"

"ARP: IPv4 but not eth addr of next IPv4 hop set, send an ARP request"
"tunnel_icmp_without_mac4.conf" "" "" "arp_request_send.pcap" ""
"arp-for-next-hop.lua"

# mergecap -F pcap -w ndp_without_dst_eth_compound.pcap tcp-fromb4-ipv6.pcap tcp-fromb4-tob4-ipv6.pcap
# mergecap -F pcap -w ndp_ns_and_recap.pcap recap-ipv6.pcap ndp_outgoing_ns.pcap
"NDP: Without receiving NA, next_hop6_mac not set"
"tunnel_icmp_withoutmac.conf" "" "ndp_without_dst_eth_compound.pcap" "decap-ipv4.pcap" "ndp_outgoing_ns.pcap"
"ndp-no-na-next-hop6-mac-not-set-2pkts.lua"

# mergecap -F pcap -w ndp_getna_compound.pcap tcp-fromb4-ipv6.pcap \
# ndp_incoming_solicited_na.pcap tcp-fromb4-tob4-ipv6.pcap
# mergecap -F pcap -w ndp_ns_and_recap.pcap ndp_outgoing_ns.pcap recap-ipv6.pcap
"NDP: With receiving NA, next_hop6_mac not initially set"
"tunnel_icmp_withoutmac.conf" "" "ndp_getna_compound.pcap" "decap-ipv4.pcap" "ndp_ns_and_recap.pcap"
"ndp-no-na-next-hop6-mac-not-set-3pkts.lua"

"IPv6 packet, next hop NA, packet, eth addr not set in configuration."
"tunnel_icmp_withoutmac.conf" "" "" "" "ndp_outgoing_ns.pcap"
"ndp-ns-for-next-hop.lua"

"from-internet IPv4 fragmented packets found in the binding table."
"icmp_on_fail.conf" "tcp-ipv4-3frags-bound.pcap" "" "" "tcp-afteraftr-ipv6-reassembled.pcap"
"in-1p-ipv4-out-1p-ipv6-2.lua"

"from-internet IPv4 fragmented packets found in the binding table, reversed."
"icmp_on_fail.conf" "tcp-ipv4-3frags-bound-reversed.pcap" "" "" "tcp-afteraftr-ipv6-reassembled.pcap"
"in-1p-ipv4-out-1p-ipv6-2.lua"

"traffic class mapping"
"icmp_on_fail.conf" "tcp-frominet-trafficclass.pcap" "" "" "tcp-afteraftr-ipv6-trafficclass.pcap"
"in-1p-ipv4-out-1p-ipv6-1.lua"

"from-internet IPv4 packet found in the binding table, original TTL=1."
"icmp_on_fail.conf" "tcp-frominet-bound-ttl1.pcap" "" "icmpv4-time-expired.pcap" ""
"tcp-frominet-bound-ttl1.lua"

"from-B4 IPv4 fragmentation (2)"
"small_ipv4_mtu_icmp.conf" "" "tcp-ipv6-fromb4-toinet-1046.pcap" "tcp-ipv4-toinet-2fragments.pcap" ""
"in-1p-ipv6-out-1p-ipv4-1.lua"

"from-B4 IPv4 fragmentation (3)"
"small_ipv4_mtu_icmp.conf" "" "tcp-ipv6-fromb4-toinet-1500.pcap" "tcp-ipv4-toinet-3fragments.pcap" ""
"in-1p-ipv6-out-1p-ipv4-2.lua"

"from-internet IPv4 packet found in the binding table, needs IPv6 fragmentation (2)."
"small_ipv6_mtu_no_icmp.conf" "tcp-frominet-bound1494.pcap" "" "" "tcp-afteraftr-ipv6-2frags.pcap"
"in-1p-ipv4-out-1p-ipv6-3.lua"

"from-internet IPv4 packet found in the binding table, needs IPv6 fragmentation (3)."
"small_ipv6_mtu_no_icmp.conf" "tcp-frominet-bound-2734.pcap" "" "" "tcp-afteraftr-ipv6-3frags.pcap"
"in-1p-ipv4-out-1p-ipv6-4.lua"

"IPv6 reassembly (to one packet)."
"big_mtu_no_icmp.conf" "" "tcp-ipv6-2frags-bound.pcap" "tcp-ipv4-2ipv6frags-reassembled-1p.pcap" ""
"in-1p-ipv6-out-1p-ipv4-3.lua"

"IPv6 reassembly (out of order fragments)."
"big_mtu_no_icmp.conf" "" "tcp-ipv6-2frags-bound-reverse.pcap" "tcp-ipv4-2ipv6frags-reassembled-1p.pcap" ""
"in-1p-ipv6-out-1p-ipv4-3.lua"

"IPv6 reassembly (with max frags set to 1)."
"no_icmp_maxfrags1.conf" "" "tcp-ipv6-2frags-bound.pcap" "" ""
"in-1p-ipv6-out-0p-ipv4.lua"

"IPv6 reassembly (followed by decapsulation)."
"small_ipv6_mtu_no_icmp.conf" "" "tcp-ipv6-2frags-bound.pcap" "tcp-ipv4-2ipv6frags-reassembled.pcap" ""
"in-1p-ipv6-out-1p-ipv4-3.lua"

"from-internet IPv4 packet found in the binding table, needs IPv6 fragmentation, DF set, ICMP-3,4, drop policy."
"small_ipv6_mtu_no_icmp.conf" "tcp-frominet-bound1494-DF.pcap" "" "" ""
"from-inet-ipv4-in-binding-big-packet-df-set-drop.lua"

"from-internet IPv4 packet found in the binding table, needs IPv6 fragmentation, DF set, ICMP-3,4, allow policy."
"small_ipv6_mtu_no_icmp_allow.conf" "tcp-frominet-bound1494-DF.pcap" "" "icmpv4-fromlwaftr-replyto-tcp-frominet-bound1494-DF.pcap" ""
"from-inet-ipv4-in-binding-big-packet-df-set-allow.lua"

"from-internet IPv4 packet NOT found in the binding table, no ICMP."
"no_icmp.conf" "tcp-frominet-unbound.pcap" "" "" ""
"in-1p-ipv4-out-none-1.lua"

"from-internet IPv4 packet NOT found in the binding table (IPv4 matches, but port doesn't), no ICMP."
"no_icmp.conf" "tcp-frominet-ip-bound-port-unbound.pcap" "" "" ""
"in-1p-ipv4-out-none-1.lua"

"from-internet IPv4 packet NOT found in the binding table (ICMP-on-fail)."
"icmp_on_fail.conf" "tcp-frominet-unbound.pcap" "" "icmpv4-dst-host-unreachable.pcap" ""
"in-1p-ipv4-out-1p-icmpv4.lua"

"from-internet IPv4 packet NOT found in the binding table (IPv4 matches, but port doesn't) (ICMP-on-fail)."
"icmp_on_fail.conf" "tcp-frominet-ip-bound-port-unbound.pcap" "" "icmpv4-dst-host-unreachable-ip-bound-port-unbound.pcap" ""
"in-1p-ipv4-out-1p-icmpv4.lua"

"from-to-b4 IPv6 packet NOT found in the binding table, no ICMP."
"no_icmp.conf" "" "tcp-afteraftr-ipv6.pcap" "" ""
"in-1p-ipv6-out-none-1.lua"

"from-b4 to-internet IPv6 packet found in the binding table."
"no_icmp.conf" "" "tcp-fromb4-ipv6.pcap" "decap-ipv4.pcap" ""
"in-1p-ipv6-out-1p-ipv4-4.lua"

"from-b4 to-internet IPv6 packet found in the binding table with vlan tag."
"vlan.conf" "" "tcp-fromb4-ipv6-vlan.pcap" "decap-ipv4-vlan.pcap" ""
"in-1p-ipv6-out-1p-ipv4-4.lua"

"from-b4 to-internet IPv6 packet NOT found in the binding table, no ICMP"
"no_icmp.conf" "" "tcp-fromb4-ipv6-unbound.pcap" "" ""
"in-1p-ipv6-out-none-1.lua"

"from-b4 to-internet IPv6 packet NOT found in the binding table, (IPv4 matches, but port doesn't), no ICMP"
"no_icmp.conf" "" "tcp-fromb4-ipv6-bound-port-unbound.pcap" "" ""
"in-1p-ipv6-out-none-1.lua"

"from-b4 to-internet IPv6 packet NOT found in the binding table (ICMP-on-fail)"
"icmp_on_fail.conf" "" "tcp-fromb4-ipv6-unbound.pcap" "" "icmpv6-nogress.pcap"
"in-1p-ipv6-out-1p-icmpv6-1.lua"

"from-b4 to-internet IPv6 packet NOT found in the binding table (IPv4 matches, but port doesn't) (ICMP-on-fail)"
"icmp_on_fail.conf" "" "tcp-fromb4-ipv6-bound-port-unbound.pcap" "" "icmpv6-nogress-ip-bound-port-unbound.pcap"
"in-1p-ipv6-out-1p-icmpv6-1.lua"

# The idea is that with hairpinning off, the packet goes out the inet interface
# and something else routes it back for re-encapsulation. It is not clear why
# this would be desired behaviour, but it is my reading of the RFC.
"from-to-b4 IPv6 packet, no hairpinning"
"no_hairpin.conf" "" "tcp-fromb4-tob4-ipv6.pcap" "decap-ipv4-nohair.pcap" ""
"in-1p-ipv6-out-1p-ipv4-4.lua"

"from-to-b4 IPv6 packet, with hairpinning"
"no_icmp.conf" "" "tcp-fromb4-tob4-ipv6.pcap" "" "recap-ipv6.pcap"
"from-to-b4-ipv6-hairpin.lua"

"from-to-b4 IPv6 packet, with hairpinning, number of packets 64"
"no_icmp.conf" "" "tcp-fromb4-tob4-ipv6-n64.pcap" "" "recap-ipv6-n64.pcap"
"from-to-b4-ipv6-hairpin-n64.lua"

# Ping from 127:11:12:13:14:15:16:128 / 178.79.150.233+7850 to
# 178.79.150.1, which has b4 address 127:22:33:44:55:66:77:127 and is
# not port-restricted.
"from-to-b4 tunneled ICMPv4 ping, with hairpinning"
"tunnel_icmp.conf" "" "hairpinned-icmpv4-echo-request.pcap" "" "hairpinned-icmpv4-echo-request-from-aftr.pcap"
"from-to-b4-tunneled-icmpv4-ping-hairpin.lua"

# As above, but a reply instead.
"from-to-b4 tunneled ICMPv4 ping reply, with hairpinning"
"tunnel_icmp.conf" "" "hairpinned-icmpv4-echo-reply.pcap" "" "hairpinned-icmpv4-echo-reply-from-aftr.pcap"
"from-to-b4-tunneled-icmpv4-ping-hairpin.lua"

"from-to-b4 tunneled ICMPv4 ping, with hairpinning, unbound"
"tunnel_icmp.conf" "" "hairpinned-icmpv4-echo-request-unbound.pcap" "" ""
"from-to-b4-tunneled-icmpv4-ping-hairpin-unbound.lua"

"from-to-b4 tunneled ICMPv4 ping reply, with hairpinning, port 0 not bound"
"tunnel_icmp.conf" "" "hairpinned-icmpv4-echo-reply-unbound.pcap" "" "hairpinned-icmpv4-echo-reply-unbound-from-aftr.pcap"
"in-1p-ipv6-out-1p-icmpv6-2.lua"

"from-to-b4 TCP packet, with hairpinning, TTL 1"
"tunnel_icmp.conf" "" "tcp-fromb4-tob4-ipv6-ttl-1.pcap" "" "tcp-fromb4-tob4-ipv6-ttl-1-reply.pcap"
"in-ipv4-ipv6-out-icmpv4-ipv6-hairpin-1.lua"

"from-to-b4 TCP packet, with hairpinning, TTL 1, drop policy"
"no_icmp.conf" "" "tcp-fromb4-tob4-ipv6-ttl-1.pcap" "" ""
"in-ipv4-ipv6-out-icmpv4-ipv6-hairpin-1-drop.lua"

"from-to-b4 IPv6 packet, with hairpinning, with vlan tag"
"vlan.conf" "" "tcp-fromb4-tob4-ipv6-vlan.pcap" "" "recap-ipv6-vlan.pcap"
"from-to-b4-ipv6-hairpin.lua"

"from-b4 IPv6 packet, with hairpinning, to B4 with custom lwAFTR address"
"no_icmp.conf" "" "tcp-fromb4-tob4-customBRIP-ipv6.pcap" "" "recap-tocustom-BRIP-ipv6.pcap"
"from-to-b4-ipv6-hairpin.lua"

"from-b4 IPv6 packet, with hairpinning, from B4 with custom lwAFTR address"
"no_icmp.conf" "" "tcp-fromb4-customBRIP-tob4-ipv6.pcap" "" "recap-fromcustom-BRIP-ipv6.pcap"
"from-to-b4-ipv6-hairpin.lua"

"from-b4 IPv6 packet, with hairpinning, different non-default lwAFTR addresses"
"no_icmp.conf" "" "tcp-fromb4-customBRIP1-tob4-customBRIP2-ipv6.pcap" "" "recap-customBR-IPs-ipv6.pcap"
"from-to-b4-ipv6-hairpin.lua"

"sending non-IPv4 traffic to the IPv4 interface"
"no_icmp.conf" "tcp-afteraftr-ipv6-wrongiface.pcap" "" "" ""
"non-ipv6-traffic-to-ipv6-interface.lua"

"sending non-IPv6 traffic to the IPv6 interface"
"no_icmp.conf" "" "tcp-frominet-bound-wrongiface.pcap" "" ""
"non-ipv4-traffic-to-ipv4-interface.lua"

# Test UDP packets

"from-internet bound IPv4 UDP packet"
"icmp_on_fail.conf" "udp-frominet-bound.pcap" "" "" "udp-afteraftr-ipv6.pcap"
"in-1p-ipv4-out-1p-ipv6-6.lua"

"unfragmented IPv4 UDP -> outgoing IPv6 UDP fragments"
"small_ipv6_mtu_no_icmp.conf" "udp-frominet-bound.pcap" "" "" "udp-afteraftr-ipv6-2frags.pcap"
"in-1p-ipv4-out-1p-ipv6-6-outfrags.lua"

"IPv6 incoming UDP fragments -> unfragmented IPv4"
"icmp_on_fail.conf" "" "udp-fromb4-2frags-bound.pcap" "udp-afteraftr-reassembled-ipv4.pcap" ""
"in-1p-ipv6-out-1p-ipv4-5-frags.lua"

"IPv6 incoming UDP fragments -> outgoing IPv4 UDP fragments"
"small_ipv4_mtu_icmp.conf" "" "udp-fromb4-2frags-bound.pcap" "udp-afteraftr-ipv4-3frags.pcap" ""
"in-1p-ipv6-out-1p-ipv4-5.lua"

"IPv4 incoming UDP fragments -> outgoing IPv6 UDP fragments"
"small_ipv6_mtu_no_icmp.conf" "udp-frominet-3frag-bound.pcap" "" "" "udp-afteraftr-reassembled-ipv6-2frags.pcap"
"in-1p-ipv4-infrags-out-1p-ipv6-6-outfrags.lua"

# Test ICMP inputs (with and without drop policy)

"incoming ICMPv4 echo request, matches binding table"
"tunnel_icmp.conf" "incoming-icmpv4-echo-request.pcap" "" "" "ipv6-tunneled-incoming-icmpv4-echo-request.pcap"
"in-1p-ipv4-out-1p-ipv6-7.lua"

"incoming ICMPv4 echo request, matches binding table, bad checksum"
"tunnel_icmp.conf" "incoming-icmpv4-echo-request-invalid-icmp-checksum.pcap" "" "" ""
"in-1p-ipv4-out-none-2.lua"

"incoming ICMPv4 echo request, matches binding table, dropping ICMP"
"no_icmp.conf" "incoming-icmpv4-echo-request.pcap" "" "" ""
"in-1p-ipv4-out-none-3.lua"

"incoming ICMPv4 echo request, doesn't match binding table"
"tunnel_icmp.conf" "incoming-icmpv4-echo-request-unbound.pcap" "" "" ""
"in-1p-ipv4-out-none-4.lua"

"incoming ICMPv4 echo reply, matches binding table"
"tunnel_icmp.conf" "incoming-icmpv4-echo-reply.pcap" "" "" "ipv6-tunneled-incoming-icmpv4-echo-reply.pcap"
"in-1p-ipv4-out-1p-ipv6-7.lua"

"incoming ICMPv4 3,4 'too big' notification, matches binding table"
"tunnel_icmp.conf" "incoming-icmpv4-34toobig.pcap" "" "" "ipv6-tunneled-incoming-icmpv4-34toobig.pcap"
"in-1p-ipv4-out-1p-ipv6-8.lua"

"incoming ICMPv6 1,3 destination/address unreachable, OPE from internet"
"tunnel_icmp.conf" "" "incoming-icmpv6-13dstaddressunreach-inet-OPE.pcap" "response-ipv4-icmp31-inet.pcap" ""
"in-1p-ipv6-out-1p-icmpv4-1.lua"

"incoming ICMPv6 2,0 'too big' notification, OPE from internet"
"tunnel_icmp.conf" "" "incoming-icmpv6-20pkttoobig-inet-OPE.pcap" "response-ipv4-icmp34-inet.pcap" ""
"in-1p-ipv6-out-1p-icmpv4-1.lua"

"incoming ICMPv6 3,0 hop limit exceeded, OPE from internet"
"tunnel_icmp.conf" "" "incoming-icmpv6-30hoplevelexceeded-inet-OPE.pcap" "response-ipv4-icmp31-inet.pcap" ""
"in-1p-ipv6-out-1p-icmpv4-1.lua"

"incoming ICMPv6 3,1 frag reassembly time exceeded, OPE from internet"
"tunnel_icmp.conf" "" "incoming-icmpv6-31fragreassemblytimeexceeded-inet-OPE.pcap" "" ""
"in-1p-ipv6-out-none-2.lua"

"incoming ICMPv6 4,3 parameter problem, OPE from internet"
"tunnel_icmp.conf" "" "incoming-icmpv6-43paramprob-inet-OPE.pcap" "response-ipv4-icmp31-inet.pcap" ""
"in-1p-ipv6-out-1p-icmpv4-1.lua"

"incoming ICMPv6 3,0 hop limit exceeded, OPE hairpinned"
"tunnel_icmp.conf" "" "incoming-icmpv6-30hoplevelexceeded-hairpinned-OPE.pcap" "" "response-ipv6-tunneled-icmpv4_31-tob4.pcap"
"in-1p-ipv6-out-1p-ipv4-hoplimhair.lua"

# Ingress filters

"ingress-filter: from-internet (IPv4) packet found in binding table (ACCEPT)"
"no_icmp_with_filters_accept.conf" "tcp-frominet-trafficclass.pcap" "" "" "tcp-afteraftr-ipv6-trafficclass.pcap"
"in-1p-ipv4-out-1p-ipv6-1.lua"

"ingress-filter: from-internet (IPv4) packet found in binding table (DROP)"
"no_icmp_with_filters_drop.conf" "tcp-frominet-trafficclass.pcap" "" "" ""
"in-1p-ipv4-out-0p-drop.lua"

"ingress-filter: from-b4 (IPv6) packet found in binding table (ACCEPT)"
"no_icmp_with_filters_accept.conf" "" "tcp-fromb4-ipv6.pcap" "decap-ipv4.pcap" ""
"in-1p-ipv6-out-1p-ipv4-4.lua"

"ingress-filter: from-b4 (IPv6) packet found in binding table (DROP)"
"no_icmp_with_filters_drop.conf" "" "tcp-fromb4-ipv6.pcap" "" ""
"nofrag6-no-icmp.lua"

# Egress filters

"egress-filter: to-internet (IPv4) (ACCEPT)"
"no_icmp_with_filters_accept.conf" "" "tcp-fromb4-ipv6.pcap" "decap-ipv4.pcap" ""
"in-1p-ipv6-out-1p-ipv4-4.lua"

"egress-filter: to-internet (IPv4) (DROP)"
"no_icmp_with_filters_drop.conf" "" "tcp-fromb4-ipv6.pcap" "" ""
"nofrag6-no-icmp.lua"

"egress-filter: to-b4 (IPv4) (ACCEPT)"
"no_icmp_with_filters_accept.conf" "tcp-frominet-trafficclass.pcap" "" "" "tcp-afteraftr-ipv6-trafficclass.pcap"
"in-1p-ipv4-out-1p-ipv6-1.lua"

"egress-filter: to-b4 (IPv4) (DROP)"
"no_icmp_with_filters_drop.conf" "tcp-frominet-trafficclass.pcap" "" "" ""
"in-1p-ipv4-out-0p-drop.lua"

# Ping to lwAFTR (IPv4).

"ICMP Echo to AFTR (IPv4)"
"no_icmp.conf" "ping-v4.pcap" "" "ping-v4-reply.pcap" ""
"nofrag4-echo.lua"

"ICMP Echo to AFTR (IPv4) (ttl=32)"
"no_icmp.conf" "ping-v4-ttl-32.pcap" "" "ping-v4-reply.pcap" ""
"nofrag4-echo.lua"

"ICMP Echo to AFTR (IPv4) + data"
"no_icmp.conf" "ping-v4-and-data.pcap" "" "ping-v4-reply.pcap" "tcp-afteraftr-ipv6.pcap"
"in-1p-ipv4-out-1p-ipv6-echo.lua"

# Ping to lwAFTR (IPv6).

"ICMP Echo to AFTR (IPv6)"
"no_icmp.conf" "" "ping-v6.pcap" "" "ping-v6-reply.pcap"
"icmpv6-ping-and-reply.lua"

"ICMP Echo to AFTR (IPv6) (hop-limit=32)"
"no_icmp.conf" "" "ping-v6-hop-limit-32.pcap" "" "ping-v6-reply.pcap"
"icmpv6-ping-and-reply.lua"

"ICMP Echo to AFTR (IPv6) + data"
"no_icmp.conf" "" "ping-v6-and-data.pcap" "decap-ipv4.pcap" "ping-v6-reply.pcap"
"in-1p-ipv6-out-1p-ipv4-4-and-echo.lua"
)
TEST_SIZE=${#TEST_DATA[@]}
