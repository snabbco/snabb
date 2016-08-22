#!/usr/bin/env bash

SNABB_LWAFTR="../../../../snabb lwaftr" \
TEST_BASE=../data/vlan \
TEST_OUT=/tmp \
EMPTY=${TEST_BASE}/../empty.pcap \
COUNTERS=${TEST_BASE}/../counters \
./core-end-to-end.sh
