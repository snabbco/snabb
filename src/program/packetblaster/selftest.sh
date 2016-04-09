#!/usr/bin/env bash

echo "selftest: packetblaster"

# do tests first that don't require PCI

function test_lwaftr_pcap {
  PCAP=$1
  shift
  TEMP_PCAP=/tmp/lwaftr$$.pcap
  echo "testing lwaftr pcap $PCAP ..."
  ./snabb packetblaster lwaftr --pcap $TEMP_PCAP $@
  status=$?
  if [ $status != 0 ]; then
    echo "Error: lwaftr pcap generation failed for ${PCAP} with ${status}"
    rm $TEMP_PCAP
    exit 1
  fi
  cmp $TEMP_PCAP $PCAP
  rm $TEMP_PCAP
  if [ $status != 0 ]; then
    echo "Error: lwaftr generated pcap differs from ${PCAP}"
    exit 1
  fi
}

test_lwaftr_pcap program/packetblaster/lwaftr/test_lwaftr_1.pcap --count 1
test_lwaftr_pcap program/packetblaster/lwaftr/test_lwaftr_2.pcap --count 2 --vlan 100 --size 0

export PCIADDR=$SNABB_PCI_INTEL0
[ ! -z "$PCIADDR" ] || export PCIADDR=$SNABB_PCI0
if [ -z "${PCIADDR}" ]; then
    echo "selftest: skipping test - SNABB_PCI_INTEL0/SNABB_PCI0 not set"
    exit 43
fi
 
# Simple test: Just make sure packetblaster runs for a period of time
# (doesn't crash on startup).
timeout 5 ./snabb packetblaster replay program/snabbnfv/test_fixtures/pcap/64.pcap ${PCIADDR}
status=$?
if [ $status != 124 ]; then
    echo "Error: expected timeout (124) but got ${status}"
    exit 1
fi

timeout 5 ./snabb packetblaster synth --src 11:11:11:11:11:11 --dst 22:22:22:22:22:22 --sizes 64,128,256 ${PCIADDR}
status=$?
if [ $status != 124 ]; then
    echo "Error: expected timeout (124) but got ${status}"
    exit 1
fi

timeout 5 ./snabb packetblaster lwaftr --pci ${PCIADDR}
status=$?
if [ $status != 124 ]; then
    echo "Error: expected timeout (124) but got ${status}"
    exit 1
fi

echo "selftest: ok"
