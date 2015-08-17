#!/bin/bash

function cleanup() {
   rm -f /var/run/snabb/link/*

   DMA_IDS="/var/run/snabb/dma_map_ids"
   if [ -e "$DMA_IDS" ]; then
      od -j4 -vi -w4 "$DMA_IDS" | while read offst id; do
         if [ -n "$id" -a "$id" != '0' ]; then
            ipcrm -m $id
         fi
      done
      rm "$DMA_IDS"
   fi
}


cleanup
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
cleanup
