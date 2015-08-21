#!/bin/bash

echo "selftest: packetblaster"
export PCIADDR=$SNABB_PCI_INTEL0
[ ! -z "$PCIADDR" ] || export PCIADDR=$SNABB_PCI0
if [ -z "${PCIADDR}" ]; then
    echo "selftest: skipping test - SNABB_PCI_INTEL0/SNABB_PCI0 not set"
    exit 43
fi

# Simple test: Just make sure packetblaster runs for a period of time
# (doesn't crash on startup).
timeout 5 ./snabb packetblaster replay program/packetblaster/selftest.pcap ${SNABB_PCI0}
status=$?
if [ $status != 124 ]; then
    echo "Error: expected timeout (124) but got ${status}"
    exit 1
fi

echo "selftest: ok"
