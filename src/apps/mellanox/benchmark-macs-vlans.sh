#!/usr/bin/env bash

echo i,macs,vlans,txrate,txdrop,txerror,rxrate,rxdrop,rxerror
for i in `seq 1 3`; do
    for macs in `seq 4 4 24`; do
        for vlans in `seq 0 4 24`; do
            out=$(./snabb snsh apps/mellanox/benchmark.snabb -a 81:00.0 -b 81:00.1 -A 6-11 -B 12-17 \
                    -m source-fwd -w 6 -q 4 -e $macs -v $vlans)
            txrate=$(echo "$out" | grep "Tx Rate is" | cut -d " " -f 4)
            txdrop=$(echo "$out" | grep "Tx Drop Rate is" | cut -d " " -f 5)
            txerror=$(echo "$out" | grep "Tx Error Rate is" | cut -d " " -f 5)
            rxrate=$(echo "$out" | grep "Rx Rate is" | cut -d " " -f 4)
            rxdrop=$(echo "$out" | grep "Rx Drop Rate is" | cut -d " " -f 5)
            rxerror=$(echo "$out" | grep "Rx Error Rate is" | cut -d " " -f 5)
            echo "$i,$macs,$vlans,$txrate,$txdrop,$txerror,$rxrate,$rxdrop,$rxerror"
        done
    done
done