#!/bin/bash

if [ -z "$SNABB_PCI0" ]; then echo "Need SNABB_PCI0"; exit $SKIPPED_CODE; fi
if [ -z "$SNABB_PCI1" ]; then echo "Need SNABB_PCI1"; exit $SKIPPED_CODE; fi

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

packetblaster $SNABB_PCI0 $CAPFILE
qemu_dpdk $SNABB_PCI1 vhost_B.sock $SNABB_TELNET0
snabbnfv_bench $SNABB_PCI1 $PACKETS
