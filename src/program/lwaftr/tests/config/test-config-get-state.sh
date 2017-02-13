#!/usr/bin/env bash
## This makes various queries to snabb config get-state to verify
## that it will run and produce values. The script has no way of
## validating the accuracy of the values, but it'll check it works.

# TEST_DIR is set by the caller, and passed onward.
export TEST_DIR
source ${TEST_DIR}/common.sh

check_for_root

# CONFIG_TEST_DIR is also set by the caller.
source ${CONFIG_TEST_DIR}/test_env.sh

echo "Testing config get state"

# Come up with a name for the lwaftr.
SNABB_NAME="`random_name`"

# Start the bench command.
start_lwaftr_bench $SNABB_NAME

# Select a few at random which should have non-zero results.
IN_IPV4="`./snabb config get-state $SNABB_NAME /softwire-state/in-ipv4-bytes`"
if [[ "$IN_IPV4" == "0" ]]; then
    exit_on_error "Counter should not show zero."
fi

OUT_IPV4="`./snabb config get-state $SNABB_NAME /softwire-state/out-ipv4-bytes`"
if [[ "$IN_IPV4" == "0" ]]; then
    exit_on_error "Counter should not show zero."
fi

./snabb config get-state "$SNABB_NAME" / > /dev/null
assert_equal "$?" "0"

stop_lwaftr_bench
