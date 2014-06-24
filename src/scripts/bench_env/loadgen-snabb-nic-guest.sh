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
. $(dirname $0)/common.sh

# Execute snabbswitch loadgen instance
numactl --cpunodebind=$NODE_BIND1 --membind=$NODE_BIND1 \
    $SNABB $LOADGEN $PCAP $NFV_PCI1 > $SNABB_LOG1 2>&1 &
SNABB_PID1=$!

# Execute QEMU on the same node
run_qemu_vhost_user "$NODE_BIND0" "$BOOTARGS0" "$IMAGE0" "$GUEST_MAC0" "$TELNET_PORT0" "$NFV_SOCKET0"

printf "Connect to guests with:\n"
printf "telnet localhost $TELNET_PORT0\n"

# Execute snabbswitch and pin it to a proper node (CPU and memory)
export NFV_PCI=$NFV_PCI0 NFV_SOCKET=$NFV_SOCKET0
numactl --cpunodebind=$NODE_BIND0 --membind=$NODE_BIND0 \
    $SNABB $NFV $NFV_PACKETS

{ echo "poweroff"; sleep 1; } | telnet localhost $TELNET_PORT0 > /dev/null 2>&1
