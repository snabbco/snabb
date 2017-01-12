#!/usr/bin/env bash

SKIPPED_CODE=43

if [[ -z "$SNABB_PCI0" ]]; then
    echo "SNABB_PCI0 not set"
    exit $SKIPPED_CODE
fi

if [[ -z "$SNABB_PCI1" ]]; then
    echo "SNABB_PCI1 not set"
    exit $SKIPPED_CODE
fi

LWAFTR_CONF=./program/lwaftr/tests/data/no_icmp.conf

function tmux_launch {
    command="$2 2>&1 | tee $3"
    if [ -z "$tmux_session" ]; then
        tmux_session=test_env-$$
        tmux new-session -d -n "$1" -s $tmux_session "$command"
    else
        tmux new-window -a -d -n "$1" -t $tmux_session "$command"
    fi
}

function kill_lwaftr {
    ps aux | grep $SNABB_PCI0 | awk '{print $2}' | xargs kill 2>/dev/null
}

function cleanup {
    kill_lwaftr
    exit
}

trap cleanup EXIT HUP INT QUIT TERM

function get_lwaftr_instance {
    pids=$(ps aux | grep $SNABB_PCI0 | awk '{print $2}')
    for pid in ${pids[@]}; do
        if [[ -d "/var/run/snabb/$pid/apps/lwaftr" ]]; then
            echo $pid 
        fi
    done
}

function fatal {
    local msg=$1
    echo "Error: $msg"
    exit 1
}

function test_lwaftr_query {
    local pid=$1
    # FIXME: Sometimes lwaftr query gets stalled. Add timeout.
    local lineno=`timeout 1 ./snabb lwaftr query $pid | wc -l`
    if [[ $lineno -gt 1 ]]; then
        echo "Success: lwaftr query $pid"
    else
        fatal "lwaftr query $pid"
    fi
}

function test_lwaftr_query_filter {
    local pid=$1
    local filter=$2
    local lineno=`timeout 1 ./snabb lwaftr query $pid $filter | wc -l`
    if [[ $lineno -gt 1 ]]; then
        echo "Success: lwaftr query $pid $filter"
    else
        fatal "lwaftr query $pid"
    fi
}

# Run lwAFTR.
tmux_launch "lwaftr" "./snabb lwaftr run --reconfigurable --conf $LWAFTR_CONF --v4 $SNABB_PCI0 --v6 $SNABB_PCI1"
sleep 2

# Run tests.
pid=$(get_lwaftr_instance)
if [[ -n "$pid" ]]; then
    test_lwaftr_query $pid
    test_lwaftr_query $pid -l
    test_lwaftr_query_filter $pid "memuse"
    test_lwaftr_query_filter $pid "in-ipv4"
fi
