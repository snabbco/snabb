#!/usr/bin/env bash
## Test querying from a known config. The test is dependent on the values
## in the test data files, however this allows for testing basic "getting".
## It performs numerous gets on different paths.

TEST_NAME="config get"

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

# Check we can get a known value from the config.
INTERNAL_IP="`./snabb config get $SNABB_NAME /softwire-config/internal-interface/ip`"
assert_equal "$INTERNAL_IP" "8:9:a:b:c:d:e:f"

EXTERNAL_IP="`./snabb config get $SNABB_NAME /softwire-config/external-interface/ip`"
assert_equal "$EXTERNAL_IP" "10.10.10.10"

BT_B4_IPV6="`./snabb config get $SNABB_NAME /softwire-config/binding-table/softwire[ipv4=178.79.150.233][psid=7850]/b4-ipv6`"
assert_equal "$BT_B4_IPV6" "127:11:12:13:14:15:16:128"

# Finally test getting a value from the ietf-softwire schema.
IETF_PATH="/softwire-config/binding/br/br-instances/br-instance[id=1]/binding-table/binding-entry[binding-ipv6info=127:22:33:44:55:66:77:128]/binding-ipv4-addr"
BINDING_IPV4="`./snabb config get --schema=ietf-softwire $SNABB_NAME $IETF_PATH`"
assert_equal "$?" "0"
assert_equal "$BINDING_IPV4" "178.79.150.15"

stop_lwaftr_bench
