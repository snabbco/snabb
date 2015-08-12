#!/bin/bash

function cleanup() {
   rm -f /var/run/snabb/link/spoon_link

   for idfile in /tmp/0x*0000; do
      [ -e "$idfile" ] || break;
      id=$(< $idfile)
      ipcrm -m $id
      rm $idfile
   done
}


cleanup
./snabb snsh program/spoon/produce.lua &
./snabb snsh program/spoon/consume.lua
echo "consumed"

for j in $(jobs -pr); do
   kill $j
done
cleanup
