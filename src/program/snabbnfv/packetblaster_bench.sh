#!/bin/bash

if [ -z "$TESTPCI0" ];     then echo "Need TESTPCI0";    exit 1; fi
if [ -z "$TESTPCI1" ];     then echo "Need TESTPCI1";    exit 1; fi
if [ -z "$TELNET_PORT" ];  then echo "Need TELNET_PORT"; exit 1; fi

if [ -z "$PACKETS" ]; then
    echo "Defaulting to PACKETS=100e6"
    export PACKETS=100e6
fi

if [ -z "$CAPFILE" ]; then
    echo "Defaulting to CAPFILE=64"
    export CAPFILE=64
fi

source program/snabbnfv/test_env/test_env.sh

packetblaster $TESTPCI0 $CAPFILE
qemu_dpdk $TESTPCI1 vhost_B.sock $TELNET_PORT
snabbnfv_bench $TESTPCI1 $PACKETS
