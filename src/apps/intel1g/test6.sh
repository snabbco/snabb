#!/usr/bin/env bash
cd $(dirname $0)
rm -f results.*

./testrecv.snabb 10 $SNABB_PCI_INTEL1G0 0 > /dev/null &
./testrecv.snabb 10 $SNABB_PCI_INTEL1G0 1 > /dev/null &
./testrecv.snabb 10 $SNABB_PCI_INTEL1G0 2 > /dev/null &
./testrecv.snabb 10 $SNABB_PCI_INTEL1G0 3 > /dev/null &
./testsend.snabb 5 $SNABB_PCI_INTEL1G1 0 source.pcap > /dev/null &
./testsend.snabb 5 $SNABB_PCI_INTEL1G1 1 source.pcap > /dev/null &
./testsend.snabb 5 $SNABB_PCI_INTEL1G1 2 source.pcap > /dev/null &
./testsend.snabb 5 $SNABB_PCI_INTEL1G1 3 source.pcap > /dev/null &
sleep 15
./sumresults.snabb pkts eq 204
exit $?
