#!/usr/bin/env bash
## This adds a softwire section and then checks it can be got
## back and that all the values are as they should be.

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

# Firstly lets verify that the thing we want to remove actually exists
./snabb config get "$SNABB_NAME" /softwire-config/binding-table/softwire[ipv4=178.79.150.2][psid=7850]/ &> /dev/null
assert_equal "$?" "0"

# Then lets remove it
./snabb config remove "$SNABB_NAME" /softwire-config/binding-table/softwire[ipv4=178.79.150.2][psid=7850]/ &> /dev/null
assert_equal "$?" "0"

# Then lets verify we can't find it
./snabb config get "$SNABB_NAME" /softwire-config/binding-table/softwire[ipv4=178.79.150.2][psid=7850]/ &> /dev/null || true
assert_equal "$?" "0"

stop_lwaftr_bench
