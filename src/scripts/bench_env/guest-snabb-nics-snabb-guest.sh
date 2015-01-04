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
run_nfv ${NODE_BIND0?} ${NFV_PCI0?} ${NFV_SOCKET0?} ${NFV_CONFIG0?} ${SNABB_LOG0?} "" ${NFV_TRACE0?} ${GUEST_MAC0?}

# Execute QEMU, remove redirection for verbosity
run_qemu_vhost_user "${NODE_BIND0?}" "${BOOTARGS0?}" "${IMAGE0?}" "${GUEST_MAC0?}" "${TELNET_PORT0?}" "${NFV_SOCKET0?}"

# Add another snabbswitch - QEMU instance
run_nfv ${NODE_BIND1?} ${NFV_PCI1?} ${NFV_SOCKET1?} ${NFV_CONFIG1?} ${SNABB_LOG1?} "" ${NFV_TRACE1?} ${GUEST_MAC1?}

# Execute QEMU, remove redirection for verbosity
run_qemu_vhost_user "${NODE_BIND1?}" "${BOOTARGS1?}" "${IMAGE1?}" "${GUEST_MAC1?}" "${TELNET_PORT1?}" "${NFV_SOCKET1?}"

printf "All instances running.\n"
printf "Connect to guests with:\n"
printf "telnet localhost $TELNET_PORT0\n"
printf "telnet localhost $TELNET_PORT1\n"

wait_qemus
