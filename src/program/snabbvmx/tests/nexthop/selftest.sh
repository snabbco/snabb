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
MIRROR_TAP=tap0
NEXT_HOP_MAC=02:99:99:99:99:99
NEXT_HOP_V4=10.0.1.100
NEXT_HOP_V6=fc00::1
SNABBVMX_DIR=program/snabbvmx
PCAP_INPUT=$SNABBVMX_DIR/tests/pcap/input
PCAP_OUTPUT=$SNABBVMX_DIR/tests/pcap/output
SNABBVMX_CONF=$SNABBVMX_DIR/tests/conf/snabbvmx-lwaftr.cfg
SNABBVMX_ID=xe1
SNABBVMX_LOG=snabbvmx.log
SNABB_TELNET0=5000
VHU_SOCK0=/tmp/vh1a.sock

# Load environment settings.
source program/snabbvmx/tests/test_env/test_env.sh

function quit_screens {
    screens=$(screen -ls | egrep -o "[0-9]+\." | sed 's/\.//')
    for each in $screens; do
        if [[ "$each" > 0 ]]; then
            screen -S $each -X quit
        fi
    done
}

function cleanup {
    local exit_code=$1
    quit_screens
    exit $exit_code
}

trap cleanup EXIT HUP INT QUIT TERM

# Override settings.
SNABBVMX_CONF=$SNABBVMX_DIR/tests/conf/snabbvmx-lwaftr-xe0.cfg
TARGET_MAC_INET=02:99:99:99:99:99
TARGET_MAC_B4=02:99:99:99:99:99

# Clean up log file.
rm -f $SNABBVMX_LOG

# Run SnabbVMX.
cmd="./snabb snabbvmx lwaftr --conf $SNABBVMX_CONF --id $SNABBVMX_ID --pci $SNABB_PCI0 --mac $MAC_ADDRESS_NET0 --sock $VHU_SOCK0"
run_cmd_in_screen "snabbvmx" "$cmd"

# Run QEMU.
start_test_env

# Flush lwAFTR packets to SnabbVMX.
cmd="./snabb packetblaster replay -D 10 $PCAP_INPUT/v4v6-256.pcap $SNABB_PCI1"
run_cmd_in_screen "packetblaster" "$cmd"

function last_32bit {
    mac=$1
    echo `echo $mac | egrep -o "[[:xdigit:]]+:[[:xdigit:]]+:[[:xdigit:]]+:[[:xdigit:]]+$"`
}

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
        exit 1
    fi
    count=$((count + 1))
    sleep 1
done
