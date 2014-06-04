#! /bin/sh
#
# Create a snabbswitch NFV instance which connects a VM to snabbswitch
# and a NIC interface. The connected NIC is physically wired with another,
# which can be used normally by the host to check traffic.
#
# Consult NIC wiring table for connections.
#
# Topology:
# guest -> snabbswitch -> NIC_0 = NIC_1 <- host
#

GUESTS="1"
. $(dirname $0)/include_checks.sh

# Execute snabbswitch and pin it to the proper node (CPU and memory)
export NFV_PCI=$NFV_PCI0 NFV_SOCKET=$NFV_SOCKET0
numactl --cpunodebind=$NODE_BIND0 --membind=$NODE_BIND0 \
    $SNABB $NFV > $SNABB_LOG0 2>&1 &
SNABB_PID0=$!

# Execute QEMU on the same node
numactl --cpunodebind=$NODE_BIND0 --membind=$NODE_BIND0 \
    $QEMU \
        -M pc -cpu kvm64 -smp 1 -cpu host --enable-kvm \
        -m $GUEST_MEM -numa node,memdev=mem \
        -object memory-file,id=mem,size=$GUEST_MEM"M",mem-path=$HUGETLBFS,share=on \
        -chardev socket,id=char0,path=$NFV_SOCKET0,server \
        -netdev type=vhost-user,id=net0,chardev=char0 \
        -device virtio-net-pci,netdev=net0,mac=$GUEST_MAC0 \
        -kernel $KERNEL -append "$BOOTARGS0" \
        -drive if=virtio,file=$IMAGE0 \
        -nographic

# Kill snabbswitch instance and clean lef over socket files
kill $SNABB_PID0
rm $NFV_SOCKET0

printf "Exit.\n"
