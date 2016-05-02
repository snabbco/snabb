#!/usr/bin/env bash
cd $(dirname $0)
exec 2> /dev/null
exec > /dev/null
rm -f results.*
./testblast.snabb $SNABB_PCI_INTEL1G1 0 source.pcap &
BLAST0=$!
./testrecv.snabb 10 $SNABB_PCI_INTEL1G0 0
kill -9 $BLAST0
./sumresults.snabb pps gt 1460000
exit $?
