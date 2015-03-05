#! /bin/sh
#
# Usage: host-nic-snabbnfv-guests.sh <nfvconf>
#
# <nfvconf> must be a path to a snabbnfv-traffic configuration file.
#
# Create a snabbnfv-traffic instance which connects two VMs to a NIC
# interface. The VMs communication is governed by the snabbnfv-traffic
# instance.
#
# Topology:
# guest_port0 -> snabbnfv-traffic <- guest_port1
#                       |
#                      NIC0

GUESTS="2"
. $(dirname $0)/common.sh

# Execute snabbswitch and pin it to the proper node (CPU and memory)
export NFV_PCI=${NFV_PCI0?}
numactl --cpunodebind=${NODE_BIND0?} --membind=${NODE_BIND0?} \
    $SNABB snabbnfv traffic ${NFV_PCI0?} ${1?} vhost_%s.sock \
    > /tmp/bench-env-traffic.${NFV_PCI0?} 2>&1 &
SNABB_PID0=$!

# Execute QEMU on the same node
run_qemu_vhost_user "${NODE_BIND0?}" "${BOOTARGS0?}" "${IMAGE0?}" "${GUEST_MAC0?}" "${TELNET_PORT0?}" "${NFV_SOCKET0?}"
run_qemu_vhost_user "${NODE_BIND0?}" "${BOOTARGS1?}" "${IMAGE1?}" "${GUEST_MAC1?}" "${TELNET_PORT1?}" "${NFV_SOCKET1?}"

wait_qemus
