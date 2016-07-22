#!/usr/bin/env bash

export SNABB_TEST_IMAGE=${SNABB_TEST_IMAGE:=eugeneia/snabb-nfv-test-vanilla}

# Snabb Docker environment

docker run --rm --privileged -i -v $(dirname $PWD):/snabb $DOCKERFLAGS \
    -e SNABB_PCI0=$SNABB_PCI0 \
    -e SNABB_PCI1=$SNABB_PCI1 \
    -e SNABB_PCI_INTEL0=$SNABB_PCI_INTEL0 \
    -e SNABB_PCI_INTEL1=$SNABB_PCI_INTEL1 \
    -e SNABB_PCI_INTEL1G0=$SNABB_PCI_INTEL1G0 \
    -e SNABB_PCI_INTEL1G1=$SNABB_PCI_INTEL1G1 \
    -e SNABB_PCI_SOLARFLARE0=$SNABB_PCI_SOLARFLARE0 \
    -e SNABB_PCI_SOLARFLARE1=$SNABB_PCI_SOLARFLARE1 \
    -e SNABB_TELNET0=$SNABB_TELNET0 \
    -e SNABB_TELNET1=$SNABB_TELNET1 \
    -e SNABB_PCAP=$SNABB_PCAP \
    -e SNABB_PERF_SAMPLESIZE=$SNABB_PERF_SAMPLESIZE \
    $SNABB_TEST_IMAGE \
    bash -c "mount -t hugetlbfs none /hugetlbfs && (cd snabb/src; $*)"
