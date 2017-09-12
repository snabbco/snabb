#!/usr/bin/env bash

# A benchmark script for 'snabb wall filter'
#
# Run this script with three arguments. The first two are the PCI addresses for the
# two NICs that are connected. The third is the CPU to pin the filter.

PCI1=$1
PCI2=$2
CPU=$3
DURATION=10
ITERS=10

echo "Firewall on $PCI1 (CPU $CPU). Packetblaster on $PCI2."

function benchmark {
  output=`mktemp`
  echo "BENCH ($1, $ITERS iters, $DURATION secs)"
  for (( i=1; i<=$ITERS; i++ ))
  do
    # run the filter
    ./snabb wall filter --cpu $CPU -p -e "{ BITTORRENT = 'drop', default = 'accept' }" -D $DURATION -4 192.168.0.1 -m "01:23:45:67:89:ab" intel $PCI1 > $output &
    # blast with pcap traffic
    ./snabb packetblaster replay -D $DURATION program/wall/tests/data/$1 $PCI2 > /dev/null
    grep "bytes:.*packets:.*bps:" $output
  done
}

benchmark BITTORRENT.pcap
benchmark rtmp_sample.cap
