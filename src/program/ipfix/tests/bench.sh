#!/usr/bin/env bash

# A benchmark script for 'snabb ipfix probe'
#
# Run this script with four arguments. The first two are the PCI addresses for the
# two NICs that are connected. The third is the PCI address for the export NIC.
# The fourth is the CPU to pin the filter.
#
# e.g.,
#   sudo program/ipfix/tests/bench.sh 02:00.0 82:00.0 03:00.0 5

PCI1=$1
PCI2=$2
PCI3=$3
CPU=$4
DURATION=10
ITERS=5

echo "Probe on $PCI1. Packetblaster on $PCI2."

function benchmark {
  pcap=`mktemp`
  output=`mktemp`
  ./program/ipfix/tests/generate_packets.py --size $size $count $pcap 2> /dev/null
  echo "BENCH (size $1 ($2 pkts) for $ITERS iters, $DURATION secs)"
  for (( i=1; i<=$ITERS; i++ ))
  do
    # run the probe
    ./snabb ipfix probe --cpu $CPU -s -i intel10g -o intel10g -m 00:11:22:33:44:55 -a 192.168.1.2 -M 55:44:33:22:11:00 -c 192.168.1.3 -p 2100 -D $DURATION $PCI1 $PCI3 > $output &
    # blast with pcap traffic
    ./snabb packetblaster replay -D $DURATION $pcap $PCI2 > /dev/null &
    wait
    grep "bytes:.*" $output
  done
}

for size in 64 200 400 800 1516
do
  for count in 1000 5000 10000
  do
    benchmark $size $count
  done
done
