#!/usr/bin/env bash

# Example invocation
# SNABB_PCI_INTEL0=02:00.0 SNABB_PCI_INTEL1=02:00.1 SNABB_SEND_CORE=1 SNABB_CORES="2 2 2 2" SNABB_RX_QS="0 1 2 3" ./bench.sh
rm -f results.*
SNABB_SEND_BLAST=true taskset -c $SNABB_SEND_CORE ./testsend.snabb Intel82599 $SNABB_PCI_INTEL0 0 source.pcap &

CORES=($SNABB_CORES)
i=0
export SNABB_RECV_SPINUP=2
export SNABB_RECV_DURATION=5
PIDS=""
for q in $SNABB_RX_QS; do
   taskset -c ${CORES[i]} ./testrecv.snabb Intel82599 $SNABB_PCI_INTEL1 $q > results.$q &
   PIDS="$PIDS $!"
   ((i++))
done
for p in $PIDS; do
   wait $p
done
cat results.* | grep "^RXDGPC" | awk '{print $2}'
rm -f results.*
pkill -P $$ -f snabb
