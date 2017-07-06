#!/usr/bin/env bash

IFACE=mgmt0
IP=10.21.21.1/24

if [ -n "$1" ]
then
    sleep 0.5s
    if [ "$1" = ${IFACE} ]; then
        ip li set up dev ${IFACE}
        ip addr add ${IP} dev ${IFACE}
        sleep 0.5s
    fi;
    exit 0
else
    echo "No interface specified."
    exit 1
fi
