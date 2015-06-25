#!/bin/bash

echo "selftest: packetblaster"
if [ -z "${SNABB_TEST_INTEL10G_PCIDEVA}" ]; then
    echo "selftest: skipping test - SNABB_TEST_INTEL10G_PCIDEVA undefined"
    exit 43
fi

# Simple test: Just make sure packetblaster runs for a period of time
# (doesn't crash on startup).
timeout 5 ./snabb packetblaster replay program/packetblaster/selftest.pcap \
                                       ${SNABB_TEST_INTEL10G_PCIDEVA}
status=$?
if [ $status != 124 ]; then
    echo "Error: expected timeout (124) but got ${status}"
    exit 1
fi

echo "selftest: ok"
