#!/usr/bin/env bash

# Entry point for Python tests.
#
# Make it work from wherever this script is called, and let tests know.
export TESTS_DIR=`dirname "$0"`
export PYTHONPATH=${TESTS_DIR}

# Only run tests in the chosen test file (without the _test.py suffix).
if [[ -n "$1" ]]; then
    TEST_WHAT=$1
else
    TEST_WHAT="*"
fi

# Create a directory for JIT migrated configs so that each configuration file
# can be contain the correct PCI device we need to test with. If it doesn't
# already exist (it shouldn't really) then make it.
export JIT_CONFIG_DIR="/tmp/snabb-configs"

if [ ! -d $JIT_CONFIG_DIR ]; then
    mkdir $JIT_CONFIG_DIR
fi

# Start discovery from this script's directory, the root of the "tests" subtree.
# Look for unittests in all files whose name ends with "_test.py", or just one
# of them, if its prefix (without _test.py) was passed as first argument.
# List all executed tests, don't show just dots.
python3 -m unittest discover \
    --start-directory "${TESTS_DIR}" \
    --pattern "${TEST_WHAT}_test.py" \
    --verbose

# Remove the config dir as part of the cleanup.
rm -r $JIT_CONFIG_DIR
