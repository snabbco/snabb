#! /bin/bash
#
# Create a snabbswitch fuzz instance which connect one guest.
#
# Topology:
# snabbswitch fuzz <-> guest
#

GUESTS="1"
. $(dirname $0)/common.sh

VMNODE=$NODE_BIND0
VMARGS=$BOOTARGS0
#All VMs same MAC - fix that if important!
VMMAC=$GUEST_MAC0
VMPORT=$TELNET_PORT0
VMIMAGE=$IMAGE0
VMFUZZLOG=$SNABB_LOG0
VMFUZZSOCK=$NFV_SOCKET0


printf "Connect to guests with:\n"
count=0
node=0
cpu=0
img=${VMIMAGE}${count}
if [ ! -f $img ]; then
    printf "$img not found\n"
    exit 1
fi

port=$VMPORT
socket=${VMFUZZSOCK}

# Execute QEMU on the same node
run_qemu_vhost_user "$node" "$VMARGS" "$img" "$VMMAC" "$port" "$socket" "$cpu"
printf "telnet localhost $port\n"

# snabb will use "next" cpu
cpu=$((cpu+1))
if [ "$VMFUZZLOG" = "/dev/null" ]; then
    log="/tmp/fuzz"
else
    log=${VMFUZZLOG}
fi

# Execute snabbswitch and pin it to a proper node (CPU and memory)
run_fuzz "$node" "$socket" "$log" "$cpu"

# wait it to end
wait_snabbs

# print stats
count=0
totalmpps=0
if [ "$VMFUZZLOG" = "/dev/null" ]; then
    log="/tmp/fuzz"
else
    log=${VMFUZZLOG}
fi

printf "$log has the output of your fuzz test run\n"

# shutdown VMs
port=$VMPORT
{ echo "poweroff"; sleep 1; } | telnet localhost $port > /dev/null 2>&1
