#!/usr/bin/env bash
## This checks it can listen, send a command and get a
## response. It only tests the socket method of communicating
## with the listen command due to the difficulties of testing
## interactive scripts.
SKIPPED_CODE=43

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Verify we have the "nc" tool, used to communicate with sockets
# if we don't have it we just have to skip this test.
which nc &> /dev/null
if [[ $? -ne 0 ]]; then
   echo "No 'nc' tool present, unable to run test." 1&>2
   exit $SKIPPED_CODE
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

# Start the listen command with a socket
SOCKET_PATH="/tmp/snabb-test-listen-sock-$SNABB_NAME"
./snabb config listen --socket "$SOCKET_PATH" "$SNABB_NAME" &> /dev/null &

# It shouldn't take long but wait a short while for the socket
# to be created.
sleep 1

# Create input and output fifo's to communicate.
LISTEN_IN=$(mktemp -u)
LISTEN_OUT=$(mktemp -u)
mkfifo "$LISTEN_IN"
mkfifo "$LISTEN_OUT"

# Start a communication with the listen program
(cat "$LISTEN_IN" | nc -U "$SOCKET_PATH" > "$LISTEN_OUT") &

# Get the PID of nc so it can be easily stopped later
NC_PID=$!

# Finally, lets send a get command.
GET_CMD="{ \"id\": \"0\", \"verb\": \"get\", \"path\": \"/routes/route[addr=1.2.3.4]/port\" }"
echo "$GET_CMD" > "$LISTEN_IN"

# Sleep a short amount of time to let it respond, one second should be more than plenty
sleep 1

# Read the response from the listen command
GET_CMD_RESPONSE=$(cat "$LISTEN_OUT")

# Check the response as best I can, I'll  use python as it's common to most.
PARSED_GET_RESPONSE=$(echo $GET_CMD_RESPONSE | python -c "
import json, sys

print(json.loads(sys.stdin.read(200))[\"status\"])"
)

# Test the status is "ok"
assert_equal "$PARSED_GET_RESPONSE" "ok"

# Finally end all the programs we've spawned.
stop_if_running "$NC_PID"
stop_lwaftr_bench
