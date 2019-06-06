#!/usr/bin/env bash

# set -x

SKIPPED_CODE=43

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

if [[ -z "$SNABB_PCI0" ]]; then
    echo "SNABB_PCI0 not defined"
    exit $SKIPPED_CODE
fi

if [[ -z "$SNABB_PCI1" ]]; then
    echo "SNABB_PCI1 not defined"
    exit $SKIPPED_CODE
fi

ping6=$(which ping6 2> /dev/null)
if [[ $? == 0 ]]; then
    ping6="ping6"
else
    ping6="ping -6"
fi

function fatal {
    local msg=$1
    echo "Error: $msg"
    exit 1
}

function iface_by_pciaddr {
    local pciaddr=$1
    echo $(lshw -c network -businfo | grep "pci@$pciaddr" | awk '{print $2}')
}

function bind_card {
    local pciaddr=$1

    # Check is bound.
    if [[ -L "/sys/bus/pci/drivers/ixgbe/$pciaddr" ]]; then
        echo $(iface_by_pciaddr $pciaddr)
    fi

    # Bind card and return iface name.
    echo $pciaddr | sudo tee /sys/bus/pci/drivers/ixgbe/bind &> /dev/null
    if [[ $? -eq 0 ]]; then
        iface=$(ls /sys/bus/pci/devices/$pciaddr/net)
        echo $iface
    fi
}

function test_ping_to_internal_interface {
    local out=$($ping6 -c 1 -I "$IFACE.v6" "$INTERNAL_IP")
    local count=$(echo "$out" | grep -o -c " 0% packet loss")
    if [[ $count -eq 1 ]]; then
        echo "Success: Ping to internal interface"
    else
        fatal "Couldn't ping to internal interface"
    fi
}

function test_ping_to_external_interface {
    local out=$(ping -c 1 -I "$IFACE.v4" "$EXTERNAL_IP")
    local count=$(echo "$out" | grep -o -c " 0% packet loss")
    if [[ $count -eq 1 ]]; then
        echo "Success: Ping to external interface"
    else
        fatal "Couldn't ping to external interface"
    fi

}

function cleanup {
    sudo tmux kill-session -t $lwaftr_session
    local pids=$(ps aux | grep $SNABB_PCI0 | grep -v grep | awk '{print $2}')
    for pid in ${pids[@]}; do
        kill $pid
    done
}

trap cleanup EXIT HUP INT QUIT TERM

LWAFTR_CONF=program/lwaftr/tests/data/lwaftr-vlan.conf
EXTERNAL_IP=10.0.1.1
INTERNAL_IP=fe80::100
IPV4_ADDRESS=10.0.1.2/24
IPV6_ADDRESS=fe80::101/64
VLAN_V4_TAG=164
VLAN_V6_TAG=125

# Bind SNABB_PCI1 to kernel.
IFACE=$(bind_card $SNABB_PCI1)
if [[ -z "$IFACE" ]]; then
    fatal "Couldn't bind card $SNABB_PCI1"
else
    ip li set up dev $IFACE
    sleep 1
fi

# Run lwAFTR in on-a-stick mode.
lwaftr_session=lwaftr-session-$$
tmux new-session -d -n "lwaftr" -s $lwaftr_session "sudo ./snabb lwaftr run --conf $LWAFTR_CONF --on-a-stick $SNABB_PCI0" | tee lwaftr.log

# Create VLAN V4 interface.
ip li delete "$IFACE.v4" &> /dev/null
ip link add link $IFACE name "$IFACE.v4" type vlan id $VLAN_V4_TAG
ip addr add $IPV4_ADDRESS dev "$IFACE.v4" 
sleep 3

# Create VLAN V6 interface.
ip li delete "$IFACE.v6" &> /dev/null
ip link add link $IFACE name "$IFACE.v6" type vlan id $VLAN_V6_TAG
ip addr add $IPV6_ADDRESS dev "$IFACE.v6" 
sleep 3

test_ping_to_internal_interface
test_ping_to_external_interface
