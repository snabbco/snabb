#!/usr/bin/env bash
cd $(dirname $0)

./testup.snabb $SNABB_PCI_INTEL1G0 0 > results.0 &
./testup.snabb $SNABB_PCI_INTEL1G0 1 > results.1 &
./testup.snabb $SNABB_PCI_INTEL1G0 2 > results.2 &
./testup.snabb $SNABB_PCI_INTEL1G0 3 > results.3 &

./testup.snabb $SNABB_PCI_INTEL1G1 0 > results.4 &
./testup.snabb $SNABB_PCI_INTEL1G1 1 > results.5 &
./testup.snabb $SNABB_PCI_INTEL1G1 2 > results.6 &
./testup.snabb $SNABB_PCI_INTEL1G1 3 > results.7

sleep 2

for i in {0..7}; do
	test 'true' = `cat results.$i | grep -e true -e false` || exit 255
done
exit 0
