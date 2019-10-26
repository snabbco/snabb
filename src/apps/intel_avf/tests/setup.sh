#!/usr/bin/env bash

set -e

PFIDX=0
function setup(){
	local pciid=$1
	local mac=$2
	if [ -z "$pciid" ]; then
		echo pciid must be defined
		exit -1
	fi
	local pfdir="/sys/bus/pci/devices/$pciid"
	local drv=$( readlink -f $pfdir/driver)
	if [ -e "$drv" ]; then
		echo $pciid > $drv/unbind
	else
		drv=/sys/bus/pci/drivers/i40e
		echo "pciid" unbound trying $drv
	fi
	sleep 1
	echo $pciid > $drv/bind
	nic=$( ls $pfdir/net )
	ip link set up dev $nic
	echo $(( $# - 1 )) > "$pfdir/sriov_numvfs"
	sleep 1

	local loop=0
	for i in ${@:2}; do
		local vfdir=$( readlink -f $pfdir/virtfn$loop )

		ip link set $nic vf $loop mac $i
		ip link set $nic vf $loop spoofchk off
		ip link set $nic vf $loop trust on || true

		local vfid=$( basename $( readlink -f $vfdir ) )
		echo $vfid > $vfdir/driver/unbind
		echo "export SNABB_AVF_PF${PFIDX}_VF${loop}=$vfid"
                echo "export SNABB_AVF_PF${PFIDX}_SRC${loop}=$i"
                echo "export SNABB_AVF_PF${PFIDX}_DST${loop}=$i"
		loop=$(( loop + 1 ))
	done
	PFIDX=$(( PFIDX + 1 ))
}

ADDR_PF0=(02:00:00:00:00:00 02:00:00:00:00:01)
ADDR_PF1=(02:00:00:00:00:10 02:00:00:00:00:11)
setup $SNABB_AVF_PF0 ${ADDR_PF0[*]}
[ -z $SNABB_AVF_PF1 ] || setup $SNABB_AVF_PF1 ${ADDR_PF1[*]}
