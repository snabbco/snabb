#!/usr/bin/env bash

TEST_DIR="./program/lwaftr/tests"

source ${TEST_DIR}/common.sh

check_for_root

echo "Testing lwaftr bench"

DATA_DIR="${TEST_DIR}/data"
BENCHDATA_DIR="${TEST_DIR}/benchdata"

./snabb lwaftr bench --duration 1 --bench-file bench.csv \
    ${DATA_DIR}/icmp_on_fail.conf \
    ${BENCHDATA_DIR}/ipv{4,6}-0550.pcap &> /dev/null
assert_equal $? 0 "lwaftr bench failed with error code $?"
assert_file_exists ./bench.csv --remove

./snabb lwaftr bench --reconfigurable --duration 1 --bench-file bench.csv \
    ${DATA_DIR}/icmp_on_fail.conf \
    ${BENCHDATA_DIR}/ipv{4,6}-0550.pcap &> /dev/null
assert_equal $? 0 "lwaftr bench --reconfigurable failed with error code $?"
assert_file_exists ./bench.csv --remove
