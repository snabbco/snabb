#!/usr/bin/env bash
## This adds a softwire section and then checks it can be got
## back and that all the values are as they should be.

TEST_NAME="config remove"

# TEST_DIR is set by the caller, and passed onward.
export TEST_DIR
source ${TEST_DIR}/common.sh || exit $?

# CONFIG_TEST_DIR is also set by the caller.
source ${CONFIG_TEST_DIR}/test_env.sh || exit $?

echo "Testing ${TEST_NAME}"

# Come up with a name for the lwaftr.
SNABB_NAME=lwaftr-$$

# Start the bench command.
start_lwaftr_bench $SNABB_NAME

# Verify that the thing we want to remove actually exists.
./snabb config get "$SNABB_NAME" /softwire-config/binding-table/softwire[ipv4=178.79.150.2][psid=7850]/ &> /dev/null
assert_equal "$?" "0"

# Remove it.
./snabb config remove "$SNABB_NAME" /softwire-config/binding-table/softwire[ipv4=178.79.150.2][psid=7850]/ &> /dev/null
assert_equal "$?" "0"

# Verify we can't find it.
./snabb config get "$SNABB_NAME" /softwire-config/binding-table/softwire[ipv4=178.79.150.2][psid=7850]/ &> /dev/null || true
assert_equal "$?" "0"

stop_lwaftr_bench
