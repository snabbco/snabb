#!/bin/sh

set -e

for ib_iface in $(lspci | grep Mellanox | awk '{print $1}')
do
	sudo setpci -s $ib_iface 68.W=4096
done

for dev in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
do
    echo performance | sudo tee $dev > /dev/null
done
