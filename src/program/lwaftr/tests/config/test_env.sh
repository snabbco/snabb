#!/usr/bin/env bash

# TEST_DIR is set by the caller.
source ${TEST_DIR}/common.sh || exit $?

DATA_DIR="${TEST_DIR}/data"
BENCHDATA_DIR="${TEST_DIR}/benchdata"

# Start the "lwaftr bench" process. The first parameter is the command name.
# The process should end when the script ends; however, if something goes wrong
# and it doesn't end correctly, a duration is set to prevent it running indefinitely.
function start_lwaftr_bench {
    ./snabb lwaftr bench --reconfigurable --bench-file /dev/null --name "$1" \
                         --duration 30 \
                         program/lwaftr/tests/data/icmp_on_fail.conf \
                         program/lwaftr/tests/benchdata/ipv{4,6}-0550.pcap &> /dev/null &

    # It takes a little time for lwaftr to properly start.
    sleep 2
}

function stop_lwaftr_bench {
    # Get the job number for lwaftr bench.
    local jobid=`jobs | grep -i "lwaftr bench" | awk '{print $1}' | tr -d '[]+'`
    kill "%$jobid"
    # Wait until it's shutdown.
    wait &> /dev/null
}

function stop_if_running {
    # Check if it's running, if not, job done.
    kill -0 $1 &> /dev/null
    if [[ $? -ne 0 ]]; then
        return
    fi

    # It's running, try and close it nicely.
    kill $1
    wait &> /dev/null
}
