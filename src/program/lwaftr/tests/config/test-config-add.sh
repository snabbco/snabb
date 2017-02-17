#!/usr/bin/env bash
## This adds a softwire section and then checks it can be got
## back and that all the values are as they should be.

TEST_NAME="config add"

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

# IP to test with.
TEST_SOFTWIRE="{ ipv4 1.2.3.4; psid 72; b4-ipv6 ::1; br 1; }"
./snabb config add "$SNABB_NAME" "/softwire-config/binding-table/softwire" "$TEST_SOFTWIRE"

# Check it can get this just fine.
./snabb config get $SNABB_NAME /softwire-config/binding-table/softwire[ipv4=1.2.3.4][psid=72] &> /dev/null
assert_equal $? 0

# Test that the b4-ipv4 is correct.
ADDED_B4_IPV4="`./snabb config get $SNABB_NAME /softwire-config/binding-table/softwire[ipv4=1.2.3.4][psid=72]/b4-ipv6`"
assert_equal "$ADDED_B4_IPV4" "::1"

stop_lwaftr_bench
