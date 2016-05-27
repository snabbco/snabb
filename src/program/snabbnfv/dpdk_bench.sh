#!/usr/bin/env bash

export SKIPPED_CODE=43

if [ -z "$SNABB_PCI_INTEL0" -o -z "$SNABB_PCI_INTEL1" ]; then
    export SNABB_PCI_INTEL0=soft
    export SNABB_PCI_INTEL1=soft
fi

if [ -z "$SNABB_TELNET0" ]; then
    export SNABB_TELNET0=5000
    echo "Defaulting to SNABB_TELNET0=$SNABB_TELNET0"
fi

if [ -z "$PACKETS" ]; then
    export PACKETS=100e6
    echo "Defaulting to PACKETS=$PACKETS"
fi

if [ -z "$SNABB_PACKET_SIZES" ]; then
    export SNABB_PACKET_SIZES=60
    echo "Defaulting to SNABB_PACKET_SIZES=$SNABB_PACKET_SIZES"
fi

if [ -z "$SNABB_PACKET_SRC" ]; then
    export SNABB_PACKET_SRC="52:54:00:00:00:02"
    echo "Defaulting to SNABB_PACKET_SRC=$SNABB_PACKET_SRC"
fi

if [ -z "$SNABB_PACKET_DST" ]; then
    export SNABB_PACKET_DST="52:54:00:00:00:01"
    echo "Defaulting to SNABB_PACKET_DST=$SNABB_PACKET_DST"
fi

if [ -z "$SNABB_DPDK_BENCH_CONF" ]; then
    export SNABB_DPDK_BENCH_CONF="program/snabbnfv/test_fixtures/nfvconfig/test_functions/snabbnfv-bench.port"
    echo "Defaulting to SNABB_DPDK_BENCH_CONF=$SNABB_DPDK_BENCH_CONF"
fi

source program/snabbnfv/test_env/test_env.sh

if [ "$SNABB_PCI_INTEL0" != "soft" ]; then
    snabb $SNABB_PCI_INTEL0 "packetblaster synth \
--sizes $SNABB_PACKET_SIZES \
--src $SNABB_PACKET_SRC \
--dst $SNABB_PACKET_DST \
$SNABB_PCI_INTEL0"
fi
qemu_dpdk $SNABB_PCI_INTEL1 vhost_B.sock $SNABB_TELNET0
snabbnfv_bench $SNABB_PCI_INTEL1 $PACKETS $SNABB_DPDK_BENCH_CONF
