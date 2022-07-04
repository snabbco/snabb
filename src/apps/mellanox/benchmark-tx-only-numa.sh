#!/usr/bin/env bash

echo i,core_A,core_B,score,unit
for i in `seq 5`; do
    for A in `seq 12 23`; do
        for B in `seq 12 23`; do
            out=$(./snabb snsh apps/mellanox/benchmark.snabb -a 81:00.0 -b 81:00.1 -A $A -B $B)
            score=$(echo "$out" | grep "Tx Rate" | cut -d " " -f 4)
            unit=$(echo "$out" | grep "Tx Rate" | cut -d " " -f 5)
            echo "$i,$A,$B,$score,$unit"
        done
    done
done