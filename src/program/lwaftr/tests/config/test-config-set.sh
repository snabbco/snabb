#!/usr/bin/env bash
## This checks you can set values, it'll then perform a get to
## verify the value set is the value that is got too.

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Load the tools to be able to test stuff.
BASEDIR="`pwd`"
cd "`dirname \"$0\"`"
source tools.sh
cd $BASEDIR

# Come up with a name for the lwaftr
SNABB_NAME="`random_name`"

# Start the bench command.
start_lwaftr_bench $SNABB_NAME

# IP to test with.
TEST_IPV4="208.118.235.148"
./snabb config set "$SNABB_NAME" "/softwire-config/external-interface/ip" "$TEST_IPV4"
SET_IP="`./snabb config get \"$SNABB_NAME\" \"/softwire-config/external-interface/ip\"`"
assert_equal "$SET_IP" "$TEST_IPV4"

# Set a value in a list
TEST_IPV6="::1"
TEST_IPV4="178.79.150.15"
TEST_PSID="0"
./snabb config set "$SNABB_NAME" "/softwire-config/binding-table/softwire[ipv4=$TEST_IPV4][psid=$TEST_PSID]/b4-ipv6" "$TEST_IPV6"
SET_IP="`./snabb config get \"$SNABB_NAME\" \"/softwire-config/binding-table/softwire[ipv4=$TEST_IPV4][psid=$TEST_PSID]/b4-ipv6\"`"
assert_equal "$SET_IP" "$TEST_IPV6"

# Check that the value above I just set is the same in the IETF schema
# We actually need to look this up backwards, lets just check the same
# IPv4 address was used as was used to set it above.
IETF_PATH="/softwire-config/binding/br/br-instances/br-instance[id=1]/binding-table/binding-entry[binding-ipv6info=::1]/binding-ipv4-addr"
IPV4_ADDR="`./snabb config get --schema=ietf-softwire $SNABB_NAME $IETF_PATH`"
assert_equal "$IPV4_ADDR" "$TEST_IPV4"

# Also check the portset, the IPv4 address alone isn't unique
IETF_PATH="/softwire-config/binding/br/br-instances/br-instance[id=1]/binding-table/binding-entry[binding-ipv6info=::1]/port-set/psid"
PSID="`./snabb config get --schema=ietf-softwire $SNABB_NAME $IETF_PATH`"
assert_equal "$PSID" "$TEST_PSID"

# Stop the lwaftr process.
stop_lwaftr_bench
