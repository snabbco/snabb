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
    echo "Defaulting to PACKETS=100e6"
    export PACKETS=100e6
fi

if [ -z "$CAPFILE" ]; then
    echo "Defaulting to CAPFILE=64"
    export CAPFILE=64
fi

source program/snabbnfv/test_env/test_env.sh

if [ "$SNABB_PCI_INTEL0" != "soft" ]; then
    packetblaster $SNABB_PCI_INTEL0 $CAPFILE
fi
qemu_dpdk $SNABB_PCI_INTEL1 vhost_B.sock $SNABB_TELNET0
snabbnfv_bench $SNABB_PCI_INTEL1 $PACKETS
