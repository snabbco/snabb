#/usr/bin/env bash

COUNTERS="data/counters"
EMPTY="data/empty.pcap"
TEST_INDEX=0

export COUNTERS

function read_column {
    echo "${TEST_DATA[$1]}"
}

function read_column_pcap {
    index=$1
    column="${TEST_DATA[$index]}"
    if [[ ${#column} == 0 ]];  then
        echo "${EMPTY}"
    else
        echo "${TEST_BASE}/$column"
    fi
}

function print_test_name {
    test_name="$(read_column $TEST_INDEX)"
    echo "Testing: $test_name"
}

function read_test_data {
    conf="${TEST_BASE}/$(read_column $((TEST_INDEX + 1)))"
    in_v4=$(read_column_pcap $((TEST_INDEX + 2)))
    in_v6=$(read_column_pcap $((TEST_INDEX + 3)))
    out_v4=$(read_column_pcap $((TEST_INDEX + 4)))
    out_v6=$(read_column_pcap $((TEST_INDEX + 5)))
    counters="${COUNTERS}/$(read_column $((TEST_INDEX + 6)))"
    echo $conf $in_v4 $in_v6 $out_v4 $out_v6 $counters
}

function next_test {
    TEST_INDEX=$(($TEST_INDEX + 7))
    if [[ $TEST_INDEX -lt $TEST_SIZE ]]; then
        return 0
    else
        return 1
    fi
}

# Contains an array of test cases.
#
# A test case is a group of 7 data fields, structured as 3 rows:
#  - "test_name"
#  - "snabbvmx_conf" "v4_in.pcap" "v6_in.pcap" "v4_out.pcap" "v6_out.pcap"
#  - "counters"
#
# Notice spaces and new lines are not taken into account.
TEST_DATA=(
    "IPv6 fragments and fragmentation is off"
    "snabbvmx-lwaftr-xe1.cfg" "" "regressiontest-signedntohl-frags.pcap" "" ""
    "drop-all-ipv6-fragments.lua"
)
TEST_SIZE=${#TEST_DATA[@]}
