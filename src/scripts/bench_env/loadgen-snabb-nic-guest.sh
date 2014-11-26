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

LOADGENPCIS=${NFV_PCI1?}
LOADGENNODE=${NODE_BIND1?}
LOADGENLOG=${SNABB_LOG1?}

VMPCIS=${NFV_PCI0?}
VMNODE=${NODE_BIND0?}
VMARGS=${BOOTARGS0?}
#All VMs same MAC - fix that if important!
VMMAC=${GUEST_MAC0?}
VMPORT=${TELNET_PORT0?}
VMIMAGE=${IMAGE0?}
VMNFVLOG=${SNABB_LOG0?}
VMNFVSOCK=${NFV_SOCKET0?}

# Execute snabbswitch loadgen instance
if [ -n "$RUN_LOADGEN" ]; then
    # up to 4 numa nodes
    for n in 0 1 2 3; do
        ports=""
        for pci in $LOADGENPCIS; do
            node=`awk -F' ' "/$pci/ {print \\$2}" /etc/pci_affinity.conf`
            if [ "$node" -eq "$n" ]; then
                ports="$ports $pci"
            fi
        done
        if [ -n "$ports" ]; then
            if [ "$LOADGENLOG" = "/dev/null" ]; then
                log=$LOADGENLOG
            else
                log=${LOADGENLOG}${n}
            fi
            run_loadgen "$n" "$ports" "$log"
        fi
    done
else
    # RUN_LOADGEN not set, not running loadgen. Let's let the user know.
    echo "RUN_LOADGEN is unset. Not running loadgen."
fi

printf "Connect to guests with:\n"
count=0
for pci in $VMPCIS; do
    node=`awk -F' ' "/$pci/ {print \\$2}" /etc/pci_affinity.conf`
    cpu=`awk -F' ' "/$pci/ {print \\$3}" /etc/pci_affinity.conf`

    img=${VMIMAGE}${count}
    if [ ! -f $img ]; then
        printf "$img not found\n"
        exit 1
    fi

    port=$((VMPORT+count))
    socket=${VMNFVSOCK}${count}
    # Execute QEMU on the same node
    run_qemu_vhost_user "$node" "$VMARGS" "$img" "$VMMAC" "$port" "$socket" "$cpu"
    printf "telnet localhost $port\n"

    # snabb will use "next" cpu
    cpu=$((cpu+1))
    if [ "$VMNFVLOG" = "/dev/null" ]; then
        log="/tmp/nfv${pci}"
    else
        log=${VMNFVLOG}${count}
    fi

    # Execute snabbswitch and pin it to a proper node (CPU and memory)
    run_nfv "$node" "$pci" "$socket" "$log" "$cpu"

    count=$((count+1))
done

# wait it to end
wait_snabbs

# print stats
count=0
totalmpps=0
for pci in $VMPCIS; do
    if [ "$VMNFVLOG" = "/dev/null" ]; then
        log="/tmp/nfv${pci}"
    else
        log=${VMNFVLOG}${count}
    fi
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
