#!/usr/bin/env bash
cd $(dirname $0)

./testup.snabb $SNABB_PCI_INTEL0 0 > results.0 &
./testup.snabb $SNABB_PCI_INTEL0 1 > results.1 &
./testup.snabb $SNABB_PCI_INTEL0 2 > results.2 &
./testup.snabb $SNABB_PCI_INTEL0 3 > results.3 &
./testup.snabb $SNABB_PCI_INTEL0 4 > results.4 &

./testup.snabb $SNABB_PCI_INTEL1 0 > results.5 &
./testup.snabb $SNABB_PCI_INTEL1 1 > results.6 &
./testup.snabb $SNABB_PCI_INTEL1 2 > results.7 &
./testup.snabb $SNABB_PCI_INTEL1 3 > results.8 &
./testup.snabb $SNABB_PCI_INTEL1 4 > results.9

sleep 2

for i in {0..9}; do
	test 'true' = `cat results.$i | grep -e true -e false` || exit 255
done
exit 0
