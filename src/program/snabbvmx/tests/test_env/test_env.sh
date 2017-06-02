#!/usr/bin/env bash

SKIPPED_CODE=43

if [[ $EUID != 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

function run_telnet {
    (echo "$2"; sleep ${3:-2}) \
        | telnet localhost $1 2>&1
}

# Usage: wait_vm_up <port>
# Blocks until ping to 0::0 suceeds.
function wait_vm_up {
    local timeout_counter=0
    local timeout_max=50
    echo -n "Waiting for VM listening on telnet port $1 to get ready..."
    while ( ! (run_telnet $1 "ping6 -c 1 0::0" | grep "1 received" \
        >/dev/null) ); do
        # Time out eventually.
        if [ $timeout_counter -gt $timeout_max ]; then
            echo " [TIMEOUT]"
            exit 1
        fi
        timeout_counter=$(expr $timeout_counter + 1)
        sleep 2
    done
    echo " [OK]"
}

# Define vars before importing SnabbNFV test_env to default initialization.
MAC=$MAC_ADDRESS_NET0
IP=$LWAFTR_IPV6_ADDRESS

if ! source program/snabbnfv/test_env/test_env.sh; then
    echo "Could not load snabbnfv test_env."; exit 1
fi

# Overwrite mac function to always return $MAC.
function mac {
    echo $MAC
}

# Overwrite ip function to always return $IP.
function ip {
    echo $IP
}

function start_test_env {
    local mirror=$1

    local cmd="snabbvmx lwaftr --conf $SNABBVMX_CONF --id $SNABBVMX_ID --pci $SNABB_PCI0 --mac $MAC_ADDRESS_NET0 --sock $VHU_SOCK0"
    if [ -n "$mirror" ]; then
        cmd="$cmd --mirror $mirror"
    fi

    if ! snabb $SNABB_PCI0 "$cmd"; then
        echo "Could not start snabbvmx."; exit 1
    fi

    if ! qemu $SNABB_PCI0 $VHU_SOCK0 $SNABB_TELNET0 $MAC_ADDRESS_NET0; then
        echo "Could not start qemu 0."; exit 1
    fi

    # Wait until VMs are ready.
    wait_vm_up $SNABB_TELNET0

    # Configure eth0 interface in the VM.
    echo -n "Setting up VM..."

    # Bring up interface.
    run_telnet $SNABB_TELNET0 "ifconfig eth0 up" >/dev/null

    # Assign lwAFTR's IPV4 and IPV6 addresses to eth0.
    run_telnet $SNABB_TELNET0 "ip -6 addr add ${LWAFTR_IPV6_ADDRESS}/64 dev eth0" >/dev/null
    run_telnet $SNABB_TELNET0 "ip addr add ${LWAFTR_IPV4_ADDRESS}/24 dev eth0" >/dev/null

    # Add IPv4 and IPv6 nexthop address resolution to MAC.
    run_telnet $SNABB_TELNET0 "ip neigh add ${NEXT_HOP_V4} lladdr ${NEXT_HOP_MAC} dev eth0" >/dev/null
    run_telnet $SNABB_TELNET0 "ip -6 neigh add ${NEXT_HOP_V6} lladdr ${NEXT_HOP_MAC} dev eth0" >/dev/null

    # Set nexthop as default gateway, both in IPv4 and IPv6.
    run_telnet $SNABB_TELNET0 "route add default gw ${NEXT_HOP_V4} eth0" >/dev/null
    run_telnet $SNABB_TELNET0 "route -6 add default gw ${NEXT_HOP_V6} eth0" >/dev/null

    # Activate IPv4 and IPv6 forwarding.
    run_telnet $SNABB_TELNET0 "sysctl -w net.ipv4.conf.all.forwarding=1" >/dev/null
    run_telnet $SNABB_TELNET0 "sysctl -w net.ipv6.conf.all.forwarding=1" >/dev/null

    echo " [OK]"
}
