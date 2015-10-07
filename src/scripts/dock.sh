#!/usr/bin/env bash

export SNABB_TEST_IMAGE=${SNABB_TEST_IMAGE:=eugeneia/snabb-nfv-test}

# Snabb Switch Docker environment

docker run --privileged -i --name "snabb_test-$USER" \
    -v $(dirname $PWD):/snabbswitch \
    -e SNABB_PCI0=$SNABB_PCI0 \
    -e SNABB_PCI1=$SNABB_PCI1 \
    -e SNABB_PCI_INTEL0=$SNABB_PCI_INTEL0 \
    -e SNABB_PCI_INTEL1=$SNABB_PCI_INTEL1 \
    -e SNABB_PCI_SOLARFLARE0=$SNABB_PCI_SOLARFLARE0 \
    -e SNABB_PCI_SOLARFLARE1=$SNABB_PCI_SOLARFLARE1 \
    -e SNABB_TELNET0=$SNABB_TELNET0 \
    -e SNABB_TELNET1=$SNABB_TELNET1 \
    -e SNABB_PCAP=$SNABB_PCAP \
    $SNABB_TEST_IMAGE \
    bash -c "mount -t hugetlbfs none /hugetlbfs && (cd snabbswitch/src; $*)"
status=$?

docker rm "snabb_test-$USER" >/dev/null

exit $status
