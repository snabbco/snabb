#!/bin/bash

set -e

export TESTDIR=/tmp/snabbtest

mkdir -p $TESTDIR

./snabb designs/neutron/neutron2snabb \
    test_fixtures/neutron_csv $TESTDIR cdn1

diff $TESTDIR/port0 test_fixtures/nfvconfig/reference/port0
diff $TESTDIR/port2 test_fixtures/nfvconfig/reference/port2

rm -r $TESTDIR
