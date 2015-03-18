#! /bin/sh
#
# Create neutron NFV instance with two virtual machines, talking to one NIC
#
# Terminal access to the VMs can be done separately by the user through telnet.
#

GUESTS="2"
. $(dirname $0)/common.sh

# Execute snabbswitch - QEMU instance
run_neutron_nfv "$NODE_BIND0" "$NFV_PCI0" "$NEUTRON_SOCKET_TEMPLATE" "$SNABB_LOG0" "" "$NFV_TRACE0"

sleep 3

# Execute QEMU, remove redirection for verbosity
run_qemu_vhost_user "$NODE_BIND0" "$BOOTARGS0" "$IMAGE0" "$GUEST_MAC0" "$TELNET_PORT0" "$NFV_SOCKET0" "" "$GUEST_LOG0"

# Execute QEMU, remove redirection for verbosity
run_qemu_vhost_user "$NODE_BIND1" "$BOOTARGS1" "$IMAGE1" "$GUEST_MAC1" "$TELNET_PORT1" "$NFV_SOCKET1" "" "$GUEST_LOG1"

printf "All instances running.\n"
printf "Connect to guests with:\n"
printf "telnet localhost $TELNET_PORT0\n"
printf "telnet localhost $TELNET_PORT1\n"

wait_qemus
