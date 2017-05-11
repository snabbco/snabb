#!/usr/bin/env bash
#
# Test VMDq mode with two pools with different MACs

SNABB_SEND_BLAST=true ./testsend.snabb $SNABB_PCI_INTEL1 0 source2.pcap &
BLAST=$!

SNABB_RECV_SPINUP=2 SNABB_RECV_DURATION=5 ./testvmdqrecv.snabb $SNABB_PCI_INTEL0 "90:72:82:78:c9:7a" 0 0 > results.0 &
SNABB_RECV_SPINUP=2 SNABB_RECV_DURATION=5 ./testvmdqrecv.snabb $SNABB_PCI_INTEL0 "12:34:56:78:9a:bc" 1 4 > results.1

kill -9 $BLAST
test `cat results.* | grep "^RXDGPC" | awk '{print $2}'` -gt 10000

# both queues should see packets
test \( $? -eq 0 \) -a \( `cat results.0 | grep -m 1 fpb | awk '{print $9}'` -gt 0 \)
test \( $? -eq 0 \) -a \( `cat results.1 | grep -m 1 fpb | awk '{print $9}'` -gt 0 \)

exit $?
