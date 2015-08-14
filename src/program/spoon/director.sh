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
./snabb snsh program/spoon/produce.lua &
./snabb snsh program/spoon/consume.lua &

wait -n
for j in $(jobs -pr); do
   kill $j
done
cleanup
