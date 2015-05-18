#!/bin/bash

set -e

export TESTDIR=/tmp/snabbtest

mkdir -p $TESTDIR

./snabb snabbnfv neutron2snabb \
    program/snabbnfv/test_fixtures/neutron_csv $TESTDIR cdn1

diff $TESTDIR/port0 program/snabbnfv/test_fixtures/nfvconfig/reference/port0
diff $TESTDIR/port2 program/snabbnfv/test_fixtures/nfvconfig/reference/port2

rm -r $TESTDIR
