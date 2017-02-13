#!/usr/bin/env bash

set -e # Exit on any errors

SKIPPED_CODE=43
TDIR="program/lwaftr/tests/data/"

if [[ $EUID != 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

# The tests require real hardware

if [ -z "$SNABB_PCI0" ]; then
   echo "Skipping tests which require real hardware, SNABB_PCI0 not set"
   exit $SKIPPED_CODE
fi

echo "Testing snabb lwaftr run"
sudo ./snabb lwaftr run -D 0.1 --conf ${TDIR}/icmp_on_fail.conf \
    --on-a-stick "$SNABB_PCI0"

# This needs to be 1 second, not 0.1 second, or it can mask DMA/setup problems
echo "Testing snabb lwaftr run --reconfigurable"
sudo ./snabb lwaftr run -D 1 --reconfigurable \
    --conf ${TDIR}/icmp_on_fail.conf --on-a-stick "$SNABB_PCI0"
