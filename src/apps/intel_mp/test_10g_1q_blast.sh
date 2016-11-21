#!/usr/bin/env bash
SNABB_SEND_BLAST=true taskset -c 1 ./testsend.snabb Intel82599 $SNABB_PCI_INTEL1 0 source.pcap &
BLAST=$!

SNABB_RECV_SPINUP=2 SNABB_RECV_DURATION=5 taskset -c 2 ./testrecv.snabb Intel82599 $SNABB_PCI_INTEL0 0 > results.0

kill -9 $BLAST
test `cat results.0 | grep "^RXDGPC" | awk '{print $2}'` -gt 10000
exit $?
