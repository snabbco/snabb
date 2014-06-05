#! /bin/sh
#
# Create two Snabbswitch nfv instances. Each instance connects a separate
# VM to a NIC through Snabbswitch to create a closed loop between the
# physically wired NICs. Consult NIC wiring table for connections.
#
# Terminal access to the VMs can be done separately by the user through telnet.
#
# Topology:
# guest0 -> snabbswitch nfv0 -> NIC0 = NIC1 <- snabbswitch nfv1 <- guest1
#

GUESTS="2"
. $(dirname $0)/include_checks.sh

# Execute snabbswitch - QEMU instance
export NFV_PCI=$NFV_PCI0 NFV_SOCKET=$NFV_SOCKET0
numactl --cpunodebind=$NODE_BIND0 --membind=$NODE_BIND0 \
    $SNABB $NFV > $SNABB_LOG0 2>&1 &
SNABB_PID0=$!

# Execute QEMU, remove redirection for verbosity
numactl --cpunodebind=$NODE_BIND0 --membind=$NODE_BIND0 \
    $QEMU \
        -M pc -cpu kvm64 -smp 1 -cpu host --enable-kvm \
        -m $GUEST_MEM -numa node,memdev=mem \
        -object memory-file,id=mem,size=$GUEST_MEM"M",mem-path=$HUGETLBFS,share=on \
        -chardev socket,id=char0,path=$NFV_SOCKET0,server \
        -netdev type=vhost-user,id=net0,chardev=char0 \
        -device virtio-net-pci,netdev=net0,mac=$GUEST_MAC0 \
        -serial telnet:localhost:$TELNET_PORT0,server,nowait \
        -kernel $KERNEL -append "$BOOTARGS0" \
        -drive if=virtio,file=$IMAGE0 \
        -nographic > /dev/null 2>&1 &
QEMU_PID0=$!

# Add another snabbswitch - QEMU instance
export NFV_PCI=$NFV_PCI1 NFV_SOCKET=$NFV_SOCKET1
numactl --cpunodebind=$NODE_BIND1 --membind=$NODE_BIND1 \
    $SNABB $NFV > $SNABB_LOG1 2>&1 &
SNABB_PID1=$!

# Execute QEMU, remove redirection for verbosity
numactl --cpunodebind=$NODE_BIND1 --membind=$NODE_BIND1 \
    $QEMU \
        -M pc -cpu kvm64 -smp 1 -cpu host --enable-kvm \
        -m $GUEST_MEM -numa node,memdev=mem \
        -object memory-file,id=mem,size=$GUEST_MEM"M",mem-path=$HUGETLBFS,share=on \
        -chardev socket,id=char0,path=$NFV_SOCKET1,server \
        -netdev type=vhost-user,id=net0,chardev=char0 \
        -device virtio-net-pci,netdev=net0,mac=$GUEST_MAC1 \
        -serial telnet:localhost:$TELNET_PORT1,server,nowait \
        -kernel $KERNEL -append "$BOOTARGS1" \
        -drive if=virtio,file=$IMAGE1 \
        -nographic > /dev/null 2>&1 &
QEMU_PID1=$!

printf "All instances running.\n"
printf "Connect to guests with:\n"
printf "telnet localhost $TELNET_PORT0\n"
printf "telnet localhost $TELNET_PORT1\n"
