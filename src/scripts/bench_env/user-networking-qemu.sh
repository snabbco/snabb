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
. $(dirname $0)/common.sh

# Execute QEMU without NETDEV
run_qemu "${NODE_BIND0?}" "${BOOTARGS0?}" "${IMAGE0?}" "${GUEST_MAC0?}" "${TELNET_PORT0?}" "-netdev user,id=net0"

wait_qemus
