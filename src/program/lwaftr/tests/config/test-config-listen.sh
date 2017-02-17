#!/usr/bin/env bash
## This checks it can listen, send a command and get a response.
## It only tests the socket method of communicating with the listen
## command due to the difficulties of testing interactive scripts.

TEST_NAME="config listen"

# TEST_DIR is set by the caller, and passed onward.
export TEST_DIR
source ${TEST_DIR}/common.sh || exit $?

# Verify we have the "nc" tool, used to communicate with sockets,
# and the "python" interpreter available.
# If we don't have them, we just have to skip this test.
check_commands_available "$TEST_NAME" nc python

# CONFIG_TEST_DIR is also set by the caller.
source ${CONFIG_TEST_DIR}/test_env.sh || exit $?

echo "Testing ${TEST_NAME}"

# Come up with a name for the lwaftr.
SNABB_NAME=lwaftr-$$

# Start the bench command.
start_lwaftr_bench $SNABB_NAME

# Start the listen command with a socket.
SOCKET_PATH="/tmp/snabb-test-listen-sock-$SNABB_NAME"
./snabb config listen --socket "$SOCKET_PATH" "$SNABB_NAME" &> /dev/null &

# Wait a short while for the socket to be created; it shouldn't take long.
sleep 1

# Create input and output FIFOs to communicate.
LISTEN_IN=$(mktemp -u)
LISTEN_OUT=$(mktemp -u)
mkfifo "$LISTEN_IN"
mkfifo "$LISTEN_OUT"

# Start a communication with the listen program.
(cat "$LISTEN_IN" | nc -U "$SOCKET_PATH" > "$LISTEN_OUT") &

# Get the PID of nc so it can be easily stopped later.
NC_PID=$!

# Send a get command.
GET_CMD="{ \"id\": \"0\", \"verb\": \"get\", \"path\": \"/routes/route[addr=1.2.3.4]/port\" }"
echo "$GET_CMD" > "$LISTEN_IN"

# Sleep a short amount of time to let it respond;
# one second should be more than plenty.
sleep 1

# Read the response from the listen command.
GET_CMD_RESPONSE=$(cat "$LISTEN_OUT")

# Check the response as best I can, I'll  use python as it's common to most.
PARSED_GET_RESPONSE=$(echo $GET_CMD_RESPONSE | python -c "
import json, sys

print(json.loads(sys.stdin.read(200))[\"status\"])"
)

# Test the status is "ok".
assert_equal "$PARSED_GET_RESPONSE" "ok"

# Finally end all the programs we've spawned.
stop_if_running "$NC_PID"
stop_lwaftr_bench
