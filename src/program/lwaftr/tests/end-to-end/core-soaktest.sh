#!/usr/bin/env bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

export SNABB_LWAFTR="../../../../snabb lwaftr"
export TEST_OUT="/tmp"
export EMPTY="../data/empty.pcap"
export COUNTERS="../data/counters"

source "test-data.sh"

function quit_with_msg {
    errno=$1; msg="$2"
    echo "Test failed: $msg"
    exit $errno
}

function soaktest {
    conf="$1"; in_v4="$2"; in_v6="$3"
    $SNABB_LWAFTR soaktest "$conf" "$in_v4" "$in_v6" ||
        quit_with_msg $? "Test failed: $SNABB_LWAFTR soaktest $@"
    $SNABB_LWAFTR soaktest --on-a-stick "$conf" "$in_v4" "$in_v6" ||
        quit_with_msg $? "Test failed: $SNABB_LWAFTR soaktest --on-a-stick $@"
}

function run_test {
    index=$1
    test_name="$(read_column $index)"
    conf="${TEST_BASE}/$(read_column $((index + 1)))"
    in_v4=$(read_column_pcap $(($index + 2)))
    in_v6=$(read_column_pcap $(($index + 3)))
    echo "Testing: $test_name"
    soaktest "$conf" "$in_v4" "$in_v6"
}

function next_test {
    ROW_INDEX=$(($ROW_INDEX + 7))
    if [[ $ROW_INDEX -ge $TEST_SIZE ]]; then
        echo "All lwAFTR soak tests passed."
        exit 0
    fi
}

ROW_INDEX=0
while true; do
    run_test $ROW_INDEX
    next_test
done
