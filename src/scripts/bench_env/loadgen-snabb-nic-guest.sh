#! /bin/bash
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

LOADGENPCIS=$NFV_PCI1
LOADGENNODE=$NODE_BIND1

VMPCIS=$NFV_PCI0
VMNODE=$NODE_BIND0
VMARGS=$BOOTARGS0
#All VMs same MAC - fix that if important!
VMMAC=$GUEST_MAC0
VMPORT=$TELNET_PORT0
VMIMAGE=$IMAGE0
VMNFVLOG=$SNABB_LOG0
VMNFVSOCK=$NFV_SOCKET0

# Execute snabbswitch loadgen instance
if [ -n "$RUN_LOADGEN" ]; then
    run_loadgen "$LOADGENNODE" "$LOADGENPCIS" "$SNABB_LOG1"
fi

printf "Connect to guests with:\n"
count=0
for pci in $VMPCIS; do
    img=${VMIMAGE}${count}
    if [ ! -f $img ]; then
        printf "$img not found\n"
        exit 1
    fi

    port=$((VMPORT+count))
    socket=${VMNFVSOCK}${count}
    # Execute QEMU on the same node
    run_qemu_vhost_user "$VMNODE" "$VMARGS" "$img" "$VMMAC" "$port" "$socket"
    printf "telnet localhost $port\n"

    log=${VMNFVLOG}${count}
    # Execute snabbswitch and pin it to a proper node (CPU and memory)
    run_nfv "$VMNODE" "$pci" "$socket" "$log"
    
    count=$((count+1))
done

# wait it to end
wait_snabbs

# print stats
count=0
totalmpps=0
for pci in $VMPCIS; do
    log=${VMNFVLOG}${count}
    mpps=`awk -F' ' '/Mpps/ {print $2}' $log`
    printf "On $pci got $mpps\n"
    count=$((count+1))
    totalmpps=`echo $totalmpps $mpps|awk '{ print $1+$2 }'`
done
printf "Rate(Mpps):\t$totalmpps\n"

# shutdown VMs
port=$VMPORT
for pci in $VMPCIS; do
    port=$((port+1))
    { echo "poweroff"; sleep 1; } | telnet localhost $port > /dev/null 2>&1
done
