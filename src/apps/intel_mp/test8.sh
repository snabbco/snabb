#!/usr/bin/env bash
cd $(dirname $0)
rm -f results.*
./testblast.snabb $SNABB_PCI_INTEL1G1 0 source.pcap &
BLAST0=$!
./testrecv.snabb 12 $SNABB_PCI_INTEL1G0 0
kill -9 $BLAST0
./sumresults.snabb pps gt 1460000
exit $?
