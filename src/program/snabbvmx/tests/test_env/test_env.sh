#!/usr/bin/env bash

SKIPPED_CODE=43

if [[ $EUID != 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

export LWAFTR_IPV6_ADDRESS=fc00::100/64
export LWAFTR_IPV4_ADDRESS=10.0.1.1/24
export BZ_IMAGE="$HOME/.test_env/bzImage"
export HUGEPAGES_FS=/dev/hugepages
export IMAGE="$HOME/.test_env/qemu.img"
export MAC_ADDRESS_NET0="02:AA:AA:AA:AA:AA"
export MEM=1024M
export MIRROR_TAP=tap0
export SNABBVMX_DIR=program/snabbvmx
export PCAP_INPUT=$SNABBVMX_DIR/tests/pcap/input
export PCAP_OUTPUT=$SNABBVMX_DIR/tests/pcap/output
export SNABBVMX_CONF=$SNABBVMX_DIR/tests/conf/snabbvmx-lwaftr-vlan.cfg
export SNABBVMX_ID=xe1
export SNABB_TELNET0=5000
export VHU_SOCK0=/tmp/vh1a.sock
export SNABBVMX_LOG=snabbvmx.log

# Usage: run_telnet <port> <command> [<sleep>]
# Runs <command> on VM listening on telnet <port>. Waits <sleep> seconds
# for before closing connection. The default of <sleep> is 2.
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

# TODO: Use standard launch_qemu command.
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

function run_cmd_in_screen { screen_id=$1; cmd=$2
    screen_id="${screen_id}-$$"
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
    run_telnet $SNABB_TELNET0 "ip -6 addr add $LWAFTR_IPV6_ADDRESS dev eth0" >/dev/null
    run_telnet $SNABB_TELNET0 "ip addr add $LWAFTR_IPV4_ADDRESS dev eth0" >/dev/null
    run_telnet $SNABB_TELNET0 "ip neigh add 10.0.1.100 lladdr 02:99:99:99:99:99 dev eth0" >/dev/null
    run_telnet $SNABB_TELNET0 "ip -6 neigh add fc00::1 lladdr 02:99:99:99:99:99 dev eth0" >/dev/null
    run_telnet $SNABB_TELNET0 "route add default gw 10.0.1.100 eth0" >/dev/null
    run_telnet $SNABB_TELNET0 "route -6 add default gw fc00::1 eth0" >/dev/null
    run_telnet $SNABB_TELNET0 "sysctl -w net.ipv4.conf.all.forwarding=1" >/dev/null
    run_telnet $SNABB_TELNET0 "sysctl -w net.ipv6.conf.all.forwarding=1" >/dev/null
}
