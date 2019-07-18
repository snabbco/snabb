#!/usr/bin/env bash

name=$(basename $0)
if [ "$name" != "dock.sh" ]; then 

  img=$(docker images -q $name)
  if [ -z "$img" ]; then
    echo "docker image $name doesn't exist"
  fi
  exec docker run -ti --rm --privileged -v ${PWD}:/u --workdir /u $name $@

else

  export SNABB_TEST_IMAGE=${SNABB_TEST_IMAGE:=eugeneia/snabb-nfv-test-vanilla}

  # Snabb Docker environment

  docker run --rm --privileged -i -v $(dirname $PWD):/snabb $DOCKERFLAGS \
    -e SNABB_PCI0 \
    -e SNABB_PCI1 \
    -e SNABB_PCI_INTEL0 \
    -e SNABB_PCI_INTEL1 \
    -e SNABB_PCI_INTEL1G0 \
    -e SNABB_PCI_INTEL1G1 \
    -e SNABB_PCI_SOLARFLARE0 \
    -e SNABB_PCI_SOLARFLARE1 \
    -e SNABB_TELNET0 \
    -e SNABB_TELNET1 \
    -e SNABB_PACKET_SIZES \
    -e SNABB_PACKET_SRC \
    -e SNABB_PACKET_DST \
    -e SNABB_IPERF_BENCH_CONF \
    -e SNABB_DPDK_BENCH_CONF \
    -e SNABB_PERF_SAMPLESIZE \
    -e SNABB_IPSEC_SKIP_E2E_TEST \
    $SNABB_TEST_IMAGE \
    bash -c "mount -t hugetlbfs none /hugetlbfs && (cd snabb/src; $*)"
fi
