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
run_qemu_tap "$NODE_BIND0" "$BOOTARGS0" "$IMAGE0" "$GUEST_MAC0" "$TELNET_PORT0" "$TAP0"

# Execute 2nd instance
run_qemu_tap "$NODE_BIND1" "$BOOTARGS1" "$IMAGE1" "$GUEST_MAC1" "$TELNET_PORT1" "$TAP1"

printf "All instances running.\n"
printf "Connect to guests with:\n"
printf "telnet localhost $TELNET_PORT0\n"
printf "telnet localhost $TELNET_PORT1\n"

wait_qemus
