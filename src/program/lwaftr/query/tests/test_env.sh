#!/usr/bin/env bash

# TEST_DIR is set by the caller.
source ${TEST_DIR}/common.sh || exit $?

TEST_OUTPUT_FNAME=$(mktemp)

# Terminate the "lwaftr run" command, remove the output file, and exit.
function query_cleanup {
    ps aux | grep $SNABB_PCI0 | grep -v "grep" | awk '{print $2}' | xargs kill 2> /dev/null
    ps aux | grep "snabb lwaftr query" | grep -v "grep" | awk '{print $2}' | xargs kill 2> /dev/null
    rm -f $TEST_OUTPUT_FNAME
    exit
}

function get_lwaftr_leader {
    local pids=$(ps aux | grep "\-\-reconfigurable" | grep $SNABB_PCI0 | grep -v "grep" | awk '{print $2}')
    for pid in ${pids[@]}; do
        if [[ -d "/var/run/snabb/$pid" ]]; then
            echo $pid
        fi
    done
}

function get_lwaftr_follower {
    local leaders=$(ps aux | grep "\-\-reconfigurable" | grep $SNABB_PCI0 | grep -v "grep" | awk '{print $2}')
    for pid in $(ls /var/run/snabb); do
        for leader in ${leaders[@]}; do
            if [[ -L "/var/run/snabb/$pid/group" ]]; then
                local target=$(ls -l /var/run/snabb/$pid/group | awk '{print $11}' | grep -oe "[0-9]\+")
                if [[ "$leader" == "$target" ]]; then
                    echo $pid
                fi
            fi
        done
    done
}

function get_lwaftr_instance {
    local pids=$(ps aux | grep $SNABB_PCI0 | awk '{print $2}')
    for pid in ${pids[@]}; do
        if [[ -d "/var/run/snabb/$pid/apps/lwaftr" ]]; then
            echo $pid 
        fi
    done
}

function test_lwaftr_query {
    ./snabb lwaftr query $@ > $TEST_OUTPUT_FNAME
    local lineno=`cat $TEST_OUTPUT_FNAME | wc -l`
    if [[ $lineno -gt 1 ]]; then
        echo "Success: lwaftr query $*"
    else
        cat $TEST_OUTPUT_FNAME
        exit_on_error "Error: lwaftr query $*"
    fi
}

function test_lwaftr_query_no_counters {
    ./snabb lwaftr query $@ > $TEST_OUTPUT_FNAME
    local lineno=`cat $TEST_OUTPUT_FNAME | wc -l`
    if [[ $lineno -eq 1 ]]; then
        echo "Success: lwaftr query no counters $*"
    else
        cat $TEST_OUTPUT_FNAME
        exit_on_error "Error: lwaftr query no counters $*"
    fi
}
