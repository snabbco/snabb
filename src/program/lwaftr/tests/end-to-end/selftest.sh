#!/bin/sh
cd "`dirname \"$0\"`"
./end-to-end.sh
./end-to-end-vlan.sh
