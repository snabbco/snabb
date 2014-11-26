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
. $(dirname $0)/common.sh

# Execute snabbswitch and pin it to the proper node (CPU and memory)
run_nfv ${NODE_BIND0?} ${NFV_PCI0?} ${NFV_SOCKET0?} ${SNABB_LOG0?}

# Execute QEMU on the same node
run_qemu_vhost_user "${NODE_BIND0?}" "${BOOTARGS0?}" "${IMAGE0?}" "${GUEST_MAC0?}" "${TELNET_PORT0?}" "${NFV_SOCKET0?}"

wait_qemus
