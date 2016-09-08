#!/usr/bin/env bash
cd $(dirname $0)
export SNABB_SEND_BLAST=true
export SNABB_RECV_EXPENSIVE=true
taskset -c 1 ./testsend.snabb Intel82599 $SNABB_PCI_INTEL1 0 source.pcap &
BLAST0=$!

SNABB_RECV_SPINUP=3 taskset -c 2 ./testrecv.snabb Intel82599 $SNABB_PCI_INTEL0 0 > results.0
kill -9 $BLAST0
sleep 1
test `cat results.0 | grep "^RXDGPC" | awk '{print $2}'` -gt 200000
exit $?
