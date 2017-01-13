#!/usr/bin/env bash

SKIPPED_CODE=43

if [[ -z "$SNABB_PCI0" ]]; then
    echo "SNABB_PCI0 not set"
    exit $SKIPPED_CODE
fi

if [[ -z "$SNABB_PCI1" ]]; then
    echo "SNABB_PCI1 not set"
    exit $SKIPPED_CODE
fi

source ./program/lwaftr/query/tests/test_env.sh

trap cleanup EXIT HUP INT QUIT TERM

LWAFTR_CONF=./program/lwaftr/tests/data/no_icmp.conf
LWAFTR_NAME=lwaftr-$$

# Run lwAFTR.
tmux_launch "lwaftr" "./snabb lwaftr run --name $LWAFTR_NAME --conf $LWAFTR_CONF --v4 $SNABB_PCI0 --v6 $SNABB_PCI1" "lwaftr.log"
sleep 2

# Test query all.
test_lwaftr_query -l

# Test query by pid.
pid=$(get_lwaftr_instance)
if [[ -n "$pid" ]]; then
    test_lwaftr_query $pid
    test_lwaftr_query $pid "memuse-ipv"
fi

# Test query by name.
test_lwaftr_query "--name $LWAFTR_NAME"
test_lwaftr_query "--name $LWAFTR_NAME memuse-ipv"
