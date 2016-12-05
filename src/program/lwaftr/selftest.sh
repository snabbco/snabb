#!/usr/bin/env bash

set -e # Exit on any errors

SKIPPED_CODE=43
TDIR="program/lwaftr/tests/data/"

if [[ $EUID != 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

# These are tests for lwaftr front ends.

echo "Testing snabb lwaftr bench"
./snabb lwaftr bench -D 0.1 ${TDIR}/icmp_on_fail.conf \
    ${TDIR}/tcp-frominet-bound.pcap ${TDIR}/tcp-fromb4-ipv6.pcap

echo "Testing snabb lwaftr bench --reconfigurable"
./snabb lwaftr bench --reconfigurable -D 1 ${TDIR}/icmp_on_fail.conf \
    ${TDIR}/tcp-frominet-bound.pcap ${TDIR}/tcp-fromb4-ipv6.pcap &

LEADER_PID=$!

sleep 0.1
./snabb config get $LEADER_PID /


# The rest of the tests require real hardware

if [ -z "$SNABB_PCI0" ]; then
   echo "Skipping tests which require real hardware, SNABB_PCI0 not set"
   exit $SKIPPED_CODE
fi

echo "Testing snabb lwaftr run"
sudo ./snabb lwaftr run -D 0.1 --conf ${TDIR}/icmp_on_fail.conf \
    --on-a-stick "$SNABB_PCI0"

echo "Testing snabb lwaftr run --reconfigurable"
sudo ./snabb lwaftr run -D 0.1 --reconfigurable \
    --conf ${TDIR}/icmp_on_fail.conf --on-a-stick "$SNABB_PCI0"
