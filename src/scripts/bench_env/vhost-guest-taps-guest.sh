#! /bin/sh
#
# Create two guests connected through a bridge and two taps in vhost mode.
# Usefull for mearuing network traffic not exiting the host.
#
# Terminal access to the VMs can be done separately by the user through telnet.
#
# Topology:
# guest0 -> vhost,tap0 -> bridge <- vhost,tap1 <- guest1
#

GUESTS="2"
. $(dirname $0)/common.sh

# Execute QEMU, remove redirection for verbosity
numactl --cpunodebind=$NODE_BIND0 --membind=$NODE_BIND0 \
    $QEMU \
        -M pc -cpu kvm64 -smp 1 -cpu host --enable-kvm \
        -m $GUEST_MEM -numa node,memdev=mem \
        -object memory-backend-file,id=mem,size=$GUEST_MEM"M",mem-path=$HUGETLBFS,share=on \
        -netdev type=tap,id=net0,script=no,downscript=no,vhost=on,ifname=$TAP0 \
        -device virtio-net-pci,netdev=net0,mac=$GUEST_MAC0 \
        -serial telnet:localhost:$TELNET_PORT0,server,nowait \
        -kernel $KERNEL -append "$BOOTARGS0" \
        -drive if=virtio,file=$IMAGE0 \
        -nographic > /dev/null 2>&1 &

# Execute 2nd instance
numactl --cpunodebind=$NODE_BIND1 --membind=$NODE_BIND1 \
    $QEMU \
        -M pc -cpu kvm64 -smp 1 -cpu host --enable-kvm \
        -m $GUEST_MEM -numa node,memdev=mem \
        -object memory-backend-file,id=mem,size=$GUEST_MEM"M",mem-path=$HUGETLBFS,share=on \
        -netdev type=tap,id=net0,script=no,downscript=no,vhost=on,ifname=$TAP1 \
        -device virtio-net-pci,netdev=net0,mac=$GUEST_MAC1 \
        -serial telnet:localhost:$TELNET_PORT1,server,nowait \
        -kernel $KERNEL -append "$BOOTARGS1" \
        -drive if=virtio,file=$IMAGE1 \
        -nographic > /dev/null 2>&1 &

printf "All instances running.\n"
printf "Connect to guests with:\n"
printf "telnet localhost $TELNET_PORT0\n"
printf "telnet localhost $TELNET_PORT1\n"
