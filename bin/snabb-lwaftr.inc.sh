#!/bin/bash

nic_exists() {
   local nic=$1

   local devices=/sys/bus/pci/devices
   if [ -d "$devices/$nic" ] || [ -d "$devices/0000:$nic" ]; then
      return 0
   fi
   return 1
}

whereis_snabb_src() {
  # Locate snabb executable and find out source folder
  local snabb_exe=`which snabb`
  if [ -z "$snabb_exe" ]; then
     error "Couldn't find snabb executable"
  fi
  local snabb_src=`dirname $snabb_exe`
  echo $snabb_src
}
