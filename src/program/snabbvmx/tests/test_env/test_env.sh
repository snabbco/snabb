#!/usr/bin/env bash

SKIPPED_CODE=43

if [[ $EUID != 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

BZ_IMAGE="$HOME/.test_env/bzImage"
HUGEPAGES_FS=/dev/hugepages
IMAGE="$HOME/.test_env/qemu.img"
MEM=1024M

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

function qemu_cmd {
    echo "qemu-system-x86_64 \
         -kernel ${BZ_IMAGE} -append \"earlyprintk root=/dev/vda rw console=tty0\" \
         -enable-kvm -drive format=raw,if=virtio,file=${IMAGE} \
         -M pc -smp 1 -cpu host -m ${MEM} \
         -object memory-backend-file,id=mem,size=${MEM},mem-path=${HUGEPAGES_FS},share=on \
         -numa node,memdev=mem \
         -chardev socket,id=char1,path=${VHU_SOCK0},server \
             -netdev type=vhost-user,id=net0,chardev=char1 \
             -device virtio-net-pci,netdev=net0,addr=0x8,mac=${MAC_ADDRESS_NET0} \
         -serial telnet:localhost:${SNABB_TELNET0},server,nowait \
         -display none"
}

function quit_screen { screen_id=$1
    screen -X -S "$screen_id" quit &> /dev/null
}

function run_cmd_in_screen { screen_id=$1; cmd=$2
    screen_id="${screen_id}-$$"
    quit_screen "$screen_id"
    screen -dmS "$screen_id" bash -c "$cmd >> $SNABBVMX_LOG"
}

function qemu {
    run_cmd_in_screen "qemu" "`qemu_cmd`"
}

function start_test_env {
    if [[ ! -f "$IMAGE" ]]; then
       echo "Couldn't find QEMU image: $IMAGE"
       exit $SKIPPED_CODE
    fi

    # Run qemu.
    qemu

    # Wait until VMs are ready.
    wait_vm_up $SNABB_TELNET0

    # Manually set ip addresses.
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
}
