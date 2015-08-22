#!/bin/bash

rm -f /var/run/snabb/link/*
./snabb gc

./snabb snsh program/spoon/produce.lua net1 12 &
./snabb snsh program/spoon/consume.lua net1 13 &

./snabb snsh program/spoon/produce.lua net2 14 &
./snabb snsh program/spoon/consume.lua net2 15 &

./snabb snsh program/spoon/produce.lua net3 16 &
./snabb snsh program/spoon/consume.lua net3 17 &

./snabb snsh program/spoon/produce.lua net4 18 &
./snabb snsh program/spoon/consume.lua net4 19 &

./snabb snsh program/spoon/produce.lua net5 20 &
./snabb snsh program/spoon/consume.lua net5 21 &

./snabb snsh program/spoon/produce.lua net6 22 &
./snabb snsh program/spoon/consume.lua net6 23 &

wait -n
wait -n
wait -n
wait -n
wait -n
wait -n

for j in $(jobs -pr); do
   kill $j
done

./snabb gc
