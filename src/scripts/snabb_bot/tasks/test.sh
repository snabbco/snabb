#!/bin/bash

# Run tests. 

cd src/
test_out=$(sudo make test 2>&1)

if [ "$?" = "0" ]; then
    echo "Tests successful."
else
    echo "Tests failed. See test output below:"
    echo
    echo "$test_out"
fi

sudo rm -rf testlog/
