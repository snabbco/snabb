#!/bin/bash

function cleanup() {
   rm -f /var/run/snabb/link/spoon_link
   
   if [ -e /var/run/snabb/dma_map_ids ]; then
      od -j4 -vi -w4 "$mapname" | while read offst id; do
         if [ -n "$id" -a "$id" != '0' ]; then
            ipcrm -m $id
         fi
      done
      rm /var/run/snabb/dma_map_ids
   fi
}


cleanup
./snabb snsh program/spoon/produce.lua &
./snabb snsh program/spoon/consume.lua

for j in $(jobs -pr); do
   kill $j
done
cleanup
