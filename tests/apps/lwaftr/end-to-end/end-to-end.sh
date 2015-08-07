#!/bin/bash

SNABB_BASE=../../../..
TEST_BASE=${SNABB_BASE}/tests/apps/lwaftr/data
TEST_OUT=/tmp

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

function quit_with_msg {
   echo $1; exit 1
}

function snabb_run_and_cmp {
   rm -f ${TEST_OUT}/endout.pcap
   #echo "${SNABB_BASE}/src/snabb snsh ${SNABB_BASE}/src/apps/lwaftr/main.lua \
   # $1 $2 ${TEST_OUT}/endout.pcap"
   ${SNABB_BASE}/src/snabb snsh ${SNABB_BASE}/src/apps/lwaftr/pcapui.lua \
      $1 $2 ${TEST_OUT}/endout.pcap $SNABB_OUT || quit_with_msg \
        "Snabb failed: ${SNABB_BASE}/src/snabb snsh \
         ${SNABB_BASE}/src/apps/lwaftr/pcapui.lua  $1 $2 ${TEST_OUT}/endout.pcap"
   #echo "cmp $3"; ls -lh $3 ${TEST_OUT}/endout.pcap
   cmp $3 ${TEST_OUT}/endout.pcap || \
      quit_with_msg "snabb snsh apps/lwaftr/main.lua $1 $2 $3 \ncmp $3"
}

echo "Testing: from-internet IPv4 packet found in the binding table."
snabb_run_and_cmp ${TEST_BASE}/icmp_on_fail.conf \
   ${TEST_BASE}/tcp-frominet-bound.pcap ${TEST_BASE}/tcp-afteraftr-ipv6.pcap


echo "Testing: from-internet IPv4 packet NOT found in the binding table."
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${TEST_BASE}/tcp-frominet-unbound.pcap ${TEST_BASE}/empty.pcap

#echo "Testing: from-internet IPv4 packet NOT found in the binding table (ICMP-on-fail)."
#snabb_run_and_cmp ${TEST_BASE}/icmp_on_fail.conf \
#   ${TEST_BASE}/tcp-frominet-unbound.pcap ${TEST_BASE}/empty.pcap

echo "Testing: from-b4 IPv6 packet NOT found in the binding table."
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${TEST_BASE}/tcp-afteraftr-ipv6.pcap ${TEST_BASE}/empty.pcap

echo "Testing: from-b4 IPv6 packet found in the binding table."
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${TEST_BASE}/tcp-fromb4-ipv6.pcap ${TEST_BASE}/decap-ipv4.pcap

echo "Testing: from-b4 IPv6 packet, no hairpinning, B4-IPv6 non-B4-IPv4 dest"
# The idea is that with hairpinning off, the packet goes out the inet interface
# and something else routes it back for re-encapsulation. It's not clear why
# this would be desired behaviour, but it's my reading of the RFC draft.
# Note: this works regardless of the destination IPv4 address and whether
# it is actually associated with the destination B4, which is even more
# questionable.
snabb_run_and_cmp ${TEST_BASE}/no_hairpin.conf \
   ${TEST_BASE}/tcp-fromb4-partly-tob4-ipv6.pcap ${TEST_BASE}/decap-ipv4-nohair-iffy.pcap

echo "Testing: from-b4 IPv6 packet, no hairpinning, B4-IPv6 and IPv4 dest"
# The idea is that with hairpinning off, the packet goes out the inet interface
# and something else routes it back for re-encapsulation. It's not clear why
# this would be desired behaviour, but it's my reading of the RFC draft.
snabb_run_and_cmp ${TEST_BASE}/no_hairpin.conf \
   ${TEST_BASE}/tcp-fromb4-tob4-ipv6.pcap ${TEST_BASE}/decap-ipv4-nohair.pcap

# TODO: verify that the partly-tob4 pcap errors with hairpinning, with-icmp.

echo "Testing: from-b4 IPv6 packet, with hairpinning"
snabb_run_and_cmp ${TEST_BASE}/no_icmp.conf \
   ${TEST_BASE}/tcp-fromb4-tob4-ipv6.pcap ${TEST_BASE}/recap-ipv6.pcap

# echo "Testing: from-b4 IPv6 packet NOT found in the binding table (ICMP-on-fail)."

# Test ICMP inputs (with and without drop policy)

echo "All end-to-end lwAFTR tests passed."
