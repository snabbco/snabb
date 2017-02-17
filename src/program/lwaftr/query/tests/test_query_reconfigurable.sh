#!/usr/bin/env bash

TEST_NAME="lwaftr query --reconfigurable"

# TEST_DIR is set by the caller, and passed onward.
export TEST_DIR
source ${TEST_DIR}/common.sh || exit $?

check_nics_available "$TEST_NAME"
check_commands_available "$TEST_NAME" tmux

# QUERY_TEST_DIR is also set by the caller.
source ${QUERY_TEST_DIR}/test_env.sh || exit $?

echo "Testing ${TEST_NAME}"

trap query_cleanup EXIT HUP INT QUIT TERM

LWAFTR_NAME=lwaftr-$$
LWAFTR_CONF=${TEST_DIR}/data/no_icmp.conf

# Launch "lwaftr run". Do not break the "lwaftr run --reconfigurable" string,
# see get_lwaftr_leader in common.sh .
CMD_LINE="./snabb lwaftr run --reconfigurable --name $LWAFTR_NAME"
CMD_LINE+=" --conf $LWAFTR_CONF --v4 $SNABB_PCI0 --v6 $SNABB_PCI1"
tmux_launch "$CMD_LINE" "lwaftr.log"
sleep 2

# Test query all.
test_lwaftr_query -l

# Test query by leader pid.
pid=$(get_lwaftr_leader)
if [[ -n "$pid" ]]; then
    test_lwaftr_query $pid
    test_lwaftr_query $pid "memuse-ipv"
    test_lwaftr_query_no_counters $pid counter-never-exists-123
fi

# Test query by follower pid.
pid=$(get_lwaftr_follower)
if [[ -n "$pid" ]]; then
    test_lwaftr_query $pid
    test_lwaftr_query $pid "memuse-ipv"
    test_lwaftr_query_no_counters $pid counter-never-exists-123
fi

# Test query by name.
test_lwaftr_query "--name $LWAFTR_NAME"
test_lwaftr_query "--name $LWAFTR_NAME memuse-ipv"
test_lwaftr_query_no_counters "--name $LWAFTR_NAME counter-never-exists-123"

exit 0
