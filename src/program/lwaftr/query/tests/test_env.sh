#!/usr/bin/env bash

TEMP_FILE=$(mktemp)

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
    rm -f $TEMP_FILE
    exit
}

function fatal {
    local msg=$1
    echo "Error: $msg"
    exit 1
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
    ./snabb lwaftr query $@ > $TEMP_FILE
    local lineno=`cat $TEMP_FILE | wc -l`
    if [[ $lineno -gt 1 ]]; then
        echo "Success: lwaftr query $*"
    else
        fatal "lwaftr query $*"
    fi
}
