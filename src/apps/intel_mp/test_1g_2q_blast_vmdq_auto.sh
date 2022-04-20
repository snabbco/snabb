#!/usr/bin/env bash
#
# Test VMDq with automatic pool selection

SNABB_SEND_BLAST=true SNABB_SEND_BLAST_RATE=1e9 ./testsend.snabb $SNABB_PCI_INTEL1G1 0 source2.pcap &
BLAST=$!

SNABB_RECV_SPINUP=2 SNABB_RECV_DURATION=5 ./testvmdqrecv.snabb $SNABB_PCI_INTEL1G0 "90:72:82:78:c9:7a" nil nil 0 > results.0 &
PID1=$!
SNABB_RECV_SPINUP=2 SNABB_RECV_DURATION=5 ./testvmdqrecv.snabb $SNABB_PCI_INTEL1G0 "12:34:56:78:9a:bc" nil nil 0 > results.1

wait $PID1
kill -9 $BLAST

# FIXME: one pool receives a ton of packets, one only a tiny amount. Generally,
# the right packets seem to be received though??? Change bpp to fpb and $11 to
# $9 when this is figured out.

# both queues should see packets
[[ `cat results.* | grep "^GPRC" | awk '{print $2}'` -gt 10000 ]] &&\
[[ `cat results.0 | grep -m 1 fpb | awk '{print $9}'` -gt 0 ]] &&\
[[ `cat results.1 | grep -m 1 fpb | awk '{print $9}'` -gt 0 ]]

exit $?
