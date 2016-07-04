#!/usr/bin/env bash
SNABB_SEND_BLAST=true taskset -c 2 ./testsend.snabb Intel1g $SNABB_PCI_INTEL1G1 0 source.pcap &
BLAST=$!

SNABB_RECV_SPINUP=2 SNABB_RECV_DURATION=5 taskset -c 4 ./testrecv.snabb Intel1g $SNABB_PCI_INTEL1G0 0 > results.0

kill -9 $BLAST
test `cat results.0 | grep "^RPTHC" | awk '{print $2}'` -gt 1400000
exit $?
