#!/usr/bin/env bash

# Make it work from wherever this script is called, and let tests know.
export TESTS_DIR=`dirname "$0"`

# Entry point for Python tests.
#
# Start discovery from this script's directory, the root of the "tests" subtree.
# Find unittests in all Python files ending with "_test.py".
# List all executed tests, don't show just dots.
python3 -m unittest discover \
    --start-directory "${TESTS_DIR}" \
    --pattern "*_test.py" \
    --verbose
