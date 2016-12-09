#!/usr/bin/env bash
## This makes verious quries to snabb config get-state to try and verify
## that it will run and produce values. The script has no way of
## validating the acuracy of the values but it'll check it works.

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

# Selecting a few at random which should have non-zero results
IN_IPV4="`snabb config get-state $SNABB_NAME /softwire-state/in-ipv4-bytes`"
if [[ "$IN_IPV4" == "0" ]]; then
	produce_error "Counter should not show zero."
fi

OUT_IPV4="`snabb config get-state $SNABB_NAME /softwire-state/out-ipv4-bytes`"
if [[ "$IN_IPV4" == "0" ]]; then
	produce_error "Counter should not show zero."
fi

./snabb config get-state "$SNABB_NAME" /
assert_equal "$?" "0"
