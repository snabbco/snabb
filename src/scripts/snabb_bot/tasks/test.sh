#!/bin/bash

# Run tests. 

cd src/
test_out=$(sudo \
    SNABB_TEST_INTEL10G_PCIDEVA=0000:86:00.0 \
    SNABB_TEST_INTEL10G_PCIDEVB=0000:86:00.1 \
    flock -x /tmp/86:00.lock \
    make test 2>&1)

EXIT=1

if echo "$test_out" | grep ERROR > /dev/null; then
    echo "Tests failed. See test output below:"
    echo
    echo "$test_out"
else
    echo "Tests successful."
    echo
    echo "$test_out"
    EXIT=0
fi

echo
for log in testlog/*; do
    echo "BEGIN $log"
    cat "$log"
    echo
done

sudo rm -rf testlog/
exit $EXIT
