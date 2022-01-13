#!/usr/bin/env bash
#
# Test VMDq mode with two pools with different VLANs

SNABB_SEND_BLAST=true SNABB_SEND_BLAST_RATE=1e9 ./testsend.snabb $SNABB_PCI_INTEL1G1 0 source-vlan.pcap &
BLAST=$!

SNABB_RECV_SPINUP=2 SNABB_RECV_DURATION=5 ./testvmdqrecv.snabb $SNABB_PCI_INTEL1G0 "90:72:82:78:c9:7a" 1 0 0 > results.0 &
PID1=$!
SNABB_RECV_SPINUP=2 SNABB_RECV_DURATION=5 ./testvmdqrecv.snabb $SNABB_PCI_INTEL1G0 "90:72:82:78:c9:7a" 2 1 0 > results.1

wait $PID1
kill -9 $BLAST
[[ `cat results.* | grep "^GPRC" | awk '{print $2}'` -gt 10000 ]] &&\
# both queues should see packets
[[ `cat results.0 | grep -m 1 fpb | awk '{print $9}'` -gt 0 ]] &&\
[[ `cat results.1 | grep -m 1 fpb | awk '{print $9}'` -gt 0 ]]

exit $?
