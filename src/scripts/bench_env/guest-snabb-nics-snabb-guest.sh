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
. $(dirname $0)/common.sh

# Execute snabbswitch - QEMU instance
export NFV_PCI=$NFV_PCI0 NFV_SOCKET=$NFV_SOCKET0
numactl --cpunodebind=$NODE_BIND0 --membind=$NODE_BIND0 \
    $SNABB $NFV > $SNABB_LOG0 2>&1 &
SNABB_PID0=$!

# Execute QEMU, remove redirection for verbosity
run_qemu_vhost_user "$NODE_BIND0" "$BOOTARGS0" "$IMAGE0" "$GUEST_MAC0" "$TELNET_PORT0" "$NFV_SOCKET0"

# Add another snabbswitch - QEMU instance
export NFV_PCI=$NFV_PCI1 NFV_SOCKET=$NFV_SOCKET1
numactl --cpunodebind=$NODE_BIND1 --membind=$NODE_BIND1 \
    $SNABB $NFV > $SNABB_LOG1 2>&1 &
SNABB_PID1=$!

# Execute QEMU, remove redirection for verbosity
run_qemu_vhost_user "$NODE_BIND1" "$BOOTARGS1" "$IMAGE1" "$GUEST_MAC1" "$TELNET_PORT1" "$NFV_SOCKET1"

printf "All instances running.\n"
printf "Connect to guests with:\n"
printf "telnet localhost $TELNET_PORT0\n"
printf "telnet localhost $TELNET_PORT1\n"

wait_qemus
