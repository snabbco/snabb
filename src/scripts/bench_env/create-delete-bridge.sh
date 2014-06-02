#! /bin/bash
#
# Create or delete a bridge with two taps for the guests to connect.
#

# Check if the script was executed as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Check number of provided arguments and sanity of first argument
if [ "$#" -lt 3 ] || [ "$1" != "add" ] && [ "$1" != "del" ] ; then
	echo "Usage: ./create-delete-bridge.sh [add | del] [bridge_name] [tap_name] [tap_name]"
fi

if [ "$1" == "add" ] ; then
	brctl addbr $2

	tunctl -u `echo $USER` -t $3
	tunctl -u `echo $USER` -t $4

	ifconfig $3 0.0.0.0 up
	ifconfig $4 0.0.0.0 up

	brctl addif $2 $3
	brctl addif $2 $4

	ifconfig $2 up
elif [ "$1" == "del" ] ; then
	ifconfig $2 down
	ifconfig $3 down
	ifconfig $4 down

	brctl delif $2 $3
	brctl delif $2 $4

	tunctl -d $3
	tunctl -d $4

	brctl delbr $2
fi
