#!/bin/bash

if [ -z "$ASSETSOURCE" ]; then
    export ASSETSOURCE="cp -v /home/max/public_html/test_env"
    echo "Defaulting to ASSETSOURCE=$ASSETSOURCE"
fi

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

#calculate and set MQ related variables
if [ -n "$QUEUES" ]; then
    export MQ=on
else
    export MQ=off
    export QUEUES=1
    echo "Defaulting to QUEUES=$QUEUES"
fi
export SMP=$QUEUES
export VECTORS=$((2*$QUEUES + 1))

export pids=""
export sockets=""
export assets=$HOME/.test_env
export qemu=qemu/obj/x86_64-softmmu/qemu-system-x86_64

export snabb_n=0

function pci_node {
    cpu=$(cat /sys/class/pci_bus/${1:0:7}/cpulistaffinity | cut -d "-" -f 1)
    numactl -H | grep "cpus: $cpu" | cut -d " " -f 2
}

function snabb_log {
    echo "snabb${snabb_n}.log"
}

function snabb {
    numactl --cpunodebind=$(pci_node $1) --membind=$(pci_node $1) \
        ./snabb $2 \
        > $(snabb_log) 2>&1 &
    pids="$pids $!"
    snabb_n=$(expr $snabb_n + 1)
}

export qemu_n=0

function qemu_log {
    echo "qemu${qemu_n}.log"
}

function qemu_image {
    image=$assets/qemu${qemu_n}.img
    [ -f $image ] || cp $assets/qemu.img $image
    echo $image
}

function provide_qemu {
    if ! [ -d $assets/qemu ]; then
        echo "Fetching qemu source code:"
        (cd $assets
            $ASSETSOURCE/qemu.tar.gz .
            tar xzf qemu.tar.gz
            rm qemu.tar.gz)
    fi
    echo "Building qemu:"
    (cd $assets/qemu
        mkdir obj
        cd obj
        ../configure --target-list=x86_64-softmmu
        make -j4)
}

function provide_bzImage {
    echo "Fetching bzImage:"
    (cd $assets
        $ASSETSOURCE/bzImage .)
}

function provide_img {
    echo "Fetching qemu.img:"
    (cd $assets
        $ASSETSOURCE/qemu.img .)
}

function provide_assets {
    mkdir -p $assets
    [ -f $assets/$qemu ]    || provide_qemu
    [ -f $assets/bzImage ]  || provide_bzImage
    [ -f $assets/qemu.img ] || provide_img
}

function mac {
    printf "$MAC%02X\n" $1
}

function ip {
    printf "$IP%04X\n" $1
}

function qemu {
    provide_assets
    if [ ! -n $QUEUES ]; then
        MQUEUES=",queues=$QUEUES"
    fi
    numactl --cpunodebind=$(pci_node $1) --membind=$(pci_node $1) \
        $assets/$qemu \
        -kernel $assets/bzImage \
        -append "earlyprintk root=/dev/vda rw console=ttyS0 ip=$(ip $qemu_n)" \
        -m $GUEST_MEM -numa node,memdev=mem -object memory-backend-file,id=mem,size=${GUEST_MEM}M,mem-path=$HUGETLBFS,share=on \
        -netdev type=vhost-user,id=net0,chardev=char0${MQUEUES} -chardev socket,id=char0,path=$2,server \
        -device virtio-net-pci,netdev=net0,mac=$(mac $qemu_n),mq=$MQ,vectors=$VECTORS \
        -M pc -smp $SMP -cpu host --enable-kvm \
        -serial telnet:localhost:$3,server,nowait \
        -drive if=virtio,file=$(qemu_image) \
        -nographic > $(qemu_log) 2>&1 &
    pids="$pids $!"
    qemu_n=$(expr $qemu_n + 1)
    sockets="$sockets $2"
}


function on_exit {
    for pid in "$pids"; do
        kill -9 $pid > /dev/null 2>&1
    done
    rm -f $sockets
    exit
}

trap on_exit EXIT HUP INT QUIT TERM
