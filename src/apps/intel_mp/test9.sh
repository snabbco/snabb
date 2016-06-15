#!/usr/bin/env bash
cd $(dirname $0)
rm -f results.*
./testblast.snabb $SNABB_PCI_INTEL1G1 0 source.pcap &
BLAST0=$!
./testblast.snabb $SNABB_PCI_INTEL1G1 1 source.pcap &
BLAST1=$!
./testblast.snabb $SNABB_PCI_INTEL1G1 2 source.pcap &
BLAST2=$!
./testblast.snabb $SNABB_PCI_INTEL1G1 3 source.pcap &
BLAST3=$!
./testrecv.snabb 10 $SNABB_PCI_INTEL1G0 0 &
./testrecv.snabb 10 $SNABB_PCI_INTEL1G0 1 &
./testrecv.snabb 10 $SNABB_PCI_INTEL1G0 2 &
./testrecv.snabb 15 $SNABB_PCI_INTEL1G0 3
kill -9 $BLAST0 $BLAST1 $BLAST2 $BLAST3
./sumresults.snabb pps gt 1460000
exit $?
