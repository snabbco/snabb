#!/bin/bash

SKIPPED_CODE=43

if [ -z "$MAC" ]; then
    export MAC=52:54:00:00:00:
    echo "Defaulting to MAC=$MAC"
fi

if [ -z "$IP" ]; then
    export IP=fe80::5054:ff:fe00:
    echo "Defaulting to IP=$IP"
fi

if [ -z "$GUEST_MEM" ]; then
    export GUEST_MEM=512
    echo "Defaulting to GUEST_MEM=$GUEST_MEM"
fi

if [ -z "$HUGETLBFS" ]; then
    export HUGETLBFS=/hugetlbfs
    echo "Defaulting to HUGETLBFS=$HUGETLBFS"
fi

#calculate and set qemu_mq related variables
if [ -n "$QUEUES" ]; then
    export qemu_mq=on
else
    export qemu_mq=off
    export QUEUES=1
    echo "Defaulting to QUEUES=$QUEUES"
fi
export qemu_smp=$QUEUES
export qemu_vectors=$((2*$QUEUES + 1))

export sockets=""
if [ -z "$SNABB_TEST_FIXTURES" ]; then
    export assets=$HOME/.test_env
else
    export assets=$SNABB_TEST_FIXTURES
fi
export qemu=qemu/obj/x86_64-softmmu/qemu-system-x86_64
export host_qemu=$(which qemu-system-x86_64)

if [ -z "$QEMU" ]; then
    export QEMU=${host_qemu:-"$assets/$qemu"}
    echo "Defaulting to QEMU=$QEMU"
fi
[ -x "$QEMU" ] || (echo "Not found: $QEMU"; exit 1)

export tmux_session=""

function tmux_launch {
    command="$2 2>&1 | tee $3"
    if [ -z "$tmux_session" ]; then
        tmux_session=test_env-$$
        tmux new-session -d -n "$1" -s $tmux_session "$command"
    else
        tmux new-window -a -d -n "$1" -t $tmux_session "$command"
    fi
}

export snabb_n=0

function pci_node {
    case "$1" in
        *:*:*.*)
            cpu=$(cat /sys/class/pci_bus/${1%:*}/cpulistaffinity | cut -d "-" -f 1)
            numactl -H | grep "cpus: $cpu" | cut -d " " -f 2
            ;;
        *)
            if [ "$1" = "soft" ]
            then echo 0
            else echo $1
            fi
            ;;
    esac
}

function snabb_log {
    echo "snabb${snabb_n}.log"
}

function snabb {
    tmux_launch \
        "snabb$snabb_n" \
        "numactl --cpunodebind=$(pci_node $1) --membind=$(pci_node $1) ./snabb $2" \
        $(snabb_log)
    snabb_n=$(expr $snabb_n + 1)
}

export qemu_n=0

function qemu_log {
    echo "qemu${qemu_n}.log"
}

function qemu_image {
    image=$assets/$1${qemu_n}.img
    [ -f $image ] || cp $assets/$1.img $image 2> /dev/null
    echo $image
}

function mac {
    printf "$MAC%02X\n" $1
}

function ip {
    printf "$IP%04X\n" $1
}

function launch_qemu {
    if [ ! -n $QUEUES ]; then
        export mqueues=",queues=$QUEUES"
    fi
    if [ -e $assets/initrd ]; then
        export QEMU_ARGS="-initrd $assets/initrd $QEMU_ARGS"
    fi
    tmux_launch \
        "qemu$qemu_n" \
        "numactl --cpunodebind=$(pci_node $1) --membind=$(pci_node $1) \
        $QEMU $QEMU_ARGS \
        -kernel $assets/$4 \
        -append \"earlyprintk root=/dev/vda $SNABB_KERNEL_PARAMS rw console=ttyS1 ip=$(ip $qemu_n)\" \
        -m $GUEST_MEM -numa node,memdev=mem -object memory-backend-file,id=mem,size=${GUEST_MEM}M,mem-path=$HUGETLBFS,share=on \
        -netdev type=vhost-user,id=net0,chardev=char0${mqueues} -chardev socket,id=char0,path=$2,server \
        -device virtio-net-pci,netdev=net0,mac=$(mac $qemu_n),mq=$qemu_mq,vectors=$qemu_vectors \
        -M pc -smp $qemu_smp -cpu host --enable-kvm \
        -serial telnet:localhost:$3,server,nowait \
        -serial stdio \
        -drive if=virtio,format=raw,file=$(qemu_image $5) \
        -display none" \
        $(qemu_log)
    qemu_n=$(expr $qemu_n + 1)
    sockets="$sockets $2"
}

function qemu {
    local image=$(qemu_image "qemu")
    if [ ! -f "$image" ]; then
        echo "Couldn't find QEMU image: ${image}"
        exit $SKIPPED_CODE
    fi
    launch_qemu $1 $2 $3 bzImage qemu
}

function qemu_dpdk {
    launch_qemu $1 $2 $3 bzImage qemu-dpdk
}

function snabbnfv_bench {
    numactl --cpunodebind=$(pci_node $1) --membind=$(pci_node $1) \
        ./snabb snabbnfv traffic -B $2 $1 $3 vhost_%s.sock
}

function on_exit {
    [ -n "$tmux_session" ] && tmux kill-session -t $tmux_session 2>&1 >/dev/null
    rm -f $sockets
    exit
}

trap on_exit EXIT HUP INT QUIT TERM

# Usage: wait_vm_up <port>

# Usage: run_telnet <port> <command> [<sleep>]
# Runs <command> on VM listening on telnet <port>. Waits <sleep> seconds
# for before closing connection. The default of <sleep> is 2.
function run_telnet {
    (echo "$2"; sleep ${3:-2}) \
        | telnet localhost $1 2>&1
}

# Blocks until ping to 0::0 suceeds.
function wait_vm_up {
    local timeout_counter=0
    local timeout_max=50
    echo -n "Waiting for VM listening on telnet port $1 to get ready..."
    while ( ! (run_telnet $1 "ping6 -c 1 0::0" 5 | grep "1 received" \
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
