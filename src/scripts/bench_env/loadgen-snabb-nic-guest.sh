#! /bin/sh
#
# Create a snabbswitch loadgen and nfv instance which connect to the
# selected NICs and one guest. The selected NICs should be physically
# wired in order to route traffic from loadgen to the guest.
#
# Consult NIC wiring table for connections.
#
# Topology:
# snabbswitch loadgen -> NIC_0 = NIC_1 <- snabbswitch nfv <- guest
#

GUESTS="1"
. $(dirname $0)/include_checks.sh

# Execute snabbswitch loadgen instance
numactl --cpunodebind=$NODE_BIND1 --membind=$NODE_BIND1 \
    $SNABB $LOADGEN $PCAP $NFV_PCI1 > $SNABB_LOG1 2>&1 &
SNABB_PID1=$!

# Execute snabbswitch and pin it to a proper node (CPU and memory)
export NFV_PCI=$NFV_PCI0 NFV_SOCKET=$NFV_SOCKET0
numactl --cpunodebind=$NODE_BIND1 --membind=$NODE_BIND0 \
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

# Kill snabbswitch instances
kill $SNABB_PID0 $SNABB_PID1
rm $NFV_SOCKET0

printf "Exit.\n"
