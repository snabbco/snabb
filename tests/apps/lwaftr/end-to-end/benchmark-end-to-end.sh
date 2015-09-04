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

function usage {
    quit_with_msg "Usage: benchmark-end-to-end <pcidev>"
}

pcidev=$1
if [ -z "$pcidev" ]; then
    usage
fi

function run_benchmark {
    local script=${SNABB_BASE}/src/apps/lwaftr/benchmark.lua
    local binding_table=${TEST_BASE}/binding.table
    local conf=$1
    local pcap_file=$2

    echo "${SNABB_BASE}/src/snabb snsh $script $binding_table $conf $pcap_file $pcidev"
    ${SNABB_BASE}/src/snabb snsh $script $binding_table $conf $pcap_file $pcidev
}

echo "Benchmarking: from-internet IPv4 packet found in the binding table."
run_benchmark ${TEST_BASE}/icmp_on_fail.conf \
    ${TEST_BASE}/tcp-frominet-bound.pcap

# Fail
# echo "Testing: from-internet IPv4 packet found in the binding table, original TTL=1."
# run_benchmark ${TEST_BASE}/icmp_on_fail.conf \
#     ${TEST_BASE}/tcp-frominet-bound-ttl1.pcap

echo "Benchmarking: from-internet IPv4 packet found in the binding table, needs IPv6 fragmentation."
run_benchmark ${TEST_BASE}/small_ipv6_mtu_no_icmp.conf \
   ${TEST_BASE}/tcp-frominet-bound1494.pcap

echo "Benchmarking: from-internet IPv4 packet found in the binding table, needs IPv6 fragmentation, DF set, ICMP-3,4."
run_benchmark ${TEST_BASE}/small_ipv6_mtu_no_icmp.conf \
   ${TEST_BASE}/tcp-frominet-bound1494-DF.pcap

# TODO: Returns 0 Mbps
# echo "Benchmarking: from-internet IPv4 packet NOT found in the binding table, no ICMP."
# run_benchmark ${TEST_BASE}/no_icmp.conf \
#    ${TEST_BASE}/tcp-frominet-unbound.pcap

# TODO: Fail
# echo "Benchmarking: from-internet IPv4 packet NOT found in the binding table (ICMP-on-fail)."
# run_benchmark ${TEST_BASE}/icmp_on_fail.conf \
#    ${TEST_BASE}/tcp-frominet-unbound.pcap

# TODO: Returns 0 Mpbs
# echo "Benchmarking: from-to-b4 IPv6 packet NOT found in the binding table, no ICMP."
# run_benchmark ${TEST_BASE}/no_icmp.conf \
# ${TEST_BASE}/tcp-afteraftr-ipv6.pcap

echo "Benchmarking: from-b4 to-internet IPv6 packet found in the binding table."
run_benchmark ${TEST_BASE}/no_icmp.conf \
${TEST_BASE}/tcp-fromb4-ipv6.pcap

# TODO: Returns 0 Mbps
# echo "Benchmarking: from-b4 to-internet IPv6 packet NOT found in the binding table, no ICMP"
# run_benchmark ${TEST_BASE}/no_icmp.conf \
#    ${TEST_BASE}/tcp-fromb4-ipv6-unbound.pcap

# TODO: Returns 0 Mbps
echo "Benchmarking: from-b4 to-internet IPv6 packet NOT found in the binding table (ICMP-on-fail)"
run_benchmark ${TEST_BASE}/icmp_on_fail.conf \
${TEST_BASE}/tcp-fromb4-ipv6-unbound.pcap

echo "Benchmarking: from-to-b4 IPv6 packet, no hairpinning"
run_benchmark ${TEST_BASE}/no_hairpin.conf \
   ${TEST_BASE}/tcp-fromb4-tob4-ipv6.pcap

echo "Benchmarking: from-to-b4 IPv6 packet, with hairpinning"
run_benchmark ${TEST_BASE}/no_icmp.conf \
   ${TEST_BASE}/tcp-fromb4-tob4-ipv6.pcap

echo "Benchmarking: from-b4 IPv6 packet, with hairpinning, to B4 with custom lwAFTR address"
run_benchmark ${TEST_BASE}/no_icmp.conf \
   ${TEST_BASE}/tcp-fromb4-tob4-customBRIP-ipv6.pcap

echo "Benchmarking: from-b4 IPv6 packet, with hairpinning, from B4 with custom lwAFTR address"
run_benchmark ${TEST_BASE}/no_icmp.conf \
   ${TEST_BASE}/tcp-fromb4-customBRIP-tob4-ipv6.pcap

echo "Benchmarking: from-b4 IPv6 packet, with hairpinning, different non-default lwAFTR addresses"
run_benchmark ${TEST_BASE}/no_icmp.conf \
   ${TEST_BASE}/tcp-fromb4-customBRIP1-tob4-customBRIP2-ipv6.pcap

echo "All benchmarking tests run."
