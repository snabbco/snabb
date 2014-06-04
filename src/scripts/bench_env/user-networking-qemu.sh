#! /bin/sh
#
# Create a VM with user networking support of QEMU.
# Handy for quickly accessing the local and remote network
# from the VM when needed.
#
# Topology:
# guest -> user_networking <- host
#

GUESTS="1"
. $(dirname $0)/include_checks.sh

# Execute QEMU
    $QEMU \
        -M pc -cpu kvm64 -smp 1 -cpu host --enable-kvm \
        -m $GUEST_MEM -numa node,memdev=mem \
        -object memory-file,id=mem,size=$GUEST_MEM"M",mem-path=$HUGETLBFS,share=on \
        -device virtio-net-pci,netdev=net0,mac=$GUEST_MAC0 \
        -netdev type=user,id=net0 \
        -kernel $KERNEL -append "$BOOTARGS0" \
        -drive if=virtio,file=$IMAGE0 \
        -nographic
