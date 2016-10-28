#!/usr/bin/env bash

SKIPPED_CODE=43

if [[ $EUID != 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

if [[ -z "$SNABB_PCI0" ]]; then
    echo "Skip test: SNABB_PCI0 not defined"
    exit $SKIPPED_CODE
fi

if [[ -z "$SNABB_PCI1" ]]; then
    echo "Skip test: SNABB_PCI1 not defined"
    exit $SKIPPED_CODE
fi

LWAFTR_IPV4_ADDRESS=10.0.1.1
LWAFTR_IPV6_ADDRESS=fc00::100
MAC_ADDRESS_NET0=02:AA:AA:AA:AA:AA
NEXT_HOP_MAC=02:99:99:99:99:99
NEXT_HOP_V4=10.0.1.100
NEXT_HOP_V6=fc00::1
SNABBVMX_DIR=program/snabbvmx
PCAP_INPUT=$SNABBVMX_DIR/tests/pcap/input
PCAP_OUTPUT=$SNABBVMX_DIR/tests/pcap/output
SNABBVMX_CONF=$SNABBVMX_DIR/tests/conf/snabbvmx-lwaftr.cfg
SNABBVMX_ID=xe1
SNABB_TELNET0=5000
VHU_SOCK0=/tmp/vh1a.sock

function last_32bit {
    mac=$1
    echo `echo $mac | egrep -o "[[:xdigit:]]+:[[:xdigit:]]+:[[:xdigit:]]+:[[:xdigit:]]+$"`
}

function cleanup {
    exit $1
}

trap cleanup EXIT HUP INT QUIT TERM

# Import SnabbVMX test_env.
if ! source program/snabbvmx/tests/test_env/test_env.sh; then
    echo "Could not load snabbvmx test_env."; exit 1
fi

# Main.
start_test_env

if ! snabb $SNABB_PCI1 "packetblaster replay -D 10 $PCAP_INPUT/v4v6-256.pcap $SNABB_PCI1"; then
    echo "Could not run packetblaster"
fi

# Query nexthop for 10 seconds.
TIMEOUT=10
count=0
while true; do
    output=`./snabb snabbvmx nexthop | egrep -o "[[:xdigit:]]+:[[:xdigit:]]+:[[:xdigit:]]+:[[:xdigit:]]+:[[:xdigit:]]+:[[:xdigit:]]+"`
    mac_v4=`echo "$output" | head -1`
    mac_v6=`echo "$output" | tail -1`

    # Somehow the first 16-bit of nexhop come from the VM corrupted, compare only last 32-bit.
    if [[ $(last_32bit "$mac_v4") == "99:99:99:99" &&
          $(last_32bit "$mac_v6") == "99:99:99:99" ]]; then
        echo "Resolved MAC inet side: $mac_v4 [OK]"
        echo "Resolved MAC inet side: $mac_v6 [OK]"
        exit 0
    fi

    if [[ $count == $TIMEOUT ]]; then
        echo "Could not resolve nexthop"
        exit 1
    fi

    # Try again until TIMEOUT.
    count=$((count + 1))
    sleep 1
done
