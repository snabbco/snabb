#! /bin/sh
#
# Usage: sudo ./rebind-nic.sh 0000:07:00.0
#
# Removes the provided PCI address from the system and rescans
# all PCI devices to re-bind them under their normal kernel driver.
# Usefull when snabbswitch has un-binded a PCI device from the kernel
# and we need to quickly restore it.
#

# Check if the script was executed as root
if [ $(id -u) -ne 0 ]; then
    printf "This script must be run as root\n"
    exit 1
fi

# Check if called properly and rebind the PCI device if so
if [ -n "$1" ] && [ -f "/sys/bus/pci/devices/$1/remove" ] ; then
    echo 1 > /sys/bus/pci/devices/$1/remove
    echo 1 > /sys/bus/pci/rescan
    printf "Re-bind successfull\n"
else
    printf "Usage: sudo ./rebind-nic.sh <PCI address>\n"
    printf "Check if PCI device exists: /sys/bus/pci/devices/$1/remove\n"
    exit 1
fi

