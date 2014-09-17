#!/bin/bash

# Run tests. 

cd src/
test_out=$(sudo make test 2>&1)

sudo rm -rf testlog/

if echo "$test_out" | grep ERROR > /dev/null; then
    echo "Tests failed. See test output below:"
    echo
    echo "$test_out"
    exit 1
else
    echo "Tests successful."
    echo
    echo "$test_out"
    exit 0
fi
