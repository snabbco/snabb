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
GUEST_MEM=1024

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
TIMEOUT=20
COUNT=0
while true; do
    output=$(./snabb snabbvmx query | grep "next_hop_mac")

    mac_v4=$(echo $output | sed "s/.*<next_hop_mac_v4>\([^<]\+\)<\/next_hop_mac_v4>.*/\1/")
    mac_v6=$(echo $output | sed "s/.*<next_hop_mac_v6>\([^<]\+\)<\/next_hop_mac_v6>.*/\1/")

    # FIXME: Should return expected MAC addresses.
    # Check VM returned something and it's different than 00:00:00:00:00:00.
    if [[ -n "$mac_v4" && -n "$mac_v6" ]]; then
       if [[ "$mac_v4" != "00:00:00:00:00:00" &&
             "$mac_v6" != "00:00:00:00:00:00" ]]; then
           echo "Resolved MAC inet side: $mac_v4 [OK]"
           echo "Resolved MAC b4 side: $mac_v6 [OK]"
           exit 0
       fi
    fi

    if [[ $COUNT == $TIMEOUT ]]; then
        echo "Could not resolve nexthop"
        echo "MAC inet side: $mac_v4 [FAILED]"
        echo "MAC b4 side: $mac_v6 [FAILED]"
        exit 1
    fi

    # Try again until TIMEOUT.
    COUNT=$((COUNT + 1))
    sleep 1
done
