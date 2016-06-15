#!/usr/bin/env bash
cd $(dirname $0)
rm -f results.*

./testrecv.snabb 12 $SNABB_PCI_INTEL1G0 0 &
./testrecv.snabb 12 $SNABB_PCI_INTEL1G0 1 &
./testrecv.snabb 12 $SNABB_PCI_INTEL1G0 2 &
./testrecv.snabb 12 $SNABB_PCI_INTEL1G0 3 &
./testsend.snabb 7 $SNABB_PCI_INTEL1G1 0 source.pcap > /dev/null &
./testsend.snabb 7 $SNABB_PCI_INTEL1G1 1 source.pcap > /dev/null &
./testsend.snabb 7 $SNABB_PCI_INTEL1G1 2 source.pcap > /dev/null &
./testsend.snabb 7 $SNABB_PCI_INTEL1G1 3 source.pcap > /dev/null &
sleep 15
./sumresults.snabb pkts eq 204
exit $?
