#!/usr/bin/env bash

# Example invocation
# SNABB_PCI_INTEL0=02:00.0 SNABB_PCI_INTEL1=02:00.1 SNABB_SEND_CORE=1 SNABB_RECV_CORES="2 2 2 2" SNABB_RECV_QS="0 1 2 3" ./bench.sh
# SNABB_RECV_MASTER_STATS controls whether a dataplane process should export counter registers to snabb counters
rm -f results.*
../../snabb packetblaster replay source.pcap $SNABB_PCI_INTEL0 > /dev/null &

CORES=($SNABB_RECV_CORES)
i=0
export SNABB_RECV_SPINUP=2
export SNABB_RECV_DURATION=5
export SNABB_RECV_MASTER_STATS="${SNABB_RECV_MASTER_STATS:-false}"
PIDS=""
for q in $SNABB_RECV_QS; do
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
