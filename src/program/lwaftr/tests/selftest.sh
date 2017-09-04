#!/usr/bin/env bash

# Entry point for Python tests.
#
# Make it work from wherever this script is called, and let tests know.
export TESTS_DIR=`dirname "$0"`
export PYTHONPATH=${TESTS_DIR}

# Only run tests in the passed subdirectory of $TESTS_DIR.
if [[ -n $1 ]]; then
    START_DIR=${TESTS_DIR}/$1/
else
    START_DIR=${TESTS_DIR}
fi

# Start discovery from this script's directory, the root of the "tests" subtree,
# or one of its subdirectories, if passed as first argument to this script.
# Look for unittests in all files whose name ends with "_test.py".
# List all executed tests, don't show just dots.
python3 -m unittest discover \
    --start-directory "${START_DIR}" \
    --pattern "*_test.py" \
    --verbose
