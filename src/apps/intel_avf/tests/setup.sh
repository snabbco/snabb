#!/bin/bash

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
       echo 1 > "$pfdir/sriov_numvfs"
       sleep 1

       local vfdir=$( readlink -f $pfdir/virtfn0 )
       local vfnic=$( ls $vfdir/net )

       ip link set $nic vf 0 mac $mac
       local vfid=$( basename $( readlink -f $vfdir ) )
       echo $vfid > $vfdir/driver/unbind
       echo $vfid
}

SNABB_AVF_VF0=$(setup $SNABB_AVF_PF0 02:00:00:00:00:00)
SNABB_AVF_VF1=$(setup $SNABB_AVF_PF1 02:00:00:00:00:01)
echo export SNABB_AVF_VF0=$SNABB_AVF_VF0
echo export SNABB_AVF_VF1=$SNABB_AVF_VF1
