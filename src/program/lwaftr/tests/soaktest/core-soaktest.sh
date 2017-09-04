#!/usr/bin/env bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

DURATION=${1:-"0.10"}

function quit_with_msg {
    errno=$1; msg="$2"
    echo "Test failed: $msg"
    exit $errno
}

function soaktest {
    conf="$1"; in_v4="$2"; in_v6="$3"
    $SNABB_LWAFTR soaktest -D $DURATION "$conf" "$in_v4" "$in_v6" ||
        quit_with_msg $? "$SNABB_LWAFTR soaktest -D $DURATION $conf $in_v4 $in_v6"
    $SNABB_LWAFTR soaktest -D $DURATION --on-a-stick "$conf" "$in_v4" "$in_v6" ||
        quit_with_msg $? "$SNABB_LWAFTR soaktest -D $DURATION --on-a-stick $conf $in_v4 $in_v6"
}

source "../end-to-end/test_env.sh"

TEST_OUT="/tmp"
SNABB_LWAFTR="../../../../snabb lwaftr"

while true; do
    print_test_name
    soaktest $(read_test_data)
    next_test || break
done
echo "All lwAFTR soak tests passed."
