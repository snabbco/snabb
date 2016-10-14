#!/usr/bin/env bash

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
    quit_screens
    exit 0
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
        break
    fi

    if [[ $count == $TIMEOUT ]]; then
        break
    fi
    count=$((count + 1))
    sleep 1
done

if [[ $count == $TIMEOUT ]]; then
    echo "Couldn't resolve nexthop"
    exit 1
fi
